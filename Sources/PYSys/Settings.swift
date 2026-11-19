import Foundation
import ServiceManagement

final class Settings: ObservableObject {
    private enum K {
        static let cryo = "cryoEnabled", idle = "idleMinutes", cpu = "cpuGuard"
        static let bloat = "bloatGB", wl = "whitelist", lang = "language"
        static let hidden = "hiddenTabs", pubIP = "showPublicIP", hiddenToggles = "hiddenToggles"
        static let sEn = "scrollEnabled", sTp = "scrollTrackpadNatural", sMo = "scrollMouseNatural"
        static let sStepOn = "scrollStepEnabled", sStep = "scrollStep", sHor = "scrollHorizontal"
        static let thMode = "themeMode", thAcc = "accentCustom", thHue = "accentHue", bgKind = "bgKind", bgHue = "bgHue"
        static let restart = "restartReminder", agCPU = "agentCPU", agMin = "agentMinutes", bar = "barItems"
        static let bgBright = "bgBrightness", bgOpa = "bgOpacity", bgBlur = "bgBlur", bgImg = "bgImageName"
    }

    /// Aplikasi yang TIDAK PERNAH dibekukan otomatis: terminal/IDE (tempat agen AI jalan),
    /// server model lokal, komunikasi, audio/video call, dan DisplayLink.
    static let defaultWhitelist = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode",
        "com.docker.docker", "com.electron.ollama", "ai.elementlabs.lmstudio",
        "com.anthropic.claudefordesktop", "com.openai.chat",
        "com.tinyspeck.slackmacgap", "net.whatsapp.WhatsApp", "ru.keepcoder.Telegram", "com.hnc.Discord",
        "us.zoom.xos", "com.microsoft.teams2", "com.apple.FaceTime",
        "com.apple.Music", "com.spotify.client",
        "com.apple.ActivityMonitor", "com.apple.systempreferences",
        "com.displaylink.DisplayLinkUserAgent",
    ]

    @Published var cryoEnabled: Bool { didSet { UserDefaults.standard.set(cryoEnabled, forKey: K.cryo) } }
    @Published var idleMinutes: Int { didSet { UserDefaults.standard.set(idleMinutes, forKey: K.idle) } }
    @Published var cpuGuard: Double { didSet { UserDefaults.standard.set(cpuGuard, forKey: K.cpu) } }
    @Published var bloatGB: Double { didSet { UserDefaults.standard.set(bloatGB, forKey: K.bloat) } }
    @Published var whitelist: [String] { didSet { UserDefaults.standard.set(whitelist, forKey: K.wl) } }
    @Published var language: String { didSet { UserDefaults.standard.set(language, forKey: K.lang) } }
    @Published var hiddenTabs: [String] { didSet { UserDefaults.standard.set(hiddenTabs, forKey: K.hidden) } }
    @Published var hiddenToggles: [String] { didSet { UserDefaults.standard.set(hiddenToggles, forKey: K.hiddenToggles) } }
    @Published var scrollEnabled: Bool { didSet { UserDefaults.standard.set(scrollEnabled, forKey: K.sEn) } }
    @Published var scrollTrackpadNatural: Bool { didSet { UserDefaults.standard.set(scrollTrackpadNatural, forKey: K.sTp) } }
    @Published var scrollMouseNatural: Bool { didSet { UserDefaults.standard.set(scrollMouseNatural, forKey: K.sMo) } }
    @Published var scrollStepEnabled: Bool { didSet { UserDefaults.standard.set(scrollStepEnabled, forKey: K.sStepOn) } }
    @Published var scrollStep: Int { didSet { UserDefaults.standard.set(scrollStep, forKey: K.sStep) } }
    @Published var scrollHorizontal: Bool { didSet { UserDefaults.standard.set(scrollHorizontal, forKey: K.sHor) } }
    @Published var themeMode: String { didSet { UserDefaults.standard.set(themeMode, forKey: K.thMode) } }
    @Published var accentCustom: Bool { didSet { UserDefaults.standard.set(accentCustom, forKey: K.thAcc) } }
    @Published var accentHue: Double { didSet { UserDefaults.standard.set(accentHue, forKey: K.thHue) } }
    @Published var bgKind: String { didSet { UserDefaults.standard.set(bgKind, forKey: K.bgKind) } }
    @Published var bgHue: Double { didSet { UserDefaults.standard.set(bgHue, forKey: K.bgHue) } }
    @Published var bgBrightness: Double { didSet { UserDefaults.standard.set(bgBrightness, forKey: K.bgBright) } }
    @Published var bgOpacity: Double { didSet { UserDefaults.standard.set(bgOpacity, forKey: K.bgOpa) } }
    @Published var bgBlur: Double { didSet { UserDefaults.standard.set(bgBlur, forKey: K.bgBlur) } }
    @Published var bgImageName: String { didSet { UserDefaults.standard.set(bgImageName, forKey: K.bgImg) } }
    @Published var restartReminder: Bool { didSet { UserDefaults.standard.set(restartReminder, forKey: K.restart) } }
    @Published var agentCPU: Double { didSet { UserDefaults.standard.set(agentCPU, forKey: K.agCPU) } }
    @Published var agentMinutes: Int { didSet { UserDefaults.standard.set(agentMinutes, forKey: K.agMin) } }
    @Published var barItems: [String] { didSet { UserDefaults.standard.set(barItems, forKey: K.bar) } }
    @Published var showPublicIP: Bool { didSet { UserDefaults.standard.set(showPublicIP, forKey: K.pubIP) } }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: [K.cryo: true, K.idle: 10, K.cpu: 1.0, K.bloat: 2.5,
                              K.wl: Settings.defaultWhitelist, K.lang: AppLanguage.id.rawValue, K.hidden: [String](), K.pubIP: true,
                              K.sEn: false, K.sTp: true, K.sMo: false, K.sStepOn: true, K.sStep: 3, K.sHor: true,
                              K.thMode: "system", K.thAcc: false, K.thHue: 210.0, K.bgKind: "none", K.bgHue: 210.0,
                              K.bgBright: 0.5, K.bgOpa: 0.35, K.bgBlur: 8.0, K.bgImg: "",
                              K.agCPU: 90.0, K.agMin: 5, K.bar: ["ram"], K.restart: true])
        cryoEnabled = d.bool(forKey: K.cryo)
        idleMinutes = max(2, d.integer(forKey: K.idle))
        cpuGuard = d.double(forKey: K.cpu)
        bloatGB = d.double(forKey: K.bloat)
        whitelist = d.stringArray(forKey: K.wl) ?? Settings.defaultWhitelist
        language = d.string(forKey: K.lang) ?? AppLanguage.id.rawValue
        hiddenTabs = d.stringArray(forKey: K.hidden) ?? []
        hiddenToggles = d.stringArray(forKey: K.hiddenToggles) ?? []
        scrollEnabled = d.bool(forKey: K.sEn)
        scrollTrackpadNatural = d.bool(forKey: K.sTp)
        scrollMouseNatural = d.bool(forKey: K.sMo)
        scrollStepEnabled = d.bool(forKey: K.sStepOn)
        scrollStep = min(10, max(1, d.integer(forKey: K.sStep)))
        scrollHorizontal = d.bool(forKey: K.sHor)
        themeMode = d.string(forKey: K.thMode) ?? "system"
        accentCustom = d.bool(forKey: K.thAcc)
        accentHue = d.double(forKey: K.thHue)
        bgKind = d.string(forKey: K.bgKind) ?? "none"
        bgHue = d.double(forKey: K.bgHue)
        bgBrightness = d.double(forKey: K.bgBright)
        bgOpacity = d.double(forKey: K.bgOpa)
        bgBlur = d.double(forKey: K.bgBlur)
        bgImageName = d.string(forKey: K.bgImg) ?? ""
        showPublicIP = d.bool(forKey: K.pubIP)
        agentCPU = d.double(forKey: K.agCPU)
        restartReminder = d.bool(forKey: K.restart)
        agentMinutes = max(1, d.integer(forKey: K.agMin))
        barItems = d.stringArray(forKey: K.bar) ?? ["ram"]
    }
}

enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

enum Fmt {
    static func bytes(_ b: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: b), countStyle: .memory)
    }
    static func disk(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
    static func ioRate(_ bps: Double) -> String {
        if bps < 1 { return "–" }
        if bps < 1_000_000 { return String(format: "%.0f KB/s", bps / 1_000) }
        return String(format: "%.1f MB/s", bps / 1_000_000)
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds)) / 60
        let d = total / 1440, h = (total % 1440) / 60, m = total % 60
        var parts: [String] = []
        if d > 0 { parts.append(tr("\(d) hari", "\(d)d")) }
        if h > 0 || d > 0 { parts.append(tr("\(h) jam", "\(h)h")) }
        parts.append(tr("\(m) menit", "\(m)m"))
        return parts.joined(separator: " ")
    }
    static func rate(_ bytesPerSec: Double) -> String {
        bytesPerSec < 50_000 ? "0 MB/s" : String(format: "%.1f MB/s", bytesPerSec / 1_000_000)
    }
}

// MARK: - Dua bahasa / Bilingual

enum AppLanguage: String {
    case id, en, system

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "id") ?? .id
    }

    static var isEnglish: Bool {
        switch current {
        case .en: return true
        case .id: return false
        case .system: return !(Locale.preferredLanguages.first ?? "id").hasPrefix("id")
        }
    }
}

/// tr("teks Indonesia", "English text") → dipilih sesuai bahasa di menu Atur.
func tr(_ id: String, _ en: String) -> String {
    AppLanguage.isEnglish ? en : id
}

// MARK: - Tab

enum AppTab: String, CaseIterable {
    case dashboard, overview, ram, cpu, network, sensors, agents, browser, history, apps, cryo, focus, tabsleep, storage, uninstall, files, toggles, clickmenu, windows, clipboard, displays, scheduler, scroll, tools, settings

    var category: TabCategory {
        switch self {
        case .dashboard, .overview, .ram, .cpu, .network, .sensors, .agents, .browser, .history: return .monitoring
        case .apps, .cryo, .focus, .tabsleep, .storage, .uninstall, .files: return .cleaner
        case .toggles, .clickmenu, .windows, .clipboard, .displays, .scheduler, .scroll, .tools, .settings: return .utility
        }
    }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .overview: return tr("Ringkasan", "Overview")
        case .ram: return "RAM"
        case .cpu: return "CPU"
        case .network: return tr("Jaringan", "Network")
        case .sensors: return tr("Sensor", "Sensors")
        case .agents: return tr("Agen AI", "AI Agents")
        case .browser: return "Browser"
        case .history: return tr("Riwayat", "History")
        case .focus: return tr("Mode fokus", "Focus mode")
        case .tabsleep: return tr("Tab browser", "Browser tabs")
        case .uninstall: return "Uninstaller"
        case .files: return tr("File besar & duplikat", "Large & duplicate files")
        case .apps: return tr("Aplikasi", "Apps")
        case .cryo: return "Cryo-Sleep"
        case .storage: return tr("Penyimpanan", "Storage")
        case .toggles: return tr("Toggle cepat", "Quick toggles")
        case .clickmenu: return tr("Klik Kanan+", "Right-Click+")
        case .windows: return tr("Jendela", "Windows")
        case .clipboard: return "Clipboard"
        case .displays: return tr("Monitor", "Displays")
        case .scheduler: return tr("Jadwal", "Schedule")
        case .scroll: return "Scroll Reverser"
        case .tools: return tr("Alat", "Tools")
        case .settings: return tr("Pengaturan", "Settings")
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "rectangle.grid.2x2"
        case .overview: return "speedometer"
        case .ram: return "memorychip"
        case .cpu: return "cpu"
        case .network: return "network"
        case .sensors: return "thermometer"
        case .agents: return "sparkles"
        case .browser: return "globe"
        case .history: return "clock.arrow.circlepath"
        case .focus: return "scope"
        case .tabsleep: return "moon.zzz"
        case .uninstall: return "trash.square"
        case .files: return "doc.on.doc"
        case .apps: return "square.grid.2x2"
        case .cryo: return "snowflake"
        case .storage: return "internaldrive"
        case .toggles: return "switch.2"
        case .clickmenu: return "cursorarrow.click.2"
        case .windows: return "macwindow.on.rectangle"
        case .clipboard: return "doc.on.clipboard"
        case .displays: return "sun.max"
        case .scheduler: return "calendar.badge.clock"
        case .scroll: return "arrow.up.arrow.down"
        case .tools: return "wrench.and.screwdriver"
        case .settings: return "gearshape"
        }
    }
}

enum TabCategory: String, CaseIterable {
    case monitoring, cleaner, utility

    var title: String {
        switch self {
        case .monitoring: return "Monitoring"
        case .cleaner: return "Cleaner"
        case .utility: return "Utility"
        }
    }
}

enum AppInfo {
    static let name = "PY-Sys"
    static let version = "1.5.3 (2026)"
    static let author = "Periyadi"
    static let email = "periyadi@telkomuniversity.ac.id"
}
