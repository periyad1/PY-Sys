import SwiftUI
import AppKit
import UserNotifications
import ApplicationServices

// MARK: - Panduan awal (onboarding) — muncul sekali untuk pengguna baru

enum PermState { case ok, no, optional }

final class OnboardingModel: ObservableObject {
    static let shared = OnboardingModel()

    @Published var step = 0
    @Published var accessibility = false
    @Published var automation: PermState = .no
    @Published var notifications = false
    @Published var loginItem = false
    @Published var smartctl = false
    @Published var copied = false

    private var timer: Timer?

    func startPolling() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        accessibility = AXIsProcessTrusted()
        loginItem = LoginItem.enabled
        smartctl = ["/opt/homebrew/bin/smartctl", "/usr/local/bin/smartctl"].contains { FileManager.default.isExecutableFile(atPath: $0) }
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().getNotificationSettings { s in
                let on = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
                DispatchQueue.main.async { self.notifications = on }
            }
        }
        DispatchQueue.global(qos: .utility).async {
            let st = Self.automationStatus(ask: false)
            DispatchQueue.main.async { self.automation = st }
        }
    }

    /// Status izin Automation ke System Events (dipakai untuk restart/matikan, Finder, tab browser).
    static func automationStatus(ask: Bool) -> PermState {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        guard let desc = target.aeDesc else { return .no }
        let err = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
        return err == 0 ? .ok : .no
    }

    // MARK: Tindakan

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            Self.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }

    func requestAutomation() {
        DispatchQueue.global(qos: .userInitiated).async {
            // Menjalankan System Events lalu meminta izin (dialog macOS muncul sekali).
            var err: NSDictionary?
            NSAppleScript(source: "tell application \"System Events\" to return name of first process")?.executeAndReturnError(&err)
            let st = Self.automationStatus(ask: true)
            DispatchQueue.main.async {
                self.automation = st
                if st != .ok {
                    Self.openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
                }
            }
        }
    }

    func requestNotifications() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().getNotificationSettings { s in
            if s.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                    DispatchQueue.main.async { self.refresh() }
                }
            } else {
                DispatchQueue.main.async {
                    Self.openSettings("x-apple.systempreferences:com.apple.preference.notifications?id=\(Bundle.main.bundleIdentifier ?? "id.pysys.app")")
                }
            }
        }
    }

    func enableLogin() {
        try? LoginItem.set(true)
        refresh()
    }

    func copyBrew() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("brew install smartmontools", forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.copied = false }
    }

    static func openSettings(_ s: String) {
        if let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }
}

enum OnboardingWindow {
    static let doneKey = "onboardingDone"
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?

    /// Dipanggil paling awal saat app dibuka, sebelum fitur lain menyimpan pengaturan.
    /// Pengguna lama (sudah punya pengaturan tersimpan) tidak diganggu.
    static func showIfFirstRun() {
        let d = UserDefaults.standard
        if d.bool(forKey: doneKey) { return }
        if let id = Bundle.main.bundleIdentifier,
           let saved = d.persistentDomain(forName: id), !saved.isEmpty {
            d.set(true, forKey: doneKey)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { show() }
    }

    static func show() {
        let model = OnboardingModel.shared
        model.step = 0
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 500),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                UserDefaults.standard.set(true, forKey: doneKey)
                OnboardingModel.shared.stopPolling()
            }
        }
        window?.title = tr("Selamat datang di PY-Sys", "Welcome to PY-Sys")
        window?.contentViewController = NSHostingController(rootView: OnboardingView(model: model, settings: AetherCore.shared.settings))
        model.startPolling()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    static func finish() {
        UserDefaults.standard.set(true, forKey: doneKey)
        window?.close()
    }
}

// MARK: - Tampilan

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var settings: Settings

    private var stepNames: [String] {
        [tr("Sambutan", "Welcome"), tr("Izin", "Permissions"), tr("Tampilan", "Appearance"), tr("Selesai", "Done")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepBar
            Group {
                switch model.step {
                case 0: welcome
                case 1: permissions
                case 2: appearance
                default: finished
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: 580, height: 500)
    }

    // Indikator langkah
    private var stepBar: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                let on = i == model.step, done = i < model.step
                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(on ? Theme.brand : (done ? Color.green : Color.secondary.opacity(0.2)))
                        Text(done ? "✓" : "\(i + 1)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(on || done ? Color.white : Color.secondary)
                    }
                    .frame(width: 20, height: 20)
                    Text(stepNames[i])
                        .font(.system(size: 12, weight: on ? .bold : .medium))
                        .foregroundStyle(on || done ? Color.primary : Color.secondary)
                }
                if i < 3 { Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.step < 3 {
                Button(tr("Lewati panduan", "Skip guide")) { OnboardingWindow.finish() }
                    .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.step > 0 {
                Button(tr("Kembali", "Back")) { model.step -= 1 }
            }
            Button(primaryTitle) {
                if model.step < 3 { model.step += 1 } else { OnboardingWindow.finish() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .noFocusRing()
    }

    private var primaryTitle: String {
        switch model.step {
        case 0: return tr("Mulai", "Start")
        case 3: return tr("Buka PY-Sys", "Open PY-Sys")
        default: return tr("Lanjut", "Next")
        }
    }

    // 1 · Sambutan
    private var welcome: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
            (Text(tr("Selamat datang di ", "Welcome to ")) + Text("PY-Sys").foregroundColor(Theme.brand))
                .font(.system(size: 22, weight: .heavy))
            Text(tr("Pantau, bersihkan, dan rawat Mac Anda dari menu bar. Panduan singkat ini menyiapkan izin dan tampilan dalam ±1 menit.",
                    "Monitor, clean and care for your Mac from the menu bar. This short guide sets up permissions and appearance in about a minute."))
                .font(.system(size: 13.5)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            HStack(spacing: 10) {
                langButton("Bahasa Indonesia", "id")
                langButton("English", "en")
            }
            .padding(.top, 4)
            HStack(spacing: 16) {
                Text(tr("✓ Tanpa hak admin", "✓ No admin rights"))
                Text(tr("✓ Tanpa mengubah sistem", "✓ No system changes"))
                Text(tr("✓ Tanpa telemetri", "✓ No telemetry"))
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func langButton(_ title: String, _ code: String) -> some View {
        let on = settings.language == code
        return Button { settings.language = code } label: {
            Text(title)
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(on ? Color.accentColor.opacity(0.12) : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(on ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    // 2 · Izin
    private var permissions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Izin yang dibutuhkan", "Permissions needed")).font(.system(size: 16, weight: .heavy))
            Text(tr("Status diperbarui otomatis setelah Anda mengizinkannya di System Settings.",
                    "Status updates automatically after you allow it in System Settings."))
                .font(.caption).foregroundStyle(.secondary)
            permRow("hand.raised.fill", "Accessibility",
                    tr("Jendela, Clipboard ⌃⌥V, Klik Kanan+, Scroll Reverser", "Windows, Clipboard ⌃⌥V, Right Click+, Scroll Reverser"),
                    model.accessibility ? .ok : .no, tr("Buka pengaturan", "Open settings"), model.requestAccessibility)
            permRow("gearshape.2.fill", "Automation",
                    tr("Tab browser, Finder, restart & matikan", "Browser tabs, Finder, restart & shut down"),
                    model.automation, tr("Minta sekarang", "Ask now"), model.requestAutomation)
            permRow("bell.fill", tr("Notifikasi", "Notifications"),
                    tr("Peringatan RAM, agen AI macet, versi baru", "RAM alerts, stuck AI agents, new versions"),
                    model.notifications ? .ok : .no, tr("Izinkan", "Allow"), model.requestNotifications)
            permRow("power", tr("Jalankan saat login", "Launch at login"),
                    tr("PY-Sys otomatis aktif setiap Mac menyala", "PY-Sys starts automatically with your Mac"),
                    model.loginItem ? .ok : .no, tr("Nyalakan", "Turn on"), model.enableLogin)
            permRow("internaldrive.fill", tr("Kesehatan SSD (smartctl)", "SSD health (smartctl)"),
                    tr("Butuh Homebrew: brew install smartmontools", "Needs Homebrew: brew install smartmontools"),
                    model.smartctl ? .ok : .optional,
                    model.copied ? tr("Tersalin ✓", "Copied ✓") : tr("Salin perintah", "Copy command"), model.copyBrew)
        }
    }

    private func permRow(_ icon: String, _ title: String, _ why: String, _ state: PermState,
                         _ button: String, _ action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium)).foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: TabCategory.utility.color)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .bold))
                Text(why).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            badge(state)
            if state == .ok {
                Color.clear.frame(width: 104, height: 1)
            } else {
                Button(button, action: action).controlSize(.small).frame(width: 104, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).stroke(Color.secondary.opacity(0.25)))
    }

    private func badge(_ s: PermState) -> some View {
        let (bg, fg, sym, txt): (Color, Color, String, String) = {
            switch s {
            case .ok: return (Color.green.opacity(0.18), Color.green, "checkmark", tr("Diizinkan", "Allowed"))
            case .no: return (Color.red.opacity(0.15), Color.red, "xmark", tr("Belum", "Not yet"))
            case .optional: return (Color.secondary.opacity(0.15), Color.secondary, "circle.dashed", tr("Opsional", "Optional"))
            }
        }()
        return HStack(spacing: 4) {
            Image(systemName: sym).font(.system(size: 9, weight: .bold))
            Text(txt).font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(bg))
    }

    // 3 · Tampilan
    private var favoriteChoices: [AppTab] {
        AppTab.allCases.filter { $0 != .settings && $0 != .dashboard }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Atur tampilan", "Set up appearance")).font(.system(size: 16, weight: .heavy))
            sectionLabel(tr("GAYA IKON", "ICON STYLE"))
            IconStylePicker(settings: settings)
            sectionLabel(tr("WARNA AKSEN", "ACCENT COLOR"))
            AccentPicker(settings: settings)
            sectionLabel(tr("FAVORIT DI BERANDA (\(settings.favorites.count)/10)", "HOME FAVORITES (\(settings.favorites.count)/10)"))
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(favoriteChoices, id: \.self) { t in
                        let on = settings.favorites.contains(t.rawValue)
                        Button { settings.toggleFavorite(t) } label: {
                            HStack(spacing: 5) {
                                FeatureIcon(tab: t, size: 18)
                                Text(t.short).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                                Spacer(minLength: 0)
                                Image(systemName: on ? "star.fill" : "star")
                                    .font(.system(size: 9)).foregroundStyle(on ? Color.yellow : Color.secondary)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.accentColor.opacity(0.12) : Color.clear))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.25)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
        .noFocusRing()
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
    }

    // 4 · Selesai
    private var finished: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("PY-Sys siap dipakai", "PY-Sys is ready")).font(.system(size: 18, weight: .heavy))
                    Text(tr("Klik ikon chip di menu bar kapan saja untuk membuka Beranda.",
                            "Click the chip icon in the menu bar any time to open Home."))
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            }
            sectionLabel(tr("TIPS CEPAT", "QUICK TIPS"))
            tip("⌃⌥V", tr("Riwayat clipboard di posisi kursor", "Clipboard history at the cursor"))
            tip("⌃⌥ ← →", tr("Jendela ke separuh kiri / kanan layar", "Snap window to left / right half"))
            tip("⌥ klik kanan", tr("Menu Klik Kanan+ di Finder", "Right Click+ menu in Finder"))
            tip(tr("Bebaskan RAM", "Free RAM"), tr("Bekukan app idle dengan satu klik di Beranda", "Freeze idle apps with one click on Home"))
            Text(tr("Panduan ini bisa dibuka lagi di Pengaturan → Tampilkan panduan awal.",
                    "You can reopen this guide in Settings → Show welcome guide."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func tip(_ key: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(key)
                .font(.system(size: 12, weight: .bold))
                .frame(minWidth: 84)
                .padding(.vertical, 4).padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
            Text(text).font(.system(size: 13))
        }
    }
}
