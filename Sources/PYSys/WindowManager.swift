import AppKit
import SwiftUI
import ApplicationServices

// MARK: - Shortcut global (satu event tap untuk Window Manager & Clipboard)

final class HotkeyCenter: ObservableObject {
    static let shared = HotkeyCenter()
    @Published private(set) var running = false
    @Published var message: String?

    /// Kembalikan true bila tombol dipakai (event ditelan).
    var handlers: [(Int64, CGEventFlags) -> Bool] = []
    fileprivate var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var watcher: Timer?

    /// Setelah izin Accessibility diberikan, macOS tidak memberi tahu aplikasi. Jadi dicek ulang
    /// tiap 2 detik; begitu diizinkan, semua fitur yang butuh event tap dinyalakan otomatis.
    private func watchPermission() {
        guard watcher == nil else { return }
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard AXIsProcessTrusted() else { return }
            self?.watcher?.invalidate()
            self?.watcher = nil
            self?.ensure(prompt: false)
            ClickMenu.shared.apply(prompt: false)
            ScrollReverser.shared.apply(prompt: false)
        }
        RunLoop.main.add(t, forMode: .common)
        watcher = t
    }

    func ensure(prompt: Bool) {
        guard tap == nil else { running = true; message = nil; return }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            running = false
            message = tr("Menunggu izin Accessibility… Setelah PY-Sys dicentang di Privacy & Security → Accessibility, shortcut menyala sendiri dalam beberapa detik.",
                         "Waiting for Accessibility permission… Once PY-Sys is ticked in Privacy & Security → Accessibility, shortcuts turn on by themselves within seconds.")
            watchPermission()
            return
        }
        let mask = CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask,
                                        callback: { _, type, event, _ in
                                            let hc = HotkeyCenter.shared
                                            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                                                if let t = hc.tap { CGEvent.tapEnable(tap: t, enable: true) }
                                                return Unmanaged.passUnretained(event)
                                            }
                                            guard type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
                                                return Unmanaged.passUnretained(event)
                                            }
                                            let code = event.getIntegerValueField(.keyboardEventKeycode)
                                            let f = event.flags.intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift])
                                            for h in hc.handlers where h(code, f) { return nil }
                                            return Unmanaged.passUnretained(event)
                                        }, userInfo: nil) else {
            running = false
            message = tr("Izin sudah ada tetapi macOS belum menerapkannya. Keluar dari PY-Sys (Quit) lalu buka lagi.",
                         "Permission is granted but macOS hasn't applied it yet. Quit PY-Sys and open it again.")
            return
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        tap = t
        source = src
        running = true
        message = nil
    }
}

enum Key {
    static let left: Int64 = 123, right: Int64 = 124, down: Int64 = 125, up: Int64 = 126
    static let ret: Int64 = 36, c: Int64 = 8, d: Int64 = 2, f: Int64 = 3, g: Int64 = 5, e: Int64 = 14, t: Int64 = 17
    static let u: Int64 = 32, i: Int64 = 34, j: Int64 = 38, k: Int64 = 40, v: Int64 = 9, z: Int64 = 6
}

// MARK: - Window Manager

enum Snap: String, CaseIterable, Identifiable {
    case left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case maximize, center, nextDisplay, prevDisplay, restore
    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return tr("Separuh kiri", "Left half")
        case .right: return tr("Separuh kanan", "Right half")
        case .top: return tr("Separuh atas", "Top half")
        case .bottom: return tr("Separuh bawah", "Bottom half")
        case .topLeft: return tr("Kiri atas", "Top left")
        case .topRight: return tr("Kanan atas", "Top right")
        case .bottomLeft: return tr("Kiri bawah", "Bottom left")
        case .bottomRight: return tr("Kanan bawah", "Bottom right")
        case .leftThird: return tr("Sepertiga kiri", "Left third")
        case .centerThird: return tr("Sepertiga tengah", "Center third")
        case .rightThird: return tr("Sepertiga kanan", "Right third")
        case .leftTwoThirds: return tr("Dua pertiga kiri", "Left two thirds")
        case .rightTwoThirds: return tr("Dua pertiga kanan", "Right two thirds")
        case .maximize: return tr("Penuhi layar", "Maximize")
        case .center: return tr("Ke tengah", "Center")
        case .nextDisplay: return tr("Monitor berikutnya", "Next display")
        case .prevDisplay: return tr("Monitor sebelumnya", "Previous display")
        case .restore: return tr("Kembalikan ukuran", "Restore")
        }
    }

    var shortcut: String {
        switch self {
        case .left: return "⌃⌥←"
        case .right: return "⌃⌥→"
        case .top: return "⌃⌥↑"
        case .bottom: return "⌃⌥↓"
        case .topLeft: return "⌃⌥U"
        case .topRight: return "⌃⌥I"
        case .bottomLeft: return "⌃⌥J"
        case .bottomRight: return "⌃⌥K"
        case .leftThird: return "⌃⌥D"
        case .centerThird: return "⌃⌥F"
        case .rightThird: return "⌃⌥G"
        case .leftTwoThirds: return "⌃⌥E"
        case .rightTwoThirds: return "⌃⌥T"
        case .maximize: return "⌃⌥↩"
        case .center: return "⌃⌥C"
        case .nextDisplay: return "⌃⌥⌘→"
        case .prevDisplay: return "⌃⌥⌘←"
        case .restore: return "⌃⌥⌫"
        }
    }

    var symbol: String {
        switch self {
        case .left: return "rectangle.lefthalf.filled"
        case .right: return "rectangle.righthalf.filled"
        case .top: return "rectangle.tophalf.filled"
        case .bottom: return "rectangle.bottomhalf.filled"
        case .topLeft, .topRight, .bottomLeft, .bottomRight: return "square.grid.2x2"
        case .leftThird, .centerThird, .rightThird, .leftTwoThirds, .rightTwoThirds: return "rectangle.split.3x1"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .center: return "rectangle.center.inset.filled"
        case .nextDisplay: return "rectangle.portrait.and.arrow.right"
        case .prevDisplay: return "rectangle.portrait.and.arrow.forward"
        case .restore: return "arrow.uturn.backward"
        }
    }

    static func from(code: Int64, flags f: CGEventFlags) -> Snap? {
        let ca: CGEventFlags = [.maskControl, .maskAlternate]
        if f == ca.union(.maskCommand) {
            if code == Key.right { return .nextDisplay }
            if code == Key.left { return .prevDisplay }
            return nil
        }
        guard f == ca else { return nil }
        switch code {
        case Key.left: return .left
        case Key.right: return .right
        case Key.up: return .top
        case Key.down: return .bottom
        case Key.u: return .topLeft
        case Key.i: return .topRight
        case Key.j: return .bottomLeft
        case Key.k: return .bottomRight
        case Key.d: return .leftThird
        case Key.f: return .centerThird
        case Key.g: return .rightThird
        case Key.e: return .leftTwoThirds
        case Key.t: return .rightTwoThirds
        case Key.ret: return .maximize
        case Key.c: return .center
        case 51: return .restore      // Delete/Backspace
        default: return nil
        }
    }
}

struct SavedWindow: Codable {
    let bundle: String
    let title: String
    let index: Int
    let x: Double, y: Double, w: Double, h: Double
}

struct SavedLayout: Codable, Identifiable {
    var id: String { signature }
    let signature: String       // susunan monitor, mis. "3: 1512x982 · 2560x1440 · 1920x1080"
    let saved: Date
    let windows: [SavedWindow]
}

final class WindowManager: ObservableObject {
    static let shared = WindowManager()
    @Published var enabled: Bool { didSet { UserDefaults.standard.set(enabled, forKey: "wmEnabled"); apply(prompt: enabled) } }
    @Published var autoRestore: Bool { didSet { UserDefaults.standard.set(autoRestore, forKey: "wmAutoRestore") } }
    @Published var gap: Double { didSet { UserDefaults.standard.set(gap, forKey: "wmGap") } }
    @Published private(set) var layouts: [SavedLayout] = []
    @Published var message: String?

    private var previous: [String: CGRect] = [:]   // ukuran sebelum di-snap, per jendela
    private var installed = false

    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PY-Sys", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("window-layouts.json")
    }

    init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: "wmEnabled")
        autoRestore = d.object(forKey: "wmAutoRestore") as? Bool ?? true
        gap = d.object(forKey: "wmGap") as? Double ?? 0
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        if let data = try? Data(contentsOf: url), let l = try? dec.decode([SavedLayout].self, from: data) { layouts = l }
    }

    func apply(prompt: Bool) {
        guard enabled else { return }
        if !installed {
            installed = true
            HotkeyCenter.shared.handlers.append { code, flags in
                guard WindowManager.shared.enabled, let s = Snap.from(code: code, flags: flags) else { return false }
                DispatchQueue.main.async { WindowManager.shared.perform(s) }
                return true
            }
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
                let wm = WindowManager.shared
                guard wm.enabled, wm.autoRestore else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { wm.restoreLayout(silent: true) }
            }
        }
        HotkeyCenter.shared.ensure(prompt: prompt)
    }

    // MARK: Koordinat (AX: kiri-atas layar utama, AppKit: kiri-bawah)

    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private static func axRect(_ r: NSRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    private static func screen(for frame: CGRect) -> NSScreen? {
        let c = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { axRect($0.frame).contains(c) } ?? NSScreen.main
    }

    // MARK: AX helpers

    private static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        var w: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXFocusedWindowAttribute as CFString, &w) == .success, let w,
              CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        return (w as! AXUIElement)
    }

    static func frame(of w: AXUIElement) -> CGRect? {
        var pv: CFTypeRef?, sv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &pv) == .success,
              AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sv) == .success,
              let pv, let sv else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &p)
        AXValueGetValue(sv as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    static func setFrame(_ w: AXUIElement, _ r: CGRect) {
        var p = r.origin, s = r.size
        // Ukuran → posisi → ukuran lagi: menghindari jendela "terpotong" saat pindah ke monitor yang lebih kecil
        if let sv = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv) }
        if let pv = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, pv) }
        if let sv = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, sv) }
    }

    private static func key(_ w: AXUIElement) -> String {
        var t: CFTypeRef?
        AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        return "\(pid)|\((t as? String) ?? "")"
    }

    // MARK: Snap

    func perform(_ s: Snap) {
        guard AXIsProcessTrusted() else {
            message = tr("Izinkan PY-Sys di Accessibility untuk mengatur jendela.", "Allow PY-Sys in Accessibility to arrange windows.")
            return
        }
        guard let w = Self.focusedWindow(), let cur = Self.frame(of: w), let scr = Self.screen(for: cur) else { return }
        let k = Self.key(w)

        if s == .restore {
            if let r = previous[k] { Self.setFrame(w, r); previous[k] = nil }
            return
        }
        if previous[k] == nil { previous[k] = cur }

        if s == .nextDisplay || s == .prevDisplay {
            let screens = NSScreen.screens
            guard screens.count > 1, let i = screens.firstIndex(of: scr) else { return }
            let j = (i + (s == .nextDisplay ? 1 : screens.count - 1)) % screens.count
            let from = Self.axRect(scr.visibleFrame), to = Self.axRect(screens[j].visibleFrame)
            // Pertahankan posisi relatif dan proporsi ukuran
            let rx = (cur.minX - from.minX) / from.width, ry = (cur.minY - from.minY) / from.height
            let rw = min(cur.width / from.width, 1), rh = min(cur.height / from.height, 1)
            Self.setFrame(w, CGRect(x: to.minX + rx * to.width, y: to.minY + ry * to.height,
                                    width: rw * to.width, height: rh * to.height))
            return
        }

        let v = Self.axRect(scr.visibleFrame)
        let g = CGFloat(gap)
        let a = v.insetBy(dx: g, dy: g)
        let hw = (a.width - g) / 2, hh = (a.height - g) / 2
        let tw = (a.width - 2 * g) / 3
        let r: CGRect
        switch s {
        case .left: r = CGRect(x: a.minX, y: a.minY, width: hw, height: a.height)
        case .right: r = CGRect(x: a.minX + hw + g, y: a.minY, width: hw, height: a.height)
        case .top: r = CGRect(x: a.minX, y: a.minY, width: a.width, height: hh)
        case .bottom: r = CGRect(x: a.minX, y: a.minY + hh + g, width: a.width, height: hh)
        case .topLeft: r = CGRect(x: a.minX, y: a.minY, width: hw, height: hh)
        case .topRight: r = CGRect(x: a.minX + hw + g, y: a.minY, width: hw, height: hh)
        case .bottomLeft: r = CGRect(x: a.minX, y: a.minY + hh + g, width: hw, height: hh)
        case .bottomRight: r = CGRect(x: a.minX + hw + g, y: a.minY + hh + g, width: hw, height: hh)
        case .leftThird: r = CGRect(x: a.minX, y: a.minY, width: tw, height: a.height)
        case .centerThird: r = CGRect(x: a.minX + tw + g, y: a.minY, width: tw, height: a.height)
        case .rightThird: r = CGRect(x: a.minX + 2 * (tw + g), y: a.minY, width: tw, height: a.height)
        case .leftTwoThirds: r = CGRect(x: a.minX, y: a.minY, width: 2 * tw + g, height: a.height)
        case .rightTwoThirds: r = CGRect(x: a.minX + tw + g, y: a.minY, width: 2 * tw + g, height: a.height)
        case .maximize: r = a
        case .center:
            let wdt = min(cur.width, a.width), hgt = min(cur.height, a.height)
            r = CGRect(x: a.midX - wdt / 2, y: a.midY - hgt / 2, width: wdt, height: hgt)
        default: return
        }
        Self.setFrame(w, r.integral)
    }

    // MARK: Simpan & pulihkan tata letak per susunan monitor

    static var signature: String {
        let s = NSScreen.screens.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" }
        return "\(s.count): " + s.joined(separator: " · ")
    }

    private static func appWindows() -> [(bundle: String, windows: [AXUIElement])] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && !$0.isHidden }
            .compactMap { app in
                let el = AXUIElementCreateApplication(app.processIdentifier)
                var v: CFTypeRef?
                guard AXUIElementCopyAttributeValue(el, kAXWindowsAttribute as CFString, &v) == .success,
                      let arr = v as? [AXUIElement], !arr.isEmpty else { return nil }
                return (bundle: app.bundleIdentifier!, windows: arr)
            }
    }

    private static func title(_ w: AXUIElement) -> String {
        var t: CFTypeRef?
        AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
        return (t as? String) ?? ""
    }

    func saveLayout() {
        guard AXIsProcessTrusted() else { message = tr("Butuh izin Accessibility.", "Needs Accessibility permission."); return }
        var list: [SavedWindow] = []
        for (b, wins) in Self.appWindows() {
            for (i, w) in wins.enumerated() {
                guard let f = Self.frame(of: w), f.width > 50, f.height > 50 else { continue }
                list.append(SavedWindow(bundle: b, title: Self.title(w), index: i,
                                        x: f.minX, y: f.minY, w: f.width, h: f.height))
            }
        }
        let sig = Self.signature
        layouts.removeAll { $0.signature == sig }
        layouts.insert(SavedLayout(signature: sig, saved: Date(), windows: list), at: 0)
        persist()
        message = tr("\(list.count) jendela disimpan untuk susunan monitor ini.", "\(list.count) windows saved for this display setup.")
    }

    func restoreLayout(silent: Bool = false) {
        guard AXIsProcessTrusted(), let l = layouts.first(where: { $0.signature == Self.signature }) else {
            if !silent { message = tr("Belum ada tata letak tersimpan untuk susunan monitor ini.", "No saved layout for this display setup yet.") }
            return
        }
        var moved = 0
        for (b, wins) in Self.appWindows() {
            let saved = l.windows.filter { $0.bundle == b }
            guard !saved.isEmpty else { continue }
            var used: Set<Int> = []
            for (i, w) in wins.enumerated() {
                let t = Self.title(w)
                let match = saved.enumerated().first { !used.contains($0.offset) && $0.element.title == t && !t.isEmpty }
                    ?? saved.enumerated().first { !used.contains($0.offset) && $0.element.index == i }
                guard let m = match else { continue }
                used.insert(m.offset)
                Self.setFrame(w, CGRect(x: m.element.x, y: m.element.y, width: m.element.w, height: m.element.h))
                moved += 1
            }
        }
        if !silent || moved > 0 {
            message = tr("\(moved) jendela dikembalikan ke posisinya.", "\(moved) windows moved back into place.")
        }
    }

    func deleteLayout(_ l: SavedLayout) {
        layouts.removeAll { $0.signature == l.signature }
        persist()
    }

    private func persist() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        if let d = try? enc.encode(layouts) { try? d.write(to: url, options: .atomic) }
    }
}

struct WindowTab: View {
    @ObservedObject private var wm = WindowManager.shared
    @ObservedObject private var hc = HotkeyCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(tr("Aktifkan pengatur jendela", "Enable window manager"), isOn: $wm.enabled).toggleStyle(.switch)
            HStack(spacing: 6) {
                Circle().fill(wm.enabled && hc.running ? Color.green : Color.secondary).frame(width: 8, height: 8)
                Text(wm.enabled && hc.running ? tr("Shortcut aktif", "Shortcuts active") : tr("Tidak aktif", "Off"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            GroupBox(tr("Atur jendela yang sedang aktif", "Arrange the active window")) {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 4) {
                    ForEach(Snap.allCases) { s in
                        Button {
                            // Kembalikan fokus ke app sebelumnya, lalu atur jendelanya
                            NSApp.hide(nil)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { wm.perform(s) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: s.symbol).frame(width: 16)
                                Text(s.title).lineLimit(1)
                                Spacer()
                                Text(s.shortcut).foregroundStyle(.secondary).font(.caption2.monospaced())
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .font(.caption)
            }

            HStack {
                Text(tr("Jarak antar jendela", "Gap between windows")).font(.caption)
                Slider(value: $wm.gap, in: 0...20, step: 2)
                Text("\(Int(wm.gap)) px").font(.caption.monospacedDigit()).frame(width: 40)
            }

            GroupBox(tr("Tata letak dua monitor", "Dual-monitor layouts")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Simpan posisi semua jendela untuk susunan monitor sekarang. Saat monitor dicabut lalu dipasang lagi, jendela dikembalikan ke tempatnya.",
                            "Save every window's position for the current display setup. When monitors are unplugged and reconnected, windows go back into place."))
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(tr("Susunan sekarang: ", "Current setup: ") + WindowManager.signature).font(.caption2.monospaced())
                    HStack {
                        Button(tr("Simpan tata letak", "Save layout")) { wm.saveLayout() }
                        Button(tr("Pulihkan", "Restore")) { wm.restoreLayout() }
                    }
                    .controlSize(.small)
                    Toggle(tr("Pulihkan otomatis saat monitor berubah", "Restore automatically when displays change"), isOn: $wm.autoRestore)
                        .font(.caption)
                    ForEach(wm.layouts) { l in
                        HStack {
                            Text("\(l.signature) · \(l.windows.count) " + tr("jendela", "windows")).font(.caption2)
                            Spacer()
                            Button { wm.deleteLayout(l) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                    }
                }
            }

            if wm.enabled && !hc.running {
                VStack(alignment: .leading, spacing: 6) {
                    if let m = hc.message {
                        Text(m).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button(tr("Buka Accessibility", "Open Accessibility")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                        Button(tr("Coba lagi", "Try again")) { hc.ensure(prompt: true) }
                    }
                    .controlSize(.small)
                }
            }
            if let m = wm.message {
                Text(m).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(tr("Butuh izin Accessibility (sama dengan Klik Kanan+). Shortcut ⌃⌥ memakai Control + Option.",
                    "Needs Accessibility permission (same as Right-Click+). ⌃⌥ shortcuts use Control + Option."))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
