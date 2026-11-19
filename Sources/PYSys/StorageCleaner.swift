import Foundation
import AppKit

/// Satu kategori yang bisa dibersihkan. Isi folder dihapus permanen (data yang bisa dibuat ulang),
/// kecuali `toTrash` = dipindah ke Sampah supaya masih bisa dikembalikan.
struct CleanTarget: Identifiable {
    let id: String
    let titleID: String
    let titleEN: String
    let noteID: String
    let noteEN: String
    let icon: String
    let folders: [URL]
    var title: String { tr(titleID, titleEN) }
    var note: String { tr(noteID, noteEN) }
}

struct OldFile: Identifiable {
    var id: String { url.path }
    let url: URL
    let size: UInt64
    let modified: Date
}

final class StorageCleaner: ObservableObject {
    static let shared = StorageCleaner()

    @Published private(set) var sizes: [String: UInt64] = [:]
    @Published private(set) var trashSize: UInt64?
    @Published private(set) var downloads: [OldFile] = []
    @Published private(set) var scanning = false
    @Published private(set) var busy = false
    @Published var message: String?

    let targets: [CleanTarget]
    private let home = FileManager.default.homeDirectoryForCurrentUser
    static let downloadAgeDays = 90
    static let downloadMinBytes: UInt64 = 500 * 1_000_000

    private init() {
        let h = FileManager.default.homeDirectoryForCurrentUser
        func u(_ p: String) -> URL { h.appendingPathComponent(p, isDirectory: true) }
        let condaPkgs = [".conda/pkgs", "anaconda3/pkgs", "miniconda3/pkgs", "opt/anaconda3/pkgs", "opt/miniconda3/pkgs", "miniforge3/pkgs"].map(u)
        targets = [
            CleanTarget(id: "caches", titleID: "Cache aplikasi", titleEN: "App caches",
                        noteID: "~/Library/Caches · dibuat ulang otomatis oleh aplikasi",
                        noteEN: "~/Library/Caches · apps rebuild these automatically",
                        icon: "archivebox", folders: [u("Library/Caches")]),
            CleanTarget(id: "logs", titleID: "Log", titleEN: "Logs",
                        noteID: "~/Library/Logs · catatan diagnostik lama",
                        noteEN: "~/Library/Logs · old diagnostic logs",
                        icon: "doc.text", folders: [u("Library/Logs")]),
            CleanTarget(id: "xcode", titleID: "Xcode DerivedData", titleEN: "Xcode DerivedData",
                        noteID: "Hasil build Xcode; dibuat ulang saat build berikutnya",
                        noteEN: "Xcode build products; rebuilt on the next build",
                        icon: "hammer", folders: [u("Library/Developer/Xcode/DerivedData")]),
            CleanTarget(id: "dev", titleID: "Cache developer", titleEN: "Developer caches",
                        noteID: "npm, ~/.cache dan paket unduhan conda (setara conda clean)",
                        noteEN: "npm, ~/.cache and downloaded conda packages (like conda clean)",
                        icon: "shippingbox", folders: [u(".npm/_cacache"), u(".cache")] + condaPkgs),
        ]
    }

    // MARK: Pindai

    func scan() {
        guard !scanning else { return }
        scanning = true
        let targets = self.targets
        let trashURL = home.appendingPathComponent(".Trash", isDirectory: true)
        let downloadsURL = home.appendingPathComponent("Downloads", isDirectory: true)
        DispatchQueue.global(qos: .utility).async {
            var result: [String: UInt64] = [:]
            for t in targets { result[t.id] = t.folders.reduce(0) { $0 + Self.size(of: $1) } }
            let trash: UInt64? = Self.isReadable(trashURL) ? Self.size(of: trashURL) : nil
            let old = Self.findDownloads(in: downloadsURL)
            DispatchQueue.main.async {
                self.sizes = result
                self.trashSize = trash
                self.downloads = old
                self.scanning = false
            }
        }
    }

    static func size(of url: URL) -> UInt64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return UInt64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
                                    options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: UInt64 = 0
        for case let f as URL in e {
            if let v = try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
               v.isRegularFile == true {
                total += UInt64(v.totalFileAllocatedSize ?? 0)
            }
        }
        return total
    }

    private static func isReadable(_ url: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
    }

    /// File/folder di Downloads yang lebih tua dari 90 hari atau lebih besar dari 500 MB.
    private static func findDownloads(in dir: URL) -> [OldFile] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                                                      options: [.skipsHiddenFiles]) else { return [] }
        let cutoff = Date().addingTimeInterval(-Double(downloadAgeDays) * 86_400)
        var result: [OldFile] = []
        for item in items {
            let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            let s = size(of: item)
            if modified < cutoff || s >= downloadMinBytes {
                result.append(OldFile(url: item, size: s, modified: modified))
            }
        }
        return Array(result.sorted { $0.size > $1.size }.prefix(20))
    }

    // MARK: Bersihkan

    private func confirm(_ title: String, _ text: String, _ button: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = .warning
        a.addButton(withTitle: button)
        a.addButton(withTitle: tr("Batal", "Cancel"))
        return a.runModal() == .alertFirstButtonReturn
    }

    func clean(_ t: CleanTarget) {
        let size = Fmt.disk(Int64(sizes[t.id] ?? 0))
        guard !busy, confirm(tr("Bersihkan \(t.title)?", "Clean \(t.title)?"),
                             tr("Sekitar \(size) akan dihapus permanen. Isi ini dibuat ulang otomatis bila diperlukan. Sebaiknya tutup aplikasi lain dulu.",
                                "About \(size) will be deleted permanently. It is recreated automatically when needed. Closing other apps first is recommended."),
                             tr("Bersihkan", "Clean")) else { return }
        busy = true
        DispatchQueue.global(qos: .utility).async {
            let before = t.folders.reduce(UInt64(0)) { $0 + Self.size(of: $1) }
            let fm = FileManager.default
            for folder in t.folders {
                guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
                for item in items { try? fm.removeItem(at: item) }   // file yang sedang dipakai dilewati
            }
            let after = t.folders.reduce(UInt64(0)) { $0 + Self.size(of: $1) }
            let freed = before > after ? before - after : 0
            DispatchQueue.main.async {
                self.busy = false
                self.message = tr("\(t.title): \(Fmt.disk(Int64(freed))) dibebaskan.", "\(t.title): \(Fmt.disk(Int64(freed))) freed.")
                self.scan()
            }
        }
    }

    func moveToTrash(_ files: [OldFile]) {
        guard !files.isEmpty else { return }
        let total = Fmt.disk(Int64(files.reduce(0) { $0 + $1.size }))
        guard confirm(tr("Pindahkan \(files.count) item ke Sampah?", "Move \(files.count) items to Trash?"),
                      tr("Total \(total). Item masih bisa dikembalikan dari Sampah sampai Sampah dikosongkan.",
                         "Total \(total). Items can be restored from the Trash until it is emptied."),
                      tr("Pindahkan", "Move")) else { return }
        var moved = 0
        for f in files where (try? FileManager.default.trashItem(at: f.url, resultingItemURL: nil)) != nil { moved += 1 }
        message = tr("\(moved) item dipindahkan ke Sampah.", "\(moved) items moved to Trash.")
        scan()
    }

    func emptyTrash() {
        let size = trashSize.map { Fmt.disk(Int64($0)) } ?? "?"
        guard confirm(tr("Kosongkan Sampah?", "Empty Trash?"),
                      tr("Sekitar \(size) akan dihapus permanen dan tidak bisa dikembalikan.",
                         "About \(size) will be deleted permanently and cannot be restored."),
                      tr("Kosongkan", "Empty")) else { return }
        var err: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&err)
        message = err == nil ? tr("Sampah dikosongkan.", "Trash emptied.")
                             : tr("Gagal mengosongkan Sampah. Izinkan PY-Sys mengontrol Finder di System Settings → Privacy & Security → Automation.",
                                  "Could not empty the Trash. Allow PY-Sys to control Finder in System Settings → Privacy & Security → Automation.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.scan() }
    }
}

enum SysInfo {
    static func string(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "–" }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "–" }
        return String(cString: buf)
    }
    static var chip: String { string("machdep.cpu.brand_string") }
    static var model: String { string("hw.model") }
    static var macOS: String { ProcessInfo.processInfo.operatingSystemVersionString }
    static var ram: String { Fmt.bytes(SystemStats.sysctl("hw.memsize", UInt64(0)) ?? 0) }
    static var cores: String {
        let p = SystemStats.sysctl("hw.perflevel0.logicalcpu", Int32(0)) ?? 0
        let e = SystemStats.sysctl("hw.perflevel1.logicalcpu", Int32(0)) ?? 0
        return e > 0 ? "\(p) P + \(e) E" : "\(SystemStats.sysctl("hw.logicalcpu", Int32(0)) ?? 0)"
    }
    /// Jumlah siklus pengisian baterai (nil di Mac tanpa baterai).
    static var batteryCycles: Int? { SensorReader.battery()?.cycles }

    static var summary: String {
        var s = "PY-Sys \(AppInfo.version)\nModel: \(model)\nChip: \(chip) (\(cores))\nRAM: \(ram)\nmacOS: \(macOS)"
        if let c = batteryCycles { s += "\nBattery cycle count: \(c)" }
        if let m = AppleBatteryInfo.shared.maxCapacity ?? SensorReader.battery()?.health.map({ $0 * 100 }) {
            s += String(format: "\nBattery maximum capacity: %.0f%%", m)
        }
        return s
    }
}
