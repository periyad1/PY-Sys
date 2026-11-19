import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Ekspor / impor pengaturan

enum SettingsTransfer {
    private static let appID = "id.pysys.app"
    private static let format = 1

    /// Kunci yang tidak ikut dipindah: status internal, jalur file lokal, dan sumber pembaruan
    /// (repo pembaruan tidak boleh diubah lewat file dari orang lain).
    private static let excluded: Set<String> = [
        "updateRepo", "updateAuto", "updateLast", "updateDismissed",
        "onboardingDone", "crashNotified", "bgImageName",
    ]

    private static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PY-Sys", isDirectory: true)
    }

    private static func keep(_ key: String) -> Bool {
        !excluded.contains(key) && !key.hasPrefix("NS") && !key.hasPrefix("com.apple") && !key.hasPrefix("Apple")
    }

    static func exportPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.propertyList]
        let day = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        panel.nameFieldStringValue = "PY-Sys-pengaturan-\(day).plist"
        panel.message = tr("Simpan pengaturan PY-Sys untuk dipindah ke Mac lain atau sebagai cadangan.",
                           "Save PY-Sys settings to move them to another Mac or keep as a backup.")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? appID) ?? [:]
        var file: [String: Any] = [
            "app": appID, "format": format,
            "version": AppInfo.version, "exported": Date(),
            "defaults": domain.filter { keep($0.key) },
        ]
        if let layouts = try? Data(contentsOf: supportDir.appendingPathComponent("window-layouts.json")) {
            file["windowLayouts"] = layouts
        }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: file, format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
            alert(tr("Pengaturan diekspor", "Settings exported"),
                  tr("Tersimpan di \(url.lastPathComponent). Buka file ini di PY-Sys Mac lain lewat Pengaturan → Impor pengaturan.",
                     "Saved as \(url.lastPathComponent). Open it in PY-Sys on another Mac via Settings → Import settings."))
        } catch {
            alert(tr("Gagal mengekspor", "Export failed"), error.localizedDescription)
        }
    }

    static func importPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = tr("Pilih file pengaturan PY-Sys (.plist) hasil ekspor.", "Choose an exported PY-Sys settings file (.plist).")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let data = try? Data(contentsOf: url),
              let file = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              file["app"] as? String == appID,
              let defaults = file["defaults"] as? [String: Any] else {
            alert(tr("File tidak dikenali", "Unrecognized file"),
                  tr("File ini bukan hasil ekspor pengaturan PY-Sys.", "This file is not a PY-Sys settings export."))
            return
        }
        if let f = file["format"] as? Int, f > format {
            alert(tr("Versi file terlalu baru", "File is too new"),
                  tr("Perbarui PY-Sys dulu, lalu impor lagi.", "Update PY-Sys first, then import again."))
            return
        }
        let from = file["version"] as? String ?? "?"
        guard confirm(tr("Impor pengaturan?", "Import settings?"),
                      tr("Pengaturan dari PY-Sys \(from) akan menggantikan pengaturan sekarang (tema, favorit, whitelist, profil fokus, jadwal, Klik Kanan+, dan lainnya). Sumber pembaruan tidak diubah. PY-Sys lalu dibuka ulang.",
                         "Settings from PY-Sys \(from) will replace your current ones (theme, favorites, whitelist, focus profiles, schedule, Right-Click+ and more). The update source is not changed. PY-Sys then relaunches."),
                      ok: tr("Impor & buka ulang", "Import & relaunch")) else { return }

        let d = UserDefaults.standard
        for (k, v) in defaults where keep(k) { d.set(v, forKey: k) }
        d.synchronize()
        if let layouts = file["windowLayouts"] as? Data {
            try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
            try? layouts.write(to: supportDir.appendingPathComponent("window-layouts.json"), options: .atomic)
        }
        relaunch()
    }

    static func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$1\"", "sh", path]
        try? p.run()
        NSApp.terminate(nil)
    }

    static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    static func confirm(_ title: String, _ text: String, ok: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: ok)
        a.addButton(withTitle: tr("Batal", "Cancel"))
        return a.runModal() == .alertFirstButtonReturn
    }
}

// MARK: - Laporan crash sederhana

final class CrashReports: ObservableObject {
    static let shared = CrashReports()
    private static let notifiedKey = "crashNotified"

    @Published private(set) var latest: (url: URL, date: Date)?
    @Published private(set) var count = 0
    @Published var message: String?

    private var dirs: [URL] {
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
        return [logs, logs.appendingPathComponent("Retired", isDirectory: true)]
    }

    /// Laporan crash PY-Sys yang dibuat macOS (≤ 30 hari terakhir), terbaru dulu.
    func scan() -> [(url: URL, date: Date)] {
        let fm = FileManager.default
        let limit = Date().addingTimeInterval(-30 * 86400)
        var out: [(URL, Date)] = []
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for u in items where u.lastPathComponent.hasPrefix("PYSys") && ["ips", "crash"].contains(u.pathExtension) {
                let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if d > limit { out.append((u, d)) }
            }
        }
        return out.sorted { $0.1 > $1.1 }.map { (url: $0.0, date: $0.1) }
    }

    func refresh() {
        let all = scan()
        latest = all.first
        count = all.count
    }

    /// Dipanggil saat app dibuka: beri tahu sekali bila ada crash baru sejak terakhir diberi tahu.
    func checkOnLaunch() {
        DispatchQueue.global(qos: .utility).async {
            let all = self.scan()
            DispatchQueue.main.async {
                self.latest = all.first
                self.count = all.count
                guard let newest = all.first?.date else { return }
                let seen = UserDefaults.standard.object(forKey: Self.notifiedKey) as? Date ?? .distantPast
                guard newest > seen else { return }
                UserDefaults.standard.set(newest, forKey: Self.notifiedKey)
                Notifier.post(title: tr("PY-Sys sempat berhenti tiba-tiba", "PY-Sys quit unexpectedly"),
                              body: tr("Laporan singkat tersedia di Pengaturan → Laporan masalah. Kirimkan bila ingin membantu perbaikan.",
                                       "A short report is in Settings → Problem report. Send it if you'd like to help fix it."))
            }
        }
    }

    // Ringkasan yang aman dibagikan: info sistem + inti laporan crash, jalur home disamarkan.
    func buildReport() -> String {
        var lines = [
            "PY-Sys \(AppInfo.version)",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Mac: \(SysInfo.model) · \(SysInfo.chip) · \(Self.arch)",
            "RAM: \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB",
            "",
        ]
        if let l = latest {
            lines.append("Crash: \(l.url.lastPathComponent) (\(l.date.formatted(date: .abbreviated, time: .shortened)))")
            lines.append(Self.summarize(l.url))
        } else {
            lines.append(tr("Tidak ada laporan crash dalam 30 hari terakhir.", "No crash reports in the last 30 days."))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return lines.joined(separator: "\n").replacingOccurrences(of: home, with: "~")
    }

    private static var arch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    /// Format .ips (macOS 12+): baris 1 = header JSON, sisanya = isi JSON.
    static func summarize(_ url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "(tidak bisa dibaca)" }
        guard let nl = text.firstIndex(of: "\n"),
              let body = try? JSONSerialization.jsonObject(with: Data(text[text.index(after: nl)...].utf8)) as? [String: Any] else {
            return text.split(separator: "\n", omittingEmptySubsequences: false).prefix(60).joined(separator: "\n")
        }
        var out: [String] = []
        if let ex = body["exception"] as? [String: Any] {
            out.append("Exception: \(ex["type"] as? String ?? "?") \(ex["signal"] as? String ?? "")")
            if let sub = ex["subtype"] as? String { out.append("Subtype: \(sub)") }
        }
        if let term = body["termination"] as? [String: Any], let ind = term["indicator"] as? String {
            out.append("Termination: \(ind)")
        }
        if let info = body["asi"] as? [String: Any] {
            for (_, v) in info { if let a = v as? [String] { out.append(contentsOf: a.prefix(3)) } }
        }
        let images = (body["usedImages"] as? [[String: Any]])?.map { $0["name"] as? String ?? "?" } ?? []
        if let threads = body["threads"] as? [[String: Any]] {
            let idx = body["faultingThread"] as? Int ?? 0
            if idx < threads.count, let frames = threads[idx]["frames"] as? [[String: Any]] {
                out.append("Thread \(idx) (crashed):")
                for (i, f) in frames.prefix(20).enumerated() {
                    let img = (f["imageIndex"] as? Int).flatMap { $0 < images.count ? images[$0] : nil } ?? "?"
                    let sym = f["symbol"] as? String ?? "0x\(String(f["imageOffset"] as? Int ?? 0, radix: 16))"
                    out.append("  \(i)  \(img)  \(sym)")
                }
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: Tindakan

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(buildReport(), forType: .string)
        flash(tr("Laporan disalin.", "Report copied."))
    }

    func saveToDesktop() {
        let desk = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let url = desk.appendingPathComponent("PY-Sys-laporan-\(Int(Date().timeIntervalSince1970)).txt")
        do {
            try buildReport().write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            flash(tr("Tersimpan di Desktop.", "Saved to Desktop."))
        } catch {
            flash(error.localizedDescription)
        }
    }

    /// Membuka halaman issue GitHub yang sudah terisi; pengguna memeriksa isinya sebelum mengirim.
    func openIssue() {
        var body = buildReport()
        if body.count > 5500 { body = String(body.prefix(5500)) + "\n…" }
        let text = tr("Apa yang sedang dilakukan saat PY-Sys berhenti?", "What were you doing when PY-Sys quit?") + "\n\n\n```\n\(body)\n```"
        var c = URLComponents(string: "https://github.com/\(Updater.officialRepo)/issues/new")!
        c.queryItems = [URLQueryItem(name: "title", value: "Crash: PY-Sys \(AppInfo.version)"),
                        URLQueryItem(name: "body", value: text)]
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        if let u = c.url { NSWorkspace.shared.open(u) }
    }

    private func flash(_ s: String) {
        message = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if self.message == s { self.message = nil } }
    }
}

// MARK: - Bagian di Pengaturan

struct MaintenanceSection: View {
    @ObservedObject private var crash = CrashReports.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Cadangan pengaturan", "Settings backup")).font(.subheadline.bold())
            Text(tr("Pindahkan tema, favorit, whitelist, profil fokus, jadwal, dan Klik Kanan+ ke Mac lain.",
                    "Move theme, favorites, whitelist, focus profiles, schedule and Right-Click+ to another Mac."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button { SettingsTransfer.exportPanel() } label: { Label(tr("Ekspor…", "Export…"), systemImage: "square.and.arrow.up") }
                Button { SettingsTransfer.importPanel() } label: { Label(tr("Impor…", "Import…"), systemImage: "square.and.arrow.down") }
            }
            .controlSize(.small)

            Divider()
            Text(tr("Laporan masalah", "Problem report")).font(.subheadline.bold())
            if let l = crash.latest {
                Text(tr("Crash terakhir: \(l.date.formatted(date: .abbreviated, time: .shortened)) · \(crash.count) dalam 30 hari",
                        "Last crash: \(l.date.formatted(date: .abbreviated, time: .shortened)) · \(crash.count) in 30 days"))
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Text(tr("Tidak ada crash dalam 30 hari terakhir.", "No crashes in the last 30 days."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(tr("Laporan berisi versi, model Mac, dan inti crash; nama pengguna disamarkan. Tidak ada yang dikirim otomatis.",
                    "The report holds the version, Mac model and crash details; your user name is masked. Nothing is sent automatically."))
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Button(tr("Salin", "Copy")) { crash.copy() }
                Button(tr("Simpan ke Desktop", "Save to Desktop")) { crash.saveToDesktop() }
                Button(tr("Laporkan di GitHub", "Report on GitHub")) { crash.openIssue() }
            }
            .controlSize(.small)
            if let m = crash.message { Text(m).font(.caption).foregroundStyle(.secondary) }
        }
        .onAppear { crash.refresh() }
    }
}
