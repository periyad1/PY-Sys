import AppKit
import SwiftUI
import IOKit.pwr_mgt
import ApplicationServices

enum ToggleID: String, CaseIterable, Identifiable {
    case quitAll, keepAwake, lockScreen, screenSaver, darkMode, hideDock, lockDock, autoHideMenuBar, hideDesktopIcons, cleanScreen, cleanKeyboard
    var id: String { rawValue }

    var title: String {
        switch self {
        case .quitAll: return tr("Tutup semua app", "Quit all apps")
        case .keepAwake: return tr("Layar tetap menyala", "Keep screen on")
        case .lockScreen: return tr("Kunci layar", "Lock screen")
        case .screenSaver: return "Screen saver"
        case .darkMode: return tr("Mode gelap", "Dark mode")
        case .hideDock: return tr("Sembunyikan Dock", "Hide Dock")
        case .lockDock: return tr("Kunci Dock", "Lock Dock")
        case .autoHideMenuBar: return tr("Sembunyikan menu bar", "Auto-hide menu bar")
        case .hideDesktopIcons: return tr("Sembunyikan file desktop", "Hide desktop files")
        case .cleanScreen: return tr("Bersihkan layar", "Clean screen")
        case .cleanKeyboard: return tr("Bersihkan keyboard", "Clean keyboard")
        }
    }

    var help: String {
        switch self {
        case .quitAll: return tr("Tutup semua aplikasi yang terbuka seperti ⌘Q (kecuali whitelist)", "Quit every open app like ⌘Q (except whitelisted ones)")
        case .keepAwake: return tr("Mencegah layar tidur selama aktif", "Prevents the display from sleeping while on")
        case .lockScreen: return tr("Kunci Mac sekarang", "Lock the Mac now")
        case .screenSaver: return tr("Jalankan screen saver", "Start the screen saver")
        case .darkMode: return tr("Ganti tampilan terang/gelap", "Switch light/dark appearance")
        case .hideDock: return tr("Dock muncul hanya saat kursor di tepi layar", "Dock appears only at the screen edge")
        case .lockDock: return tr("Kunci isi, ukuran dan posisi Dock", "Lock Dock contents, size and position")
        case .autoHideMenuBar: return tr("Menu bar muncul hanya saat kursor di atas", "Menu bar appears only at the top edge")
        case .hideDesktopIcons: return tr("Sembunyikan semua ikon di desktop", "Hide all icons on the desktop")
        case .cleanScreen: return tr("Layar hitam untuk dilap; klik atau Esc untuk keluar", "Black screen for wiping; click or Esc to exit")
        case .cleanKeyboard: return tr("Kunci keyboard 30 detik untuk dilap", "Lock the keyboard for 30 s to wipe it")
        }
    }

    var icon: String {
        switch self {
        case .quitAll: return "xmark.square"
        case .keepAwake: return "sun.max"
        case .lockScreen: return "lock"
        case .screenSaver: return "tv"
        case .darkMode: return "circle.lefthalf.filled"
        case .hideDock: return "dock.rectangle"
        case .lockDock: return "pin"
        case .autoHideMenuBar: return "menubar.rectangle"
        case .hideDesktopIcons: return "eye.slash"
        case .cleanScreen: return "display"
        case .cleanKeyboard: return "keyboard"
        }
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class CleanScreenView: NSView {
    var onExit: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { onExit?() }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { onExit?() } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()
        let text = tr("Klik atau tekan Esc untuk keluar", "Click or press Esc to exit") as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor(white: 0.35, alpha: 1)]
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: 40), withAttributes: attrs)
    }
}

struct KeyboardLockView: View {
    @ObservedObject var toggles = SystemToggles.shared
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "keyboard").font(.system(size: 28))
            Text(tr("Keyboard terkunci untuk dibersihkan", "Keyboard locked for cleaning")).font(.headline)
            Text(tr("Terbuka otomatis dalam \(toggles.keyboardSecondsLeft) detik", "Unlocks automatically in \(toggles.keyboardSecondsLeft) s"))
                .foregroundStyle(.secondary)
            Button(tr("Buka kunci sekarang", "Unlock now")) { toggles.unlockKeyboard() }
        }
        .padding(24)
        .frame(width: 340)
    }
}

final class SystemToggles: ObservableObject {
    static let shared = SystemToggles()

    @Published private(set) var on: Set<ToggleID> = []
    @Published var message: String?
    @Published private(set) var keyboardSecondsLeft = 0

    private var assertionID: IOPMAssertionID = 0
    private var overlays: [NSWindow] = []
    private var keyboardPanel: NSPanel?
    private var keyboardTimer: Timer?
    private var keyboardSource: CFRunLoopSource?
    var keyboardTap: CFMachPort?

    // MARK: Status

    func refresh() {
        var s = Set<ToggleID>()
        if assertionID != 0 { s.insert(.keepAwake) }
        if (globalPref("AppleInterfaceStyle") as? String) == "Dark" { s.insert(.darkMode) }
        if boolPref("autohide", "com.apple.dock", default: false) { s.insert(.hideDock) }
        if boolPref("contents-immutable", "com.apple.dock", default: false) { s.insert(.lockDock) }
        if (globalPref("_HIHideMenuBar") as? NSNumber)?.boolValue == true { s.insert(.autoHideMenuBar) }
        if !boolPref("CreateDesktop", "com.apple.finder", default: true) { s.insert(.hideDesktopIcons) }
        on = s
    }

    private func globalPref(_ key: String) -> Any? {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        return CFPreferencesCopyAppValue(key as CFString, kCFPreferencesAnyApplication)
    }

    private func boolPref(_ key: String, _ domain: String, default def: Bool) -> Bool {
        CFPreferencesAppSynchronize(domain as CFString)
        guard let v = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else { return def }
        return (v as? NSNumber)?.boolValue ?? def
    }

    // MARK: Aksi

    func perform(_ t: ToggleID) {
        message = nil
        switch t {
        case .quitAll:
            quitAllApps()
        case .keepAwake:
            if assertionID == 0 {
                var id: IOPMAssertionID = 0
                if IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                               IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "PY-Sys: keep screen on" as CFString, &id) == kIOReturnSuccess {
                    assertionID = id
                }
            } else {
                IOPMAssertionRelease(assertionID)
                assertionID = 0
            }
        case .lockScreen:
            typealias LockFn = @convention(c) () -> Int32
            if let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
               let sym = dlsym(h, "SACLockScreenImmediate") {
                _ = unsafeBitCast(sym, to: LockFn.self)()
            } else {
                run("/usr/bin/pmset", ["displaysleepnow"])
            }
        case .screenSaver:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"))
        case .darkMode:
            appleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
        case .hideDock:
            appleScript("tell application \"System Events\" to tell dock preferences to set autohide to not autohide")
        case .autoHideMenuBar:
            appleScript("tell application \"System Events\" to tell dock preferences to set autohide menu bar to not autohide menu bar")
        case .lockDock:
            let lock = !on.contains(.lockDock)
            for key in ["contents-immutable", "size-immutable", "position-immutable"] {
                run("/usr/bin/defaults", ["write", "com.apple.dock", key, "-bool", lock ? "true" : "false"])
            }
            run("/usr/bin/killall", ["Dock"])
        case .hideDesktopIcons:
            let hide = !on.contains(.hideDesktopIcons)
            run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", hide ? "false" : "true"])
            run("/usr/bin/killall", ["Finder"])
        case .cleanScreen:
            showCleanScreen()
        case .cleanKeyboard:
            lockKeyboard(seconds: 30)
        }
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.refresh() }
    }

    private func appleScript(_ source: String) {
        var err: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&err)
        if err != nil {
            message = tr("Izinkan PY-Sys mengontrol System Events di System Settings → Privacy & Security → Automation.",
                         "Allow PY-Sys to control System Events in System Settings → Privacy & Security → Automation.")
        }
    }

    private func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
    }

    // MARK: Tutup semua app

    /// Menutup semua aplikasi biasa dengan sopan (seperti ⌘Q): dialog "Simpan?" tetap muncul.
    /// Finder, PY-Sys dan aplikasi whitelist Cryo dilewati, kecuali dicentang di dialog konfirmasi.
    private func quitAllApps() {
        let core = AetherCore.shared
        let skip: Set<String> = ["com.apple.finder", Bundle.main.bundleIdentifier ?? "id.pysys.app"]
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid()
                && !skip.contains($0.bundleIdentifier ?? "")
        }
        let whitelisted = apps.filter { core.settings.whitelist.contains($0.bundleIdentifier ?? "") }
        let normal = apps.filter { !core.settings.whitelist.contains($0.bundleIdentifier ?? "") }
        guard !apps.isEmpty else {
            message = tr("Tidak ada aplikasi yang terbuka.", "No open apps.")
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = tr("Tutup \(normal.count) aplikasi?", "Quit \(normal.count) apps?")
        let names = normal.compactMap { $0.localizedName }.prefix(12).joined(separator: ", ")
        alert.informativeText = (names.isEmpty ? tr("Semua aplikasi yang terbuka ada di whitelist.", "Every open app is whitelisted.") : names)
            + tr("\n\nAplikasi dengan dokumen belum tersimpan akan menanyakan dulu.",
                 "\n\nApps with unsaved documents will ask first.")
        if !whitelisted.isEmpty {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = tr("Ikut tutup \(whitelisted.count) app whitelist (\(whitelisted.compactMap { $0.localizedName }.prefix(4).joined(separator: ", ")))",
                                                "Also quit \(whitelisted.count) whitelisted apps (\(whitelisted.compactMap { $0.localizedName }.prefix(4).joined(separator: ", ")))")
            alert.suppressionButton?.state = .off
        }
        alert.addButton(withTitle: tr("Tutup semua", "Quit all"))
        alert.addButton(withTitle: tr("Batal", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let targets = normal + (alert.suppressionButton?.state == .on ? whitelisted : [])
        for app in targets {
            if core.freezer.isFrozen(app.processIdentifier) { core.freezer.thaw(app.processIdentifier) }  // app beku tak bisa menjawab
            app.terminate()
        }
        message = tr("Meminta \(targets.count) aplikasi menutup…", "Asked \(targets.count) apps to quit…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            let still = targets.filter { !$0.isTerminated }.compactMap { $0.localizedName }
            self.message = still.isEmpty
                ? tr("\(targets.count) aplikasi sudah ditutup.", "\(targets.count) apps quit.")
                : tr("Masih terbuka (menunggu Anda): \(still.joined(separator: ", "))", "Still open (waiting for you): \(still.joined(separator: ", "))")
        }
    }

    // MARK: Bersihkan layar

    private func showCleanScreen() {
        closeCleanScreen()
        for screen in NSScreen.screens {
            let w = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.level = .screenSaver
            w.backgroundColor = .black
            w.isOpaque = true
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let v = CleanScreenView(frame: NSRect(origin: .zero, size: screen.frame.size))
            v.onExit = { [weak self] in self?.closeCleanScreen() }
            w.contentView = v
            w.setFrame(screen.frame, display: true)
            w.makeKeyAndOrderFront(nil)
            overlays.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        if let first = overlays.first {
            first.makeKey()
            first.makeFirstResponder(first.contentView)
        }
    }

    private func closeCleanScreen() {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
    }

    // MARK: Bersihkan keyboard

    private func lockKeyboard(seconds: Int) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            message = tr("Izinkan PY-Sys di System Settings → Privacy & Security → Accessibility, lalu coba lagi.",
                         "Allow PY-Sys in System Settings → Privacy & Security → Accessibility, then try again.")
            return
        }
        unlockKeyboard()
        let types: [UInt64] = [UInt64(CGEventType.keyDown.rawValue), UInt64(CGEventType.keyUp.rawValue),
                               UInt64(CGEventType.flagsChanged.rawValue), 14 /* tombol media/kecerahan */]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: { _, type, event, _ in
                                              if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                                                  if let t = SystemToggles.shared.keyboardTap { CGEvent.tapEnable(tap: t, enable: true) }
                                                  return Unmanaged.passUnretained(event)
                                              }
                                              return nil
                                          }, userInfo: nil) else {
            message = tr("Keyboard tidak bisa dikunci.", "Could not lock the keyboard.")
            return
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        keyboardTap = tap
        keyboardSource = src
        keyboardSecondsLeft = seconds

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 180),
                            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: KeyboardLockView())
        panel.center()
        panel.orderFrontRegardless()
        keyboardPanel = panel

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.keyboardSecondsLeft -= 1
            if self.keyboardSecondsLeft <= 0 { self.unlockKeyboard() }
        }
        RunLoop.main.add(timer, forMode: .common)
        keyboardTimer = timer
    }

    func unlockKeyboard() {
        if let t = keyboardTap {
            CGEvent.tapEnable(tap: t, enable: false)
            CFMachPortInvalidate(t)
        }
        if let s = keyboardSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        keyboardTap = nil
        keyboardSource = nil
        keyboardTimer?.invalidate()
        keyboardTimer = nil
        keyboardSecondsLeft = 0
        keyboardPanel?.orderOut(nil)
        keyboardPanel = nil
    }
}

// MARK: - Utility › Toggles

struct TogglesTab: View {
    @ObservedObject var settings: Settings
    @ObservedObject private var toggles = SystemToggles.shared
    @ObservedObject private var ui = UIState.shared

    var body: some View {
        let items = ToggleID.allCases.filter { !settings.hiddenToggles.contains($0.rawValue) }
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: 4), spacing: 14) {
                ForEach(items) { item in
                    let active = toggles.on.contains(item)
                    Button { toggles.perform(item) } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(active ? Theme.accent : Color.secondary.opacity(0.18))
                                    .frame(width: 46, height: 46)
                                Image(systemName: item.icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(active ? Color.white : Color.primary)
                            }
                            Text(item.title)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(height: 30, alignment: .top)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(item.help)
                }
            }
            if let m = toggles.message {
                Text(m).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup(tr("Kelola fitur", "Feature management"), isExpanded: $ui.togglesManage) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ToggleID.allCases) { t in
                        Toggle(isOn: Binding(
                            get: { !settings.hiddenToggles.contains(t.rawValue) },
                            set: { show in
                                if show { settings.hiddenToggles.removeAll { $0 == t.rawValue } }
                                else if !settings.hiddenToggles.contains(t.rawValue) { settings.hiddenToggles.append(t.rawValue) }
                            })) {
                            Label(t.title, systemImage: t.icon)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .onAppear { toggles.refresh() }
    }
}
