import AppKit
import SwiftUI

// MARK: - Tombol daya: Kunci, Tidur, Keluar akun, Restart, Matikan

enum PowerAction: String, CaseIterable, Identifiable {
    case lock, sleep, logout, restart, shutdown
    var id: String { rawValue }

    var title: String {
        switch self {
        case .lock: return tr("Kunci layar", "Lock Screen")
        case .sleep: return tr("Tidur", "Sleep")
        case .logout: return tr("Keluar akun…", "Log Out…")
        case .restart: return tr("Restart…", "Restart…")
        case .shutdown: return tr("Matikan…", "Shut Down…")
        }
    }

    var symbol: String {
        switch self {
        case .lock: return "lock"
        case .sleep: return "moon"
        case .logout: return "rectangle.portrait.and.arrow.right"
        case .restart: return "arrow.clockwise"
        case .shutdown: return "power"
        }
    }

    var needsConfirm: Bool { self == .logout || self == .restart || self == .shutdown }
}

enum Power {
    private static var reopenWindows: Bool {
        get { UserDefaults.standard.object(forKey: "powerReopen") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "powerReopen") }
    }

    static func perform(_ a: PowerAction) {
        switch a {
        case .lock:
            SystemToggles.shared.perform(.lockScreen)
        case .sleep:
            run("/usr/bin/pmset", ["sleepnow"])
        case .logout, .restart, .shutdown:
            guard confirm(a) else { return }
            prepare()
            let verb = a == .logout ? "log out" : (a == .restart ? "restart" : "shut down")
            let save = a == .logout ? "" : " state saving preference \(reopenWindows ? "true" : "false")"
            var err: NSDictionary?
            _ = NSAppleScript(source: "tell application \"System Events\" to \(verb)\(save)")?.executeAndReturnError(&err)
            if err != nil {
                // Versi macOS lama tanpa parameter state saving: coba perintah polos
                err = nil
                _ = NSAppleScript(source: "tell application \"System Events\" to \(verb)")?.executeAndReturnError(&err)
            }
            if err != nil {
                let al = NSAlert()
                al.messageText = tr("Tidak bisa menjalankan perintah", "Couldn't run the command")
                al.informativeText = tr("Izinkan PY-Sys mengontrol System Events di System Settings → Privacy & Security → Automation.",
                                        "Allow PY-Sys to control System Events in System Settings → Privacy & Security → Automation.")
                al.runModal()
            }
        }
    }

    /// Sebelum Mac dimatikan: cairkan app beku, lanjutkan agen yang dijeda, simpan riwayat.
    private static func prepare() {
        AetherCore.shared.freezer.thawAll()
        AgentMonitor.shared.resumeAll()
        HistoryStore.shared.save()
    }

    private static func confirm(_ a: PowerAction) -> Bool {
        let al = NSAlert()
        al.icon = NSApp.applicationIconImage
        switch a {
        case .logout:
            al.messageText = tr("Keluar dari akun sekarang?", "Log out now?")
            al.addButton(withTitle: tr("Keluar akun", "Log Out"))
        case .restart:
            al.messageText = tr("Restart Mac sekarang?", "Restart your Mac now?")
            al.addButton(withTitle: "Restart")
        default:
            al.messageText = tr("Matikan Mac sekarang?", "Shut down your Mac now?")
            al.addButton(withTitle: tr("Matikan", "Shut Down"))
            al.buttons.first?.hasDestructiveAction = true
        }
        al.addButton(withTitle: tr("Batal", "Cancel"))
        al.informativeText = tr("App yang dibekukan dicairkan dulu, lalu macOS meminta Anda menyimpan dokumen yang belum disimpan.",
                                "Frozen apps are thawed first, then macOS asks you to save any unsaved documents.")
        if a != .logout {
            al.showsSuppressionButton = true
            al.suppressionButton?.title = tr("Buka lagi jendela saat login kembali", "Reopen windows when logging back in")
            al.suppressionButton?.state = reopenWindows ? .on : .off
        }
        NSApp.activate(ignoringOtherApps: true)
        let ok = al.runModal() == .alertFirstButtonReturn
        if a != .logout, let b = al.suppressionButton { reopenWindows = b.state == .on }
        return ok
    }

    private static func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
    }
}

/// Tombol ⏻ di bagian bawah panel, di samping Keluar.
struct PowerMenu: View {
    var body: some View {
        Menu {
            ForEach(PowerAction.allCases) { a in
                if a == .logout { Divider() }
                Button(role: a == .shutdown ? .destructive : nil) {
                    // Tunggu menu tertutup dulu supaya dialog konfirmasi muncul di depan
                    DispatchQueue.main.async { Power.perform(a) }
                } label: {
                    Label(a.title, systemImage: a.symbol)
                }
            }
        } label: {
            Image(systemName: "power")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .noFocusRing()
        .help(tr("Kunci, tidur, restart, matikan", "Lock, sleep, restart, shut down"))
    }
}
