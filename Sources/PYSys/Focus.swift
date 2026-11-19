import AppKit
import SwiftUI

// MARK: - Profil kerja (Mode Fokus RAM)

struct FocusProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var icon: String
    var keep: [String]          // bundle ID yang tetap jalan
    var quitOthers: Bool        // false = bekukan (Cryo-Sleep), true = tutup
}

final class FocusStore: ObservableObject {
    static let shared = FocusStore()
    private let key = "focusProfiles", activeKey = "focusActive"

    @Published var profiles: [FocusProfile] { didSet { persist() } }
    @Published private(set) var active: String?
    @Published var lastMessage: String?
    private var frozenByFocus: [pid_t] = []

    static let browsers = ["com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser",
                           "com.apple.Safari", "org.mozilla.firefox", "com.vivaldi.Vivaldi", "com.operasoftware.Opera"]
    static let terminals = ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty"]

    static let presets: [FocusProfile] = [
        FocusProfile(id: "ai", name: tr("Riset AI / Coding", "AI research / Coding"), icon: "sparkles",
                     keep: terminals + browsers + ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode",
                                                   "com.anthropic.claudefordesktop", "com.openai.chat", "com.docker.docker",
                                                   "ai.elementlabs.lmstudio", "com.electron.ollama"],
                     quitOthers: false),
        FocusProfile(id: "write", name: tr("Menulis / Disertasi", "Writing / Thesis"), icon: "doc.text",
                     keep: browsers + ["com.microsoft.Word", "com.apple.iWork.Pages", "org.zotero.zotero", "com.mendeley.desktop",
                                       "com.microsoft.Excel", "com.apple.Preview", "com.readdle.PDFExpert-Mac", "com.anthropic.claudefordesktop"],
                     quitOthers: false),
        FocusProfile(id: "present", name: tr("Presentasi / Rapat", "Presenting / Meetings"), icon: "person.3",
                     keep: ["com.microsoft.Powerpoint", "com.apple.iWork.Keynote", "us.zoom.xos", "com.microsoft.teams2",
                            "com.apple.FaceTime", "com.google.Chrome", "com.apple.Safari", "com.apple.Preview"],
                     quitOthers: false),
    ]

    /// Tidak pernah dibekukan/ditutup oleh profil apa pun.
    static let always: Set<String> = ["com.apple.finder", "com.apple.systempreferences", "com.apple.ActivityMonitor",
                                      "com.displaylink.DisplayLinkUserAgent", "id.pysys.app"]

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let p = try? JSONDecoder().decode([FocusProfile].self, from: d), !p.isEmpty {
            profiles = p
        } else {
            profiles = Self.presets
        }
        active = UserDefaults.standard.string(forKey: activeKey)
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(d, forKey: key) }
    }

    /// App biasa yang sedang jalan dan akan terkena profil ini.
    func affected(by p: FocusProfile, groups: [AppGroup]) -> [AppGroup] {
        let keep = Set(p.keep).union(Self.always)
        let wl = Set(AetherCore.shared.settings.whitelist)
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return groups.filter { g in
            guard g.isApp, let b = g.bundleID, !keep.contains(b), g.mainPID != getpid(), g.mainPID != front else { return false }
            return p.quitOthers || !wl.contains(b) || !Self.respectWhitelist
        }
    }

    static var respectWhitelist: Bool {
        get { UserDefaults.standard.object(forKey: "focusRespectWL") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "focusRespectWL") }
    }

    func apply(_ p: FocusProfile) {
        let core = AetherCore.shared
        if active != nil { end(silent: true) }
        let targets = affected(by: p, groups: core.groups)
        var bytes: UInt64 = 0
        for g in targets {
            bytes += g.footprint
            if p.quitOthers {
                NSRunningApplication(processIdentifier: g.mainPID)?.terminate()
            } else {
                core.freezer.manualFreeze(g)
                frozenByFocus.append(g.mainPID)
            }
        }
        active = p.id
        UserDefaults.standard.set(p.id, forKey: activeKey)
        lastMessage = p.quitOthers
            ? tr("\(targets.count) app ditutup (±\(Fmt.bytes(bytes))).", "\(targets.count) apps closed (about \(Fmt.bytes(bytes))).")
            : tr("\(targets.count) app dibekukan (±\(Fmt.bytes(bytes))). Membuka app yang beku akan mencairkannya.",
                 "\(targets.count) apps frozen (about \(Fmt.bytes(bytes))). Opening a frozen app thaws it.")
    }

    func end(silent: Bool = false) {
        let fz = AetherCore.shared.freezer
        for pid in frozenByFocus { fz.thaw(pid) }
        frozenByFocus.removeAll()
        active = nil
        UserDefaults.standard.removeObject(forKey: activeKey)
        if !silent { lastMessage = tr("Mode fokus selesai. App yang dibekukan sudah dicairkan.", "Focus ended. Frozen apps were thawed.") }
    }

    func newProfileFromRunning() {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleIdentifier)
        let p = FocusProfile(id: UUID().uuidString, name: tr("Profil baru", "New profile"), icon: "star",
                             keep: Array(Set(running)).sorted(), quitOthers: false)
        profiles.append(p)
        UIState.shared.focusEdit = p.id
    }
}

struct FocusTab: View {
    @ObservedObject var core: AetherCore
    @ObservedObject private var store = FocusStore.shared
    @ObservedObject private var ui = UIState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Pilih profil sesuai pekerjaan. App di luar profil dibekukan (atau ditutup) supaya RAM lega untuk yang sedang dipakai.",
                    "Pick a profile for your work. Apps outside it are frozen (or closed) so RAM is free for what you're using."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if let a = store.active, let p = store.profiles.first(where: { $0.id == a }) {
                HStack {
                    Label(tr("Aktif: \(p.name)", "Active: \(p.name)"), systemImage: p.icon).font(.callout.bold())
                    Spacer()
                    Button(tr("Akhiri fokus", "End focus")) { store.end() }.controlSize(.small)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent.opacity(0.15)))
            }
            if let m = store.lastMessage { Text(m).font(.caption).foregroundStyle(.secondary) }

            ForEach(store.profiles) { p in
                let hit = store.affected(by: p, groups: core.groups)
                let bytes = hit.reduce(UInt64(0)) { $0 + $1.footprint }
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: p.icon).frame(width: 18)
                            Text(p.name).font(.callout.bold())
                            Spacer()
                            Button {
                                ui.focusEdit = ui.focusEdit == p.id ? nil : p.id
                            } label: { Image(systemName: ui.focusEdit == p.id ? "chevron.up" : "pencil") }
                                .buttonStyle(.borderless)
                            Button(p.quitOthers ? tr("Tutup lainnya", "Close others") : tr("Terapkan", "Apply")) { store.apply(p) }
                                .controlSize(.small)
                                .disabled(hit.isEmpty)
                        }
                        Text(hit.isEmpty
                             ? tr("Tidak ada app yang perlu dibekukan sekarang.", "Nothing to freeze right now.")
                             : tr("Akan \(p.quitOthers ? "menutup" : "membekukan") \(hit.count) app · ±\(Fmt.bytes(bytes)): ",
                                  "Will \(p.quitOthers ? "close" : "freeze") \(hit.count) apps · about \(Fmt.bytes(bytes)): ")
                               + hit.prefix(4).map(\.name).joined(separator: ", ") + (hit.count > 4 ? "…" : ""))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        if ui.focusEdit == p.id { FocusEditor(profileID: p.id) }
                    }
                }
            }

            HStack {
                Button(tr("Profil baru dari app yang sedang jalan", "New profile from running apps")) { store.newProfileFromRunning() }
                    .controlSize(.small)
                Spacer()
            }
            Toggle(tr("Jangan bekukan app di whitelist Cryo-Sleep", "Don't freeze apps on the Cryo-Sleep whitelist"), isOn: Binding(
                get: { FocusStore.respectWhitelist },
                set: { FocusStore.respectWhitelist = $0; store.objectWillChange.send() }))
                .font(.caption)
        }
    }
}

struct FocusEditor: View {
    let profileID: String
    @ObservedObject private var store = FocusStore.shared

    private var index: Int? { store.profiles.firstIndex { $0.id == profileID } }

    var body: some View {
        if let i = index {
            let running = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && !FocusStore.always.contains($0.bundleIdentifier!) }
                .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            VStack(alignment: .leading, spacing: 6) {
                TextField(tr("Nama profil", "Profile name"), text: $store.profiles[i].name)
                Picker(tr("App lain", "Other apps"), selection: $store.profiles[i].quitOthers) {
                    Text(tr("Bekukan (Cryo-Sleep)", "Freeze (Cryo-Sleep)")).tag(false)
                    Text(tr("Tutup", "Quit")).tag(true)
                }
                .pickerStyle(.segmented)
                Text(tr("Tetap jalan dalam profil ini:", "Keep running in this profile:")).font(.caption.bold())
                ForEach(running, id: \.processIdentifier) { app in
                    let b = app.bundleIdentifier ?? ""
                    Toggle(isOn: Binding(
                        get: { store.profiles[i].keep.contains(b) },
                        set: { on in
                            if on { if !store.profiles[i].keep.contains(b) { store.profiles[i].keep.append(b) } }
                            else { store.profiles[i].keep.removeAll { $0 == b } }
                        })) {
                        HStack(spacing: 6) {
                            if let ic = app.icon { Image(nsImage: ic).resizable().frame(width: 14, height: 14) }
                            Text(app.localizedName ?? b)
                        }
                    }
                    .font(.caption)
                }
                Text(tr("Hanya app yang sedang jalan yang ditampilkan. Pilihan untuk app lain tetap tersimpan.",
                        "Only running apps are listed. Choices for other apps are kept."))
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button(tr("Hapus profil", "Delete profile"), role: .destructive) {
                        store.profiles.remove(at: i)
                        UIState.shared.focusEdit = nil
                    }
                    .controlSize(.small)
                    .disabled(store.profiles.count <= 1)
                }
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Tidurkan tab browser (simpan & tutup, pulihkan nanti)

struct BrowserTabItem: Identifiable, Hashable {
    var id: String { "\(bundle)|\(window)|\(index)" }
    let bundle: String
    let browser: String
    let window: Int
    let index: Int
    let url: String
    let title: String
}

struct SavedTab: Codable, Identifiable, Hashable {
    var id: String { "\(bundle)|\(url)|\(saved.timeIntervalSince1970)" }
    let bundle: String
    let browser: String
    let url: String
    let title: String
    let saved: Date
}

final class TabSleeper: ObservableObject {
    static let shared = TabSleeper()

    @Published private(set) var tabs: [BrowserTabItem] = []
    @Published private(set) var saved: [SavedTab] = []
    @Published var message: String?
    @Published private(set) var loading = false

    /// bundle ID → (nama aplikasi untuk AppleScript, properti judul tab)
    static let scriptable: [String: (app: String, title: String)] = [
        "com.google.Chrome": ("Google Chrome", "title"),
        "com.microsoft.edgemac": ("Microsoft Edge", "title"),
        "com.brave.Browser": ("Brave Browser", "title"),
        "com.vivaldi.Vivaldi": ("Vivaldi", "title"),
        "com.operasoftware.Opera": ("Opera", "title"),
        "company.thebrowser.Browser": ("Arc", "title"),
        "com.apple.Safari": ("Safari", "name"),
    ]

    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PY-Sys", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("saved-tabs.json")
    }

    init() {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        if let d = try? Data(contentsOf: url), let s = try? dec.decode([SavedTab].self, from: d) { saved = s }
    }

    private func persist() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        if let d = try? enc.encode(saved) { try? d.write(to: url, options: .atomic) }
    }

    private func run(_ src: String) -> String? {
        var err: NSDictionary?
        let r = NSAppleScript(source: src)?.executeAndReturnError(&err)
        return err == nil ? (r?.stringValue ?? "") : nil
    }

    func refresh() {
        loading = true
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var list: [BrowserTabItem] = []
        var failed: [String] = []
        for (bid, info) in Self.scriptable where running.contains(bid) {
            let src = """
            set sep to character id 9
            set out to ""
            tell application "\(info.app)"
                repeat with w in windows
                    set wid to id of w
                    set i to 0
                    repeat with t in tabs of w
                        set i to i + 1
                        set out to out & wid & sep & i & sep & (URL of t) & sep & (\(info.title) of t) & linefeed
                    end repeat
                end repeat
            end tell
            return out
            """
            guard let out = run(src) else { failed.append(info.app); continue }
            for line in out.split(separator: "\n") {
                let f = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
                guard f.count >= 3, let w = Int(f[0]), let i = Int(f[1]) else { continue }
                list.append(BrowserTabItem(bundle: bid, browser: info.app, window: w, index: i,
                                           url: f[2], title: f.count > 3 ? f[3] : f[2]))
            }
        }
        tabs = list.sorted { ($0.browser, $0.window, $0.index) < ($1.browser, $1.window, $1.index) }
        loading = false
        message = failed.isEmpty ? nil
            : tr("\(failed.joined(separator: ", ")) belum bisa dibaca. Izinkan PY-Sys di Privacy & Security → Automation.",
                 "Couldn't read \(failed.joined(separator: ", ")). Allow PY-Sys in Privacy & Security → Automation.")
    }

    /// Tutup tab (indeks dari belakang supaya urutan tidak bergeser). Simpan dulu bila diminta.
    func close(_ items: [BrowserTabItem], save: Bool) {
        guard !items.isEmpty else { return }
        if save {
            let now = Date()
            saved.insert(contentsOf: items.map { SavedTab(bundle: $0.bundle, browser: $0.browser, url: $0.url, title: $0.title, saved: now) }, at: 0)
            persist()
        }
        let byWindow = Dictionary(grouping: items) { "\($0.bundle)|\($0.window)" }
        for (_, group) in byWindow {
            guard let first = group.first, let info = Self.scriptable[first.bundle] else { continue }
            let cmds = group.map(\.index).sorted(by: >).map { "close tab \($0) of window id \(first.window)" }.joined(separator: "\n")
            _ = run("tell application \"\(info.app)\"\n\(cmds)\nend tell")
        }
        message = save ? tr("\(items.count) tab disimpan dan ditutup.", "\(items.count) tabs saved and closed.")
                       : tr("\(items.count) tab ditutup.", "\(items.count) tabs closed.")
        refresh()
    }

    /// Tab dengan URL yang sama persis (selain yang pertama) di browser yang sama.
    var duplicates: [BrowserTabItem] {
        var seen: Set<String> = []
        return tabs.filter { t in
            let k = t.bundle + "|" + t.url
            if seen.contains(k) { return true }
            seen.insert(k)
            return false
        }
    }

    func restore(_ s: [SavedTab]) {
        for t in s {
            guard let u = URL(string: t.url) else { continue }
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: t.bundle) {
                NSWorkspace.shared.open([u], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(u)
            }
        }
        forget(s)
    }

    func forget(_ s: [SavedTab]) {
        let ids = Set(s.map(\.id))
        saved.removeAll { ids.contains($0.id) }
        persist()
    }
}

struct TabSleepTab: View {
    @ObservedObject private var ts = TabSleeper.shared
    @ObservedObject private var ui = UIState.shared

    private var selected: [BrowserTabItem] { ts.tabs.filter { ui.tabSel.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Setiap tab terbuka memakan RAM. Simpan tab yang belum dibaca lalu tutup; buka lagi kapan saja dari daftar di bawah.",
                    "Every open tab uses RAM. Save tabs you haven't read and close them; reopen them anytime from the list below."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(ts.tabs.isEmpty ? tr("Muat daftar tab", "Load tabs") : tr("Muat ulang", "Reload")) {
                    ts.refresh()
                    ui.tabSel = []
                }
                .controlSize(.small)
                Spacer()
                let dup = ts.duplicates
                if !dup.isEmpty {
                    Button(tr("Tutup \(dup.count) duplikat", "Close \(dup.count) duplicates")) { ts.close(dup, save: false) }
                        .controlSize(.small)
                }
            }

            if !ts.tabs.isEmpty {
                Text(tr("\(ts.tabs.count) tab terbuka · \(selected.count) dipilih", "\(ts.tabs.count) open tabs · \(selected.count) selected"))
                    .font(.caption.bold())
                ForEach(Array(Dictionary(grouping: ts.tabs, by: \.browser).keys).sorted(), id: \.self) { b in
                    Text(b).font(.caption.bold()).foregroundStyle(.secondary).padding(.top, 4)
                    ForEach(ts.tabs.filter { $0.browser == b }) { t in
                        Toggle(isOn: Binding(
                            get: { ui.tabSel.contains(t.id) },
                            set: { on in if on { ui.tabSel.insert(t.id) } else { ui.tabSel.remove(t.id) } })) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(t.title).lineLimit(1)
                                Text(URL(string: t.url)?.host ?? t.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .font(.caption)
                    }
                }
                HStack {
                    Button(tr("Simpan & tutup", "Save & close")) {
                        ts.close(selected, save: true)
                        ui.tabSel = []
                    }
                    .disabled(selected.isEmpty)
                    Button(tr("Tutup saja", "Just close")) {
                        ts.close(selected, save: false)
                        ui.tabSel = []
                    }
                    .disabled(selected.isEmpty)
                    Spacer()
                }
                .controlSize(.small)
            }

            if let m = ts.message {
                Text(m).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }

            if !ts.saved.isEmpty {
                Divider()
                HStack {
                    Text(tr("Tab tersimpan (\(ts.saved.count))", "Saved tabs (\(ts.saved.count))")).font(.subheadline.bold())
                    Spacer()
                    Button(tr("Buka semua", "Open all")) { ts.restore(ts.saved) }.controlSize(.small)
                }
                ForEach(ts.saved) { s in
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(s.title).lineLimit(1)
                            Text("\(s.browser) · \(URL(string: s.url)?.host ?? s.url)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button { ts.restore([s]) } label: { Image(systemName: "arrow.up.forward.square") }
                            .buttonStyle(.borderless).help(tr("Buka lagi", "Reopen"))
                        Button { ts.forget([s]) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help(tr("Hapus dari daftar", "Remove from list"))
                    }
                    .font(.caption)
                }
            }

            Text(tr("Firefox belum didukung (tidak punya AppleScript). Chrome, Edge, dan Brave juga punya Memory Saver bawaan di Settings › Performance.",
                    "Firefox isn't supported (no AppleScript). Chrome, Edge and Brave also have a built-in Memory Saver in Settings › Performance."))
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
