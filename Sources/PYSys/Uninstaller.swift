import AppKit
import SwiftUI

// MARK: - Uninstaller: hapus app + sisa file di ~/Library

struct InstalledApp: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String
    let size: UInt64
}

struct Leftover: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let size: UInt64
}

final class Uninstaller: ObservableObject {
    static let shared = Uninstaller()

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var loading = false
    @Published var selected: InstalledApp?
    @Published private(set) var leftovers: [Leftover] = []
    @Published var include: Set<String> = []
    @Published var message: String?

    func scan() {
        guard !loading else { return }
        loading = true
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let dirs = [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
            var out: [InstalledApp] = []
            for d in dirs {
                for u in (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? [] where u.pathExtension == "app" {
                    guard let b = Bundle(url: u), let bid = b.bundleIdentifier,
                          bid != Bundle.main.bundleIdentifier, !bid.hasPrefix("com.apple.") else { continue }
                    let name = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                        ?? (b.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? u.deletingPathExtension().lastPathComponent
                    out.append(InstalledApp(url: u, name: name, bundleID: bid, size: StorageCleaner.size(of: u)))
                }
            }
            DispatchQueue.main.async {
                self.apps = out.sorted { $0.size > $1.size }
                self.loading = false
            }
        }
    }

    /// Cari file sisa milik app di ~/Library berdasarkan bundle ID dan nama app.
    func select(_ a: InstalledApp) {
        selected = a
        leftovers = []
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let lib = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library")
            let bid = a.bundleID.lowercased()
            let name = a.name.lowercased()
            let places = ["Application Support", "Caches", "Preferences", "Containers", "Group Containers", "Saved Application State",
                          "Logs", "HTTPStorages", "WebKit", "LaunchAgents", "Application Scripts", "Cookies"]
            var found: [Leftover] = []
            for p in places {
                let dir = lib.appendingPathComponent(p)
                for u in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                    let n = u.lastPathComponent.lowercased()
                    let stem = (n as NSString).deletingPathExtension
                    let hit = n.contains(bid) || stem == name || (name.count >= 5 && stem.hasPrefix(name))
                    guard hit else { continue }
                    found.append(Leftover(url: u, size: StorageCleaner.size(of: u)))
                }
            }
            DispatchQueue.main.async {
                guard self.selected == a else { return }
                self.leftovers = found.sorted { $0.size > $1.size }
                self.include = Set(found.map(\.id))
            }
        }
    }

    func uninstall() {
        guard let a = selected else { return }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: a.bundleID).first {
            running.terminate()
            usleep(800_000)
        }
        let items = [a.url] + leftovers.filter { include.contains($0.id) }.map(\.url)
        let total = a.size + leftovers.filter { include.contains($0.id) }.reduce(0) { $0 + $1.size }
        let al = NSAlert()
        al.messageText = tr("Hapus \(a.name)?", "Uninstall \(a.name)?")
        al.informativeText = tr("\(items.count) item (\(Fmt.disk(Int64(total)))) dipindahkan ke Sampah. Masih bisa dikembalikan sampai Sampah dikosongkan.",
                                "\(items.count) items (\(Fmt.disk(Int64(total)))) will be moved to the Trash. They can be restored until the Trash is emptied.")
        al.addButton(withTitle: tr("Pindahkan ke Sampah", "Move to Trash"))
        al.addButton(withTitle: tr("Batal", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard al.runModal() == .alertFirstButtonReturn else { return }
        var failed: [String] = []
        for u in items where (try? FileManager.default.trashItem(at: u, resultingItemURL: nil)) == nil {
            failed.append(u.lastPathComponent)
        }
        if failed.contains(a.url.lastPathComponent) {
            // App milik admin/root: minta Finder (akan menanyakan password)
            var err: NSDictionary?
            let src = "tell application \"Finder\" to delete (POSIX file \"\(AppleScriptText.escape(a.url.path))\" as alias)"
            _ = NSAppleScript(source: src)?.executeAndReturnError(&err)
            if err == nil { failed.removeAll { $0 == a.url.lastPathComponent } }
        }
        message = failed.isEmpty ? tr("\(a.name) dihapus (\(Fmt.disk(Int64(total)))).", "\(a.name) removed (\(Fmt.disk(Int64(total))).")
                                 : tr("Sebagian gagal dihapus: \(failed.joined(separator: ", "))", "Some items couldn't be removed: \(failed.joined(separator: ", "))")
        selected = nil
        leftovers = []
        scan()
    }
}

struct UninstallTab: View {
    @ObservedObject private var un = Uninstaller.shared
    @ObservedObject private var ui = UIState.shared

    private var filtered: [InstalledApp] {
        ui.appSearch.isEmpty ? un.apps : un.apps.filter { $0.name.localizedCaseInsensitiveContains(ui.appSearch) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let a = un.selected {
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: a.url.path)).resizable().frame(width: 32, height: 32)
                    VStack(alignment: .leading) {
                        Text(a.name).font(.callout.bold())
                        Text(a.bundleID).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(tr("Kembali", "Back")) { un.selected = nil }.controlSize(.small)
                }
                StatRow(title: tr("Aplikasi", "App"), value: Fmt.disk(Int64(a.size)))
                Text(tr("File sisa di ~/Library", "Leftover files in ~/Library")).font(.caption.bold())
                if un.leftovers.isEmpty {
                    Text(tr("Tidak ada file sisa yang ditemukan.", "No leftover files found.")).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(un.leftovers) { l in
                    Toggle(isOn: Binding(get: { un.include.contains(l.id) },
                                         set: { on in if on { un.include.insert(l.id) } else { un.include.remove(l.id) } })) {
                        HStack {
                            Text(l.url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Fmt.disk(Int64(l.size))).monospacedDigit()
                        }
                    }
                    .font(.caption)
                }
                Button(tr("Hapus aplikasi & file terpilih", "Uninstall app & selected files")) { un.uninstall() }
                    .controlSize(.small)
            } else {
                HStack {
                    TextField(tr("Cari aplikasi…", "Search apps…"), text: $ui.appSearch).textFieldStyle(.roundedBorder)
                    Button(tr("Muat ulang", "Reload")) { un.scan() }.controlSize(.small)
                }
                if un.loading { ProgressView().controlSize(.small) }
                ForEach(filtered) { a in
                    Button { un.select(a) } label: {
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: a.url.path)).resizable().frame(width: 20, height: 20)
                            Text(a.name).lineLimit(1)
                            Spacer()
                            Text(Fmt.disk(Int64(a.size))).foregroundStyle(.secondary).monospacedDigit()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
                Text(tr("App bawaan Apple tidak ditampilkan. Semua item dipindah ke Sampah, jadi masih bisa dikembalikan.",
                        "Built-in Apple apps aren't listed. Everything goes to the Trash, so it can still be restored."))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let m = un.message { Text(m).font(.caption).foregroundStyle(.secondary) }
        }
        .onAppear { if un.apps.isEmpty { un.scan() } }
    }
}

// MARK: - File besar & duplikat

struct FoundFile: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let size: UInt64
}

struct DupGroup: Identifiable {
    let id: String          // hash
    let files: [FoundFile]
    var wasted: UInt64 { (files.first?.size ?? 0) * UInt64(max(files.count - 1, 0)) }
}

final class FileFinder: ObservableObject {
    static let shared = FileFinder()

    @Published var root: URL = FileManager.default.homeDirectoryForCurrentUser
    @Published var minLargeMB: Double = 200
    @Published private(set) var large: [FoundFile] = []
    @Published private(set) var dups: [DupGroup] = []
    @Published private(set) var scanning = false
    @Published private(set) var progress = ""
    @Published var picked: Set<String> = []
    @Published var message: String?
    private var cancel = false

    func scan() {
        guard !scanning else { return }
        scanning = true
        cancel = false
        large = []
        dups = []
        picked = []
        let root = self.root, minLarge = UInt64(minLargeMB * 1_000_000)
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            let skip = ["Library", ".Trash", "node_modules", ".git", ".npm", ".cache", "Pictures/Photos Library.photoslibrary"]
            var bySize: [UInt64: [URL]] = [:]
            var big: [FoundFile] = []
            var n = 0
            if let e = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let u as URL in e {
                    if self.cancel { break }
                    let rel = u.path.replacingOccurrences(of: root.path + "/", with: "")
                    if skip.contains(where: { rel == $0 || rel.hasPrefix($0 + "/") }) { e.skipDescendants(); continue }
                    guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true, v.isSymbolicLink != true,
                          let s = v.fileSize, s > 0 else { continue }
                    let size = UInt64(s)
                    if size >= minLarge { big.append(FoundFile(url: u, size: size)) }
                    if size >= 1_000_000 { bySize[size, default: []].append(u) }
                    n += 1
                    if n % 2000 == 0 { DispatchQueue.main.async { self.progress = tr("\(n) file diperiksa…", "\(n) files checked…") } }
                }
            }
            // Duplikat: ukuran sama → hash 1 MB pertama → hash penuh
            var groups: [DupGroup] = []
            for (size, urls) in bySize where urls.count > 1 && !self.cancel {
                var byHead: [String: [URL]] = [:]
                for u in urls { if let h = Self.hash(u, limit: 1_000_000) { byHead[h, default: []].append(u) } }
                for (_, same) in byHead where same.count > 1 {
                    var byFull: [String: [URL]] = [:]
                    for u in same {
                        if let h = size <= 1_000_000 ? Self.hash(u, limit: 1_000_000) : Self.hash(u, limit: nil) {
                            byFull[h, default: []].append(u)
                        }
                    }
                    for (h, f) in byFull where f.count > 1 {
                        groups.append(DupGroup(id: h, files: f.map { FoundFile(url: $0, size: size) }
                            .sorted { $0.url.path.count < $1.url.path.count }))
                    }
                }
            }
            DispatchQueue.main.async {
                self.large = big.sorted { $0.size > $1.size }.prefix(200).map { $0 }
                self.dups = groups.sorted { $0.wasted > $1.wasted }
                self.scanning = false
                self.progress = ""
            }
        }
    }

    func stop() { cancel = true }

    /// FNV-1a 64-bit (cukup untuk membandingkan isi file; tidak untuk keamanan).
    private static func hash(_ u: URL, limit: Int?) -> String? {
        guard let h = try? FileHandle(forReadingFrom: u) else { return nil }
        defer { try? h.close() }
        var v: UInt64 = 0xcbf29ce484222325
        var read = 0
        while true {
            let want = limit.map { min(1 << 20, $0 - read) } ?? (1 << 20)
            if want <= 0 { break }
            guard let d = try? h.read(upToCount: want), !d.isEmpty else { break }
            for b in d { v = (v ^ UInt64(b)) &* 0x100000001b3 }
            read += d.count
        }
        return String(v, radix: 16) + "-\(read)"
    }

    /// Tandai semua kecuali salinan pertama di setiap grup duplikat.
    func pickExtraCopies() {
        picked = Set(dups.flatMap { $0.files.dropFirst().map(\.id) })
    }

    func trashPicked() {
        let all = large + dups.flatMap(\.files)
        let urls = Array(Set(all.filter { picked.contains($0.id) }.map(\.url)))
        guard !urls.isEmpty else { return }
        let total = Array(Set(all.filter { picked.contains($0.id) })).reduce(UInt64(0)) { $0 + $1.size }
        let al = NSAlert()
        al.messageText = tr("Pindahkan \(urls.count) file ke Sampah?", "Move \(urls.count) files to the Trash?")
        al.informativeText = tr("Total \(Fmt.disk(Int64(total))). Masih bisa dikembalikan dari Sampah.", "Total \(Fmt.disk(Int64(total))). They can be restored from the Trash.")
        al.addButton(withTitle: tr("Pindahkan", "Move"))
        al.addButton(withTitle: tr("Batal", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard al.runModal() == .alertFirstButtonReturn else { return }
        var moved = 0
        for u in urls where (try? FileManager.default.trashItem(at: u, resultingItemURL: nil)) != nil { moved += 1 }
        let gone = Set(urls.map(\.path))
        large.removeAll { gone.contains($0.url.path) }
        dups = dups.map { DupGroup(id: $0.id, files: $0.files.filter { !gone.contains($0.url.path) }) }.filter { $0.files.count > 1 }
        picked = []
        message = tr("\(moved) file dipindahkan ke Sampah.", "\(moved) files moved to the Trash.")
    }
}

struct FileFinderTab: View {
    @ObservedObject private var ff = FileFinder.shared

    private func row(_ f: FoundFile) -> some View {
        Toggle(isOn: Binding(get: { ff.picked.contains(f.id) },
                             set: { on in if on { ff.picked.insert(f.id) } else { ff.picked.remove(f.id) } })) {
            HStack {
                Text(f.url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(Fmt.disk(Int64(f.size))).monospacedDigit()
                Button { NSWorkspace.shared.activateFileViewerSelecting([f.url]) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless)
            }
        }
        .font(.caption)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("Folder: ", "Folder: ") + ff.root.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(.caption).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(tr("Ganti…", "Change…")) {
                    let p = NSOpenPanel()
                    p.canChooseDirectories = true
                    p.canChooseFiles = false
                    NSApp.activate(ignoringOtherApps: true)
                    if p.runModal() == .OK, let u = p.url { ff.root = u }
                }
                .controlSize(.small)
            }
            HStack {
                Text(tr("File besar ≥", "Large files ≥")).font(.caption)
                Picker("", selection: $ff.minLargeMB) {
                    Text("100 MB").tag(100.0)
                    Text("200 MB").tag(200.0)
                    Text("500 MB").tag(500.0)
                    Text("1 GB").tag(1000.0)
                }
                .labelsHidden().frame(width: 90)
                Spacer()
                if ff.scanning {
                    ProgressView().controlSize(.small)
                    Button(tr("Berhenti", "Stop")) { ff.stop() }.controlSize(.small)
                } else {
                    Button(tr("Pindai", "Scan")) { ff.scan() }.controlSize(.small)
                }
            }
            if !ff.progress.isEmpty { Text(ff.progress).font(.caption2).foregroundStyle(.secondary) }

            if !ff.large.isEmpty {
                Text(tr("File besar (\(ff.large.count))", "Large files (\(ff.large.count))")).font(.subheadline.bold())
                ForEach(ff.large.prefix(30)) { row($0) }
            }
            if !ff.dups.isEmpty {
                let wasted = ff.dups.reduce(UInt64(0)) { $0 + $1.wasted }
                HStack {
                    Text(tr("Duplikat: \(ff.dups.count) grup · \(Fmt.disk(Int64(wasted))) terbuang", "Duplicates: \(ff.dups.count) groups · \(Fmt.disk(Int64(wasted))) wasted"))
                        .font(.subheadline.bold())
                    Spacer()
                    Button(tr("Pilih salinan ekstra", "Select extra copies")) { ff.pickExtraCopies() }.controlSize(.small)
                }
                ForEach(ff.dups.prefix(30)) { g in
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(g.files) { row($0) }
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                }
            }
            if !ff.picked.isEmpty {
                Button(tr("Pindahkan \(ff.picked.count) file terpilih ke Sampah", "Move \(ff.picked.count) selected files to the Trash")) { ff.trashPicked() }
                    .controlSize(.small)
            }
            if let m = ff.message { Text(m).font(.caption).foregroundStyle(.secondary) }
            Text(tr("Folder Library, .git, node_modules, cache, dan isi paket (.app, .photoslibrary) dilewati supaya aman. Duplikat dicari untuk file ≥ 1 MB dengan isi yang benar-benar sama.",
                    "Library, .git, node_modules, caches and package contents (.app, .photoslibrary) are skipped for safety. Duplicates are files ≥ 1 MB with exactly the same content."))
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}


/// Teks aman untuk disisipkan di dalam string AppleScript ("…"): garis miring terbalik dan tanda kutip di-escape.
enum AppleScriptText {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
