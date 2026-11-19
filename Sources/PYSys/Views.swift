import SwiftUI
import Charts
import AppKit

extension PressureLevel {
    var label: String {
        switch self {
        case .normal: return tr("Normal", "Normal")
        case .warning: return tr("Waspada", "Warning")
        case .critical: return tr("Kritis", "Critical")
        }
    }
    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
    var symbol: String {
        switch self {
        case .normal: return "memorychip"
        case .warning: return "exclamationmark.triangle"
        case .critical: return "flame"
        }
    }
}

struct RootView: View {
    @ObservedObject var core: AetherCore
    @ObservedObject var freezer: Freezer
    @ObservedObject var settings: Settings
    @ObservedObject private var ui = UIState.shared

    private var isHome: Bool { AppTab(rawValue: ui.tab) == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let current = AppTab(rawValue: ui.tab)
            HStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 20, height: 20)
                Text("PY-Sys").font(.system(.headline, design: .rounded).weight(.heavy)).foregroundStyle(Theme.brand)
                Text("· " + (current?.title ?? tr("Beranda", "Home"))).font(.system(.headline, design: .rounded)).foregroundStyle(.secondary)
                Spacer()
                QuickThemeMenu(settings: settings)
                PressureBadge(level: core.mem.pressure)
            }
            UpdateBanner()
            if ui.customColorOpen { CustomColorCard(settings: settings) }

            if let t = current {
                HStack {
                    Button {
                        ui.search = ""
                        ui.tab = UIState.home
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left")
                            Text(tr("Beranda", "Home"))
                        }
                        .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("[", modifiers: .command)
                    Spacer()
                    if t != .settings {
                        let fav = settings.favorites.contains(t.rawValue)
                        Button {
                            settings.toggleFavorite(t)
                        } label: {
                            Label(tr("Favorit", "Favorite"), systemImage: fav ? "star.fill" : "star")
                                .foregroundStyle(fav ? Color.orange : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                ScrollView {
                    Group {
                        switch t {
                        case .dashboard: DashboardTab(core: core)
                        case .overview: OverviewTab(core: core, freezer: freezer)
                        case .ram: MemoryTab(core: core)
                        case .cpu: CPUTab(core: core)
                        case .network: NetworkTab(core: core, settings: settings)
                        case .sensors: SensorsTab(core: core)
                        case .agents: AgentsTab(settings: settings)
                        case .browser: BrowserTab()
                        case .history: HistoryTab(core: core)
                        case .focus: FocusTab(core: core)
                        case .tabsleep: TabSleepTab()
                        case .uninstall: UninstallTab()
                        case .files: FileFinderTab()
                        case .apps: AppsTab(core: core, freezer: freezer)
                        case .cryo: CryoTab(freezer: freezer, settings: settings)
                        case .storage: StorageTab(core: core)
                        case .toggles: TogglesTab(settings: settings)
                        case .clickmenu: ClickMenuTab()
                        case .windows: WindowTab()
                        case .clipboard: ClipboardTab()
                        case .displays: DisplaysTab()
                        case .scheduler: SchedulerTab()
                        case .scroll: ScrollTab(settings: settings)
                        case .tools: ToolsTab(core: core)
                        case .settings: SettingsTab(settings: settings)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 4)
                }
                .frame(height: 470)
            } else {
                HomeView(core: core, settings: settings)
                    .frame(height: 500)
            }

            Divider()
            HStack {
                if !freezer.frozen.isEmpty {
                    Button(tr("Cairkan semua", "Thaw all") + " (\(freezer.frozen.count))") { freezer.thawAll() }
                }
                Spacer()
                ShortcutBar()
                Button(tr("Keluar", "Quit")) {
                    freezer.thawAll()
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 440)
        .background(ThemeBackground(settings: settings))
        .tint(Theme.accent)
        .id(settings.language + Theme.key(settings))   // gambar ulang semua teks saat bahasa diganti
        .background(PanelVisibilityWatcher())
        .onAppear { AetherCore.shared.setPanelOpen(true) }
        .onDisappear { AetherCore.shared.setPanelOpen(false) }
    }
}

struct PressureBadge: View {
    let level: PressureLevel
    var body: some View {
        Text(level.label)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(level.color.opacity(0.2), in: Capsule())
            .foregroundStyle(level.color)
    }
}

struct StatRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}

// MARK: - Ringkasan / Overview

struct MemoryBar: View {
    let mem: MemorySnapshot

    private var segments: [(name: String, bytes: UInt64, color: Color)] {
        [(tr("Aplikasi", "App"), mem.app, .blue), ("Wired", mem.wired, .orange),
         (tr("Terkompresi", "Compressed"), mem.compressed, .purple),
         (tr("Cache file", "File cache"), mem.cachedFiles, .gray)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(segments, id: \.name) { s in
                        Rectangle()
                            .fill(s.color)
                            .frame(width: max(0, geo.size.width * CGFloat(Double(s.bytes) / Double(max(mem.total, 1)))))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 14)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 3) {
                ForEach(segments, id: \.name) { s in
                    HStack(spacing: 4) {
                        Circle().fill(s.color).frame(width: 7, height: 7)
                        Text(s.name).foregroundStyle(.secondary)
                        Spacer()
                        Text(Fmt.bytes(s.bytes)).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
    }
}

struct Sparkline: View {
    let title: String
    let points: [(date: Date, value: Double)]
    let color: Color
    let yMax: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f", points.last?.value ?? 0)).font(.caption2).monospacedDigit()
            }
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { item in
                    AreaMark(x: .value("t", item.element.date), y: .value("v", item.element.value))
                        .foregroundStyle(color.opacity(0.2))
                    LineMark(x: .value("t", item.element.date), y: .value("v", item.element.value))
                        .foregroundStyle(color)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...(yMax ?? max(1, points.map { $0.value }.max() ?? 1)))
            .frame(height: 48)
        }
    }
}

struct OverviewTab: View {
    @ObservedObject var core: AetherCore
    @ObservedObject var freezer: Freezer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("\(Fmt.bytes(core.mem.used)) dari \(Fmt.bytes(core.mem.total)) terpakai",
                    "\(Fmt.bytes(core.mem.used)) of \(Fmt.bytes(core.mem.total)) used"))
                .font(.callout)
            MemoryBar(mem: core.mem)

            GroupBox(tr("Swap & kompresi", "Swap & compression")) {
                VStack(spacing: 4) {
                    StatRow(title: tr("Swap terpakai", "Swap used"),
                            value: "\(Fmt.bytes(core.mem.swapUsed)) / \(Fmt.bytes(core.mem.swapTotal))")
                    StatRow(title: tr("Laju swap-out", "Swap-out rate"), value: Fmt.rate(core.swapOutRate))
                    StatRow(title: tr("Rasio kompresi", "Compression ratio"),
                            value: core.mem.compressionRatio > 0 ? String(format: "%.1f×", core.mem.compressionRatio) : "–")
                    StatRow(title: tr("Dibekukan Cryo", "Frozen by Cryo"),
                            value: "\(freezer.frozen.count) app · \(Fmt.bytes(freezer.frozenBytes))")
                }
            }

            GroupBox(tr("10 menit terakhir", "Last 10 minutes")) {
                HStack(spacing: 12) {
                    Sparkline(title: tr("RAM terpakai %", "RAM used %"),
                              points: core.history.map { ($0.date, $0.usedPct) }, color: .blue, yMax: 100)
                    Sparkline(title: "Swap-out MB/s",
                              points: core.history.map { ($0.date, $0.swapOutMBps) }, color: .red, yMax: nil)
                }
            }

            GroupBox(tr("SSD internal", "Internal SSD")) {
                VStack(spacing: 6) {
                    if let v = core.volume {
                        HStack(spacing: 8) {
                            Image(systemName: "internaldrive").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(v.name)
                                Text(tr("\(Fmt.disk(v.free)) bebas", "\(Fmt.disk(v.free)) free"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                CompositionBar(segments: [(UInt64(max(0, v.total - v.free)), Color.cyan)],
                                               total: UInt64(max(1, v.total)))
                                    .frame(width: 130)
                                HStack(spacing: 6) {
                                    Text("R").font(.caption).foregroundStyle(.secondary)
                                    ActivityDot(active: core.diskReadRate > 50_000, color: .cyan)
                                    Text("W").font(.caption).foregroundStyle(.secondary)
                                    ActivityDot(active: core.diskWriteRate > 50_000, color: .red)
                                }
                            }
                        }
                        StatRow(title: tr("Terpakai", "Used"), value: Fmt.disk(v.total - v.free))
                        StatRow(title: tr("Bebas", "Free"), value: Fmt.disk(v.free))
                    }
                    StatRow(title: tr("Baca sekarang", "Read now"), value: Fmt.ioRate(core.diskReadRate))
                    StatRow(title: tr("Tulis sekarang", "Write now"), value: Fmt.ioRate(core.diskWriteRate))
                    StatRow(title: tr("Ditulis sejak boot", "Written since boot"), value: Fmt.bytes(core.diskWrittenSinceBoot))
                    if let h = core.ssd {
                        if let p = h.percentUsed {
                            StatRow(title: tr("Sisa umur SSD", "SSD lifetime left"), value: "\(max(0, 100 - p))%")
                        }
                        if let w = h.written { StatRow(title: tr("Total ditulis (seumur)", "Total written (lifetime)"), value: w) }
                        if let s = h.availableSpare { StatRow(title: "Available Spare", value: "\(s)%") }
                        if let hrs = h.powerOnHours { StatRow(title: tr("Jam menyala", "Power-on hours"), value: tr("\(hrs) jam", "\(hrs) h")) }
                    } else if let m = core.ssdMessage {
                        Text(m.text).font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Spacer()
                        Button(tr("Segarkan", "Refresh")) { core.refreshSSD() }.controlSize(.small)
                    }
                }
            }

            GroupBox(tr("Proses baca/tulis disk", "Disk read/write processes")) {
                VStack(spacing: 4) {
                    HStack {
                        Spacer()
                        Text("R").frame(width: 80, alignment: .trailing)
                        Text("W").frame(width: 80, alignment: .trailing)
                    }
                    .font(.caption.bold()).foregroundStyle(.secondary)
                    if core.diskProcs.isEmpty {
                        Text(tr("Tidak ada aktivitas disk saat ini.", "No disk activity right now."))
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(core.diskProcs) { p in
                        HStack {
                            Text(p.name).lineLimit(1)
                            Spacer()
                            Text(Fmt.ioRate(p.read)).monospacedDigit().frame(width: 80, alignment: .trailing)
                            Text(Fmt.ioRate(p.write)).monospacedDigit().frame(width: 80, alignment: .trailing)
                        }
                        .font(.callout)
                    }
                    Text(tr("Hanya proses milik akun Anda (proses sistem butuh hak admin).",
                            "Only your own processes (system processes need admin rights)."))
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onAppear { core.setOverviewVisible(true) }
        .onDisappear { core.setOverviewVisible(false) }
    }
}

struct ActivityDot: View {
    let active: Bool
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(active ? color : Color.secondary.opacity(0.2))
            .frame(width: 10, height: 10)
    }
}

// MARK: - Aplikasi / Apps

struct AppsTab: View {
    @ObservedObject var core: AetherCore
    @ObservedObject var freezer: Freezer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Pemakai memori terbesar · diperbarui tiap 15 detik",
                    "Top memory users · refreshed every 15 seconds"))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(core.groups.prefix(15))) { g in
                AppRow(group: g, isFrozen: freezer.isFrozen(g.mainPID), freezer: freezer)
                Divider()
            }
        }
    }
}

struct AppRow: View {
    let group: AppGroup
    let isFrozen: Bool
    let freezer: Freezer

    var body: some View {
        HStack(spacing: 8) {
            if let icon = group.icon {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: "terminal").frame(width: 18, height: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(group.name).lineLimit(1)
                    if isFrozen { Image(systemName: "snowflake").foregroundStyle(.cyan).font(.caption) }
                }
                Text(tr("\(group.pids.count) proses", "\(group.pids.count) processes")
                     + " · CPU \(String(format: "%.1f", group.cpu))%")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Fmt.bytes(group.footprint)).monospacedDigit().font(.callout)
            if group.isApp {
                if isFrozen {
                    Button { freezer.thaw(group.mainPID) } label: { Image(systemName: "sun.max") }
                        .help(tr("Cairkan", "Thaw"))
                } else {
                    Button { freezer.manualFreeze(group) } label: { Image(systemName: "snowflake") }
                        .help(tr("Bekukan (sembunyikan lalu SIGSTOP)", "Freeze (hide, then SIGSTOP)"))
                }
                Button {
                    if isFrozen { freezer.thaw(group.mainPID) }
                    NSRunningApplication(processIdentifier: group.mainPID)?.terminate()
                } label: { Image(systemName: "xmark.circle") }
                    .help(tr("Tutup aplikasi", "Quit app"))
            }
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Cryo-Sleep

struct CryoTab: View {
    @ObservedObject var freezer: Freezer
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(tr("Cryo-Sleep otomatis", "Automatic Cryo-Sleep"), isOn: $settings.cryoEnabled)
            Stepper(tr("Bekukan setelah idle \(settings.idleMinutes) menit",
                       "Freeze after \(settings.idleMinutes) min idle"),
                    value: $settings.idleMinutes, in: 2...120)
            Stepper(String(format: tr("Lewati jika CPU > %.1f%%", "Skip if CPU > %.1f%%"), settings.cpuGuard),
                    value: $settings.cpuGuard, in: 0.5...20, step: 0.5)
            Text(tr("Aplikasi hanya dibekukan jika: bukan app aktif, tidak punya jendela terlihat di monitor mana pun, sudah idle, hampir tidak memakai CPU, dan tidak ada di whitelist. Klik ikonnya di Dock atau Cmd-Tab untuk mencairkan otomatis.",
                    "An app is frozen only if it is not the active app, has no visible window on any display, has been idle, uses almost no CPU, and is not whitelisted. Click its Dock icon or Cmd-Tab to it to thaw it automatically."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            if freezer.frozen.isEmpty {
                Text(tr("Tidak ada aplikasi yang sedang dibekukan.", "No apps are frozen right now."))
                    .foregroundStyle(.secondary)
            }
            ForEach(freezer.frozen) { f in
                HStack {
                    Image(systemName: "snowflake").foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.name)
                        Text(tr("sejak", "since") + " \(f.since.formatted(date: .omitted, time: .shortened)) · \(Fmt.bytes(f.footprint))"
                             + (f.manual ? " · manual" : ""))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(tr("Cairkan", "Thaw")) { freezer.thaw(f.mainPID) }
                }
            }
        }
    }
}

// MARK: - Atur / Settings

struct RunningItem: Hashable {
    let id: String
    let name: String
}

struct SettingsTab: View {
    @ObservedObject var settings: Settings
    @ObservedObject private var ui = UIState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(tr("Bahasa", "Language"), selection: $settings.language) {
                Text("Bahasa Indonesia").tag(AppLanguage.id.rawValue)
                Text("English").tag(AppLanguage.en.rawValue)
                Text(tr("Ikuti sistem", "Follow system")).tag(AppLanguage.system.rawValue)
            }

            Toggle(tr("Jalankan saat login", "Launch at login"), isOn: Binding(
                get: { ui.loginOn },
                set: { v in
                    do { try LoginItem.set(v); ui.loginOn = v; ui.loginError = nil }
                    catch {
                        ui.loginError = tr("Gagal: \(error.localizedDescription). Pastikan app ada di /Applications.",
                                           "Failed: \(error.localizedDescription). Make sure the app is in /Applications.")
                    }
                }))
            if let e = ui.loginError { Text(e).font(.caption).foregroundStyle(.red) }

            Stepper(String(format: tr("Peringatan jika satu app > %.1f GB", "Alert when one app > %.1f GB"), settings.bloatGB),
                    value: $settings.bloatGB, in: 0.5...6, step: 0.5)
            Toggle(tr("Ingatkan bila Mac sebaiknya di-restart", "Remind me when the Mac should be restarted"),
                   isOn: $settings.restartReminder)
            Toggle(tr("Tampilkan IP publik (memakai layanan ipapi.co)", "Show public IP (uses ipapi.co)"),
                   isOn: $settings.showPublicIP)

            Divider()
            Text(tr("Tampilan di menu bar", "Shown in the menu bar")).font(.subheadline.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                ForEach(BarItem.allCases) { b in
                    Toggle(b.title, isOn: Binding(
                        get: { settings.barItems.contains(b.rawValue) },
                        set: { on in
                            if on { if !settings.barItems.contains(b.rawValue) { settings.barItems.append(b.rawValue) } }
                            else { settings.barItems.removeAll { $0 == b.rawValue } }
                        }))
                }
            }
            .font(.caption)
            Text(tr("Pilih sedikit saja: menu bar yang penuh bisa menyembunyikan ikon lain di MacBook dengan notch.",
                    "Keep it short: a crowded menu bar can hide other icons on MacBooks with a notch."))
                .font(.caption2).foregroundStyle(.secondary)

            Divider()
            ThemeSettingsSection(settings: settings)

            Divider()
            Text(tr("Fitur yang ditampilkan di Beranda", "Features shown on Home")).font(.subheadline.bold())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                ForEach(AppTab.allCases.filter { $0 != .settings }, id: \.self) { t in
                    Toggle(isOn: Binding(
                        get: { !settings.hiddenTabs.contains(t.rawValue) },
                        set: { show in
                            if show { settings.hiddenTabs.removeAll { $0 == t.rawValue } }
                            else if !settings.hiddenTabs.contains(t.rawValue) { settings.hiddenTabs.append(t.rawValue) }
                        })) {
                        Label(t.title, systemImage: t.icon)
                    }
                }
            }

            Divider()
            Text(tr("Whitelist (tidak pernah dibekukan otomatis)", "Whitelist (never auto-frozen)"))
                .font(.subheadline.bold())
            HStack {
                TextField(tr("bundle id, mis. com.google.Chrome", "bundle id, e.g. com.google.Chrome"), text: $ui.newID)
                    .textFieldStyle(.roundedBorder)
                Button(tr("Tambah", "Add")) { add(ui.newID) }
                    .disabled(ui.newID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Menu(tr("Tambah dari aplikasi yang sedang berjalan", "Add from running apps")) {
                ForEach(runningApps, id: \.self) { item in
                    Button(item.name) { add(item.id) }
                }
            }
            ForEach(settings.whitelist, id: \.self) { id in
                HStack {
                    Text(id).font(.caption.monospaced()).lineLimit(1)
                    Spacer()
                    Button { settings.whitelist.removeAll { $0 == id } } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button(tr("Kembalikan whitelist bawaan", "Restore default whitelist")) {
                settings.whitelist = Settings.defaultWhitelist
            }
            .controlSize(.small)

            Divider()
            UpdateSection()

            Divider()
            Text(tr("Tentang \(AppInfo.name)", "About \(AppInfo.name)")).font(.subheadline.bold())
            Button {
                AboutWindow.show()
            } label: {
                Label(tr("Deskripsi program & fitur versi terbaru", "Program description & latest features"), systemImage: "info.circle")
            }
            .controlSize(.small)
            VStack(spacing: 4) {
                StatRow(title: tr("Versi", "Version"), value: AppInfo.version)
                StatRow(title: tr("Pembuat", "Author"), value: AppInfo.author)
                HStack {
                    Text("Email").foregroundStyle(.secondary)
                    Spacer()
                    Link(AppInfo.email, destination: URL(string: "mailto:\(AppInfo.email)")!)
                }
                .font(.callout)
            }

            DonateQRView()
        }
    }

    private var runningApps: [RunningItem] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { a in a.bundleIdentifier.map { RunningItem(id: $0, name: a.localizedName ?? $0) } }
            .filter { !settings.whitelist.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    private func add(_ raw: String) {
        let id = raw.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !settings.whitelist.contains(id) else { return }
        settings.whitelist.append(id)
        ui.newID = ""
    }
}

/// State UI disimpan di ObservableObject (bukan @State) supaya bisa di-build
/// dengan Command Line Tools saja, tanpa plugin SwiftUIMacros dari Xcode penuh.
final class UIState: ObservableObject {
    static let shared = UIState()
    static let home = "home"
    @Published var tab = UIState.home
    @Published var search = ""
    @Published var editFavorites = false
    @Published var newID = ""
    @Published var loginOn = LoginItem.enabled
    @Published var loginError: String?
    @Published var copied = false
    @Published var togglesManage = false
    @Published var historyRange = "24h"
    @Published var historyMetric = "ram"
    @Published var focusEdit: String?
    @Published var tabSel: Set<String> = []
    @Published var appSearch = ""
    @Published var customColorOpen = false
}

// MARK: - Shortcut aplikasi sistem

struct ShortcutBar: View {
    private static let items = SysApp.all

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.items) { item in
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.id) {
                    Button {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                    } label: {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .help(tr(item.idn, item.en))
                }
            }
        }
        .padding(.trailing, 4)
    }
}

// MARK: - Dukungan pengembangan (QRIS)

struct DonateQRView: View {
    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "donate-qr", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if let img = Self.image {
            VStack(spacing: 6) {
                Text(tr("Dukung pengembangan PY-Sys", "Support PY-Sys development"))
                    .font(.subheadline.bold())
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 180, height: 180)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(tr("Pindai QRIS dengan DANA, GoPay, OVO, ShopeePay, atau m-banking. Nominal bebas — terima kasih!",
                        "Scan this QRIS code with any Indonesian e-wallet or mobile banking app. Any amount — thank you!"))
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
    }
}



/// Memberi tahu AetherCore kapan panel menu bar benar-benar terlihat (mode hemat saat tertutup).
/// onAppear/onDisappear tidak selalu terpanggil untuk MenuBarExtra, jadi status jendelanya juga dipantau.
struct PanelVisibilityWatcher: NSViewRepresentable {
    final class Probe: NSView {
        private var observers: [NSObjectProtocol] = []
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers = []
            guard let w = window else { return }
            let report: (Notification) -> Void = { [weak w] _ in
                guard let w else { return }
                AetherCore.shared.setPanelOpen(w.isVisible && w.occlusionState.contains(.visible))
            }
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification,
                         NSWindow.didResignKeyNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: w, queue: .main, using: report))
            }
            DispatchQueue.main.async { AetherCore.shared.setPanelOpen(w.isVisible && w.occlusionState.contains(.visible)) }
        }
        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    }
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}
}
