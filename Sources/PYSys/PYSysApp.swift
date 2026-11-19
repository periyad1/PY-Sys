import SwiftUI
import AppKit

@main
struct PYSysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let core = AetherCore.shared

    var body: some Scene {
        MenuBarExtra {
            RootView(core: core, freezer: core.freezer, settings: core.settings)
        } label: {
            MenuBarLabel(core: core)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        OnboardingWindow.showIfFirstRun()      // cek dulu sebelum fitur lain menyimpan pengaturan
        NSApp.setActivationPolicy(.accessory)   // tanpa ikon Dock
        Notifier.requestAuthorization()
        AgentMonitor.shared.recoverAfterCrash()
        _ = AetherCore.shared
        ScrollReverser.shared.apply(prompt: false)
        ClickMenu.shared.apply(prompt: false)
        HistoryStore.shared.start()
        WindowManager.shared.apply(prompt: false)
        ClipboardHistory.shared.start()
        DisplayControl.shared.start()
        TaskScheduler.shared.start()
        Updater.shared.startAuto()
        Theme.applyAppearance(AetherCore.shared.settings.themeMode)
        CrashReports.shared.checkOnLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AetherCore.shared.freezer.thawAll()      // jangan pernah tinggalkan app dalam keadaan beku
        AgentMonitor.shared.resumeAll()
        HistoryStore.shared.save()
    }
}

struct MenuBarLabel: View {
    @ObservedObject var core: AetherCore
    @ObservedObject private var settings = AetherCore.shared.settings
    @ObservedObject private var agents = AgentMonitor.shared
    @ObservedObject private var updater = Updater.shared

    private var text: String {
        var parts: [String] = []
        for raw in settings.barItems {
            guard let b = BarItem(rawValue: raw) else { continue }
            switch b {
            case .ram: parts.append("\(Int((core.mem.usedFraction * 100).rounded()))%")
            case .cpu: parts.append("CPU \(Int(((1 - core.cpu.idle) * 100).rounded()))%")
            case .temp: if let t = core.cpu.cpuTemp { parts.append("\(Int(t.rounded()))°") }
            case .net: parts.append("↓\(BarFmt.rate(core.netDown)) ↑\(BarFmt.rate(core.netUp))")
            case .swap: parts.append("Swap \(BarFmt.gb(core.mem.swapUsed))")
            case .agents: parts.append("AI \(agents.agents.count)")
            }
        }
        return parts.joined(separator: "  ")
    }

    var body: some View {
        HStack(spacing: 3) {
            if core.mem.pressure == .normal { Image(nsImage: Brand.menuGlyph) } else { Image(systemName: core.mem.pressure.symbol) }
            let t = text
            if !t.isEmpty { Text(t).monospacedDigit() }
            if updater.available { Image(systemName: "arrow.down.circle.fill") }
        }
    }
}
