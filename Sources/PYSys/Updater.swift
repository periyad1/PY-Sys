import AppKit
import SwiftUI
import Security

// MARK: - Pembaruan otomatis dari GitHub Releases

final class Updater: ObservableObject {
    static let shared = Updater()

    @Published var repo: String { didSet { UserDefaults.standard.set(repo, forKey: "updateRepo") } }
    @Published var autoCheck: Bool { didSet { UserDefaults.standard.set(autoCheck, forKey: "updateAuto") } }
    @Published private(set) var status: String?
    @Published private(set) var checking = false

    // Versi baru yang ditemukan
    @Published private(set) var latest: String?
    @Published private(set) var notes: String = ""
    @Published private(set) var dmgURL: URL?
    @Published private(set) var pageURL: URL?
    @Published private(set) var installing = false
    @Published private(set) var installStep: String?
    @Published private(set) var dismissed: String? { didSet { UserDefaults.standard.set(dismissed, forKey: "updateDismissed") } }

    private var timer: Timer?

    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Ada versi baru (dipakai untuk tanda di menu bar).
    var available: Bool { latest.map { Self.newer($0, than: Self.current) } ?? false }
    /// Banner di panel: ada versi baru dan belum ditunda untuk versi itu.
    var showBanner: Bool { available && dismissed != latest }

    init() {
        repo = UserDefaults.standard.string(forKey: "updateRepo") ?? ""
        autoCheck = UserDefaults.standard.object(forKey: "updateAuto") as? Bool ?? true
        dismissed = UserDefaults.standard.string(forKey: "updateDismissed")
    }

    /// "1.10" > "1.9", "1.5.2" > "1.5.1"
    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let y = b.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    /// Cek saat PY-Sys dibuka, lalu dicek ulang tiap 6 jam; ke GitHub paling sering sekali per 24 jam.
    func startAuto() {
        cleanupAfterUpdate()
        maybeCheck()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.maybeCheck() }
        t.tolerance = 600
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func maybeCheck() {
        guard autoCheck, !repo.isEmpty else { return }
        let last = UserDefaults.standard.object(forKey: "updateLast") as? Date ?? .distantPast
        if Date().timeIntervalSince(last) > 86_000 { check(silent: true) }
    }

    func check(silent: Bool = false) {
        let r = repo.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "https://github.com/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard r.split(separator: "/").count == 2, let url = URL(string: "https://api.github.com/repos/\(r)/releases/latest") else {
            status = tr("Isi repo GitHub dengan format pemilik/nama, mis. periyadi/PY-Sys.", "Enter the GitHub repo as owner/name, e.g. periyadi/PY-Sys.")
            return
        }
        checking = true
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: req) { data, _, err in
            var msg: String
            var v: String?, body = "", dmg: URL?, page: URL?
            if let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let tag = j["tag_name"] as? String {
                v = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                body = (j["body"] as? String) ?? ""
                page = URL(string: j["html_url"] as? String ?? "")
                let assets = j["assets"] as? [[String: Any]] ?? []
                if let d = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true })?["browser_download_url"] as? String {
                    dmg = URL(string: d)
                }
                UserDefaults.standard.set(Date(), forKey: "updateLast")
                msg = Self.newer(v!, than: Self.current)
                    ? tr("Versi \(v!) tersedia (Anda memakai \(Self.current)).", "Version \(v!) is available (you have \(Self.current)).")
                    : tr("PY-Sys sudah versi terbaru (\(Self.current)).", "PY-Sys is up to date (\(Self.current)).")
            } else {
                msg = tr("Gagal memeriksa: \(err?.localizedDescription ?? "repo atau rilis tidak ditemukan (repo harus public)").",
                         "Check failed: \(err?.localizedDescription ?? "repo or release not found (the repo must be public)").")
            }
            DispatchQueue.main.async {
                self.checking = false
                self.status = msg
                guard let v else { return }
                let isNew = Self.newer(v, than: Self.current)
                let wasKnown = self.latest == v
                self.latest = v
                self.notes = body
                self.dmgURL = dmg
                self.pageURL = page
                if isNew && silent && !wasKnown && self.dismissed != v {
                    Notifier.post(title: "PY-Sys \(v)", body: tr("Versi baru tersedia. Buka PY-Sys lalu klik Perbarui sekarang.",
                                                                 "A new version is available. Open PY-Sys and click Update now."))
                }
            }
        }.resume()
    }

    func later() { dismissed = latest }

    // MARK: Pasang otomatis

    private var cacheDir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PY-Sys-Update", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func cleanupAfterUpdate() {
        // Sisa unduhan dari pembaruan sebelumnya
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PY-Sys-Update")
        if FileManager.default.fileExists(atPath: d.path) { try? FileManager.default.removeItem(at: d) }
    }

    private func fail(_ s: String) {
        installing = false
        installStep = nil
        status = s
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        guard (try? p.run()) != nil else { return (-1, "") }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        return (p.terminationStatus, out)
    }

    // MARK: Verifikasi tanda tangan

    /// Persyaratan tanda tangan aplikasi yang sedang berjalan ("cap" pembuatnya).
    private static func requirement(of url: URL) -> (req: SecRequirement, text: String)? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var req: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, [], &req) == errSecSuccess, let req else { return nil }
        var text: CFString?
        SecRequirementCopyString(req, [], &text)
        return (req, (text as String?) ?? "")
    }

    /// Versi baru hanya diterima bila ditandatangani sertifikat yang sama dengan versi yang terpasang.
    /// nil = lolos; selain itu berisi alasan penolakan.
    static func verifySameSigner(_ newApp: URL) -> String? {
        guard let mine = requirement(of: Bundle.main.bundleURL) else {
            return tr("Tanda tangan PY-Sys yang terpasang tidak terbaca.", "The installed PY-Sys signature can't be read.")
        }
        // Build ad-hoc (tanpa sertifikat) tidak punya "cap" tetap: tidak bisa dibandingkan.
        guard mine.text.contains("certificate") else {
            return tr("PY-Sys ini dibuild tanpa sertifikat, jadi pembaruan tidak bisa diverifikasi. Pasang manual dari DMG.",
                      "This PY-Sys was built without a certificate, so updates can't be verified. Install manually from the DMG.")
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(newApp as CFURL, [], &code) == errSecSuccess, let code else {
            return tr("Versi baru tidak bertanda tangan.", "The new version isn't signed.")
        }
        let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures) | UInt32(kSecCSCheckNestedCode) | UInt32(kSecCSStrictValidate))
        let rc = SecStaticCodeCheckValidity(code, flags, mine.req)
        return rc == errSecSuccess ? nil
            : tr("DITOLAK: versi baru tidak ditandatangani oleh pembuat PY-Sys yang sama (kode \(rc)). Bisa jadi rilis palsu; jangan dipasang.",
                 "REJECTED: the new version isn't signed by the same PY-Sys publisher (code \(rc)). It may be a fake release; don't install it.")
    }

    func install() {
        guard !installing else { return }
        guard let dmg = dmgURL else {
            if let p = pageURL { NSWorkspace.shared.open(p) }
            return
        }
        let appPath = Bundle.main.bundlePath
        let parent = (appPath as NSString).deletingLastPathComponent
        guard FileManager.default.isWritableFile(atPath: parent), FileManager.default.isWritableFile(atPath: appPath) else {
            // Tidak bisa mengganti sendiri (mis. app milik admin lain): unduh lewat browser saja
            status = tr("PY-Sys tidak bisa mengganti dirinya di \(parent). DMG dibuka di browser; pasang manual.",
                        "PY-Sys can't replace itself in \(parent). The DMG opens in your browser; install it manually.")
            NSWorkspace.shared.open(dmg)
            return
        }
        installing = true
        installStep = tr("Mengunduh…", "Downloading…")
        let dir = cacheDir
        URLSession.shared.downloadTask(with: dmg) { tmp, _, err in
            guard let tmp else {
                DispatchQueue.main.async { self.fail(tr("Unduhan gagal: \(err?.localizedDescription ?? "?")", "Download failed: \(err?.localizedDescription ?? "?")")) }
                return
            }
            let fm = FileManager.default
            let dmgFile = dir.appendingPathComponent("update.dmg")
            let mount = dir.appendingPathComponent("mnt")
            let newApp = dir.appendingPathComponent("PY-Sys.app")
            try? fm.removeItem(at: dmgFile)
            try? fm.removeItem(at: newApp)
            try? fm.createDirectory(at: mount, withIntermediateDirectories: true)
            do { try fm.moveItem(at: tmp, to: dmgFile) } catch {
                DispatchQueue.main.async { self.fail(error.localizedDescription) }
                return
            }
            DispatchQueue.main.async { self.installStep = tr("Memasang…", "Installing…") }

            let (rc, _) = Self.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmgFile.path])
            guard rc == 0 else {
                DispatchQueue.main.async { self.fail(tr("DMG tidak bisa dibuka.", "Couldn't open the DMG.")) }
                return
            }
            let found = (try? fm.contentsOfDirectory(atPath: mount.path))?.first { $0.hasSuffix(".app") }
            if let f = found { Self.run("/usr/bin/ditto", [mount.appendingPathComponent(f).path, newApp.path]) }
            Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"])

            // Periksa: aplikasi utuh, bundle ID sama, versinya memang lebih baru
            guard found != nil, let b = Bundle(url: newApp), b.bundleIdentifier == Bundle.main.bundleIdentifier,
                  let nv = b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, Self.newer(nv, than: Self.current) else {
                DispatchQueue.main.async { self.fail(tr("Isi DMG tidak valid; pembaruan dibatalkan.", "The DMG contents aren't valid; update cancelled.")) }
                return
            }
            if let why = Self.verifySameSigner(newApp) {
                try? fm.removeItem(at: newApp)
                try? fm.removeItem(at: dmgFile)
                DispatchQueue.main.async {
                    self.fail(why)
                    Notifier.post(title: tr("Pembaruan PY-Sys ditolak", "PY-Sys update rejected"), body: why)
                }
                return
            }
            Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

            // Skrip kecil yang menunggu PY-Sys keluar, menukar aplikasinya, lalu membuka versi baru.
            // Bila penukaran gagal, versi lama dikembalikan.
            let backup = dir.appendingPathComponent("PY-Sys-lama.app").path
            let script = """
            #!/bin/bash
            for i in $(seq 1 100); do kill -0 \(getpid()) 2>/dev/null || break; sleep 0.2; done
            rm -rf "\(backup)"
            if mv "\(appPath)" "\(backup)"; then
              if /usr/bin/ditto "\(newApp.path)" "\(appPath)"; then
                rm -rf "\(backup)"
              else
                rm -rf "\(appPath)"; mv "\(backup)" "\(appPath)"
              fi
            fi
            /System/Library/CoreServices/pbs -update 2>/dev/null
            open "\(appPath)"
            """
            let scriptURL = dir.appendingPathComponent("swap.sh")
            do { try script.write(to: scriptURL, atomically: true, encoding: .utf8) } catch {
                DispatchQueue.main.async { self.fail(error.localizedDescription) }
                return
            }
            DispatchQueue.main.async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = [scriptURL.path]
                do { try p.run() } catch { self.fail(error.localizedDescription); return }
                self.installStep = tr("Memulai ulang…", "Restarting…")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
            }
        }.resume()
    }
}

// MARK: - Banner di panel

struct UpdateBanner: View {
    @ObservedObject private var up = Updater.shared

    var body: some View {
        if up.showBanner || up.installing, let v = up.latest {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent).font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tr("PY-Sys \(v) tersedia", "PY-Sys \(v) is available")).font(.callout.bold())
                        Text(tr("Anda memakai \(Updater.current)", "You have \(Updater.current)")).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if up.installing {
                        ProgressView().controlSize(.small)
                        Text(up.installStep ?? "").font(.caption)
                    } else {
                        Button(tr("Nanti", "Later")) { up.later() }.controlSize(.small)
                        Button(tr("Perbarui sekarang", "Update now")) { up.install() }
                            .controlSize(.small).buttonStyle(.borderedProminent)
                    }
                }
                let n = up.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                if !n.isEmpty {
                    Text(String(n.prefix(220)) + (n.count > 220 ? "…" : ""))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.12)))
        }
    }
}

struct UpdateSection: View {
    @ObservedObject private var up = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Pembaruan", "Updates")).font(.subheadline.bold())
            HStack {
                TextField(tr("Repo GitHub (pemilik/nama)", "GitHub repo (owner/name)"), text: $up.repo)
                    .textFieldStyle(.roundedBorder)
                Button(up.checking ? "…" : tr("Cek sekarang", "Check now")) { up.check() }
                    .controlSize(.small)
                    .disabled(up.checking || up.repo.isEmpty)
            }
            Toggle(tr("Periksa otomatis setiap hari", "Check automatically every day"), isOn: $up.autoCheck).font(.caption)
            if let s = up.status {
                Text(s).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if up.available && !up.installing {
                Button(tr("Perbarui ke \(up.latest ?? "")", "Update to \(up.latest ?? "")")) { up.install() }.controlSize(.small)
            }
            Text(tr("Versi \(Updater.current). PY-Sys membaca rilis terbaru dari GitHub Releases repo ini (harus public). Pembaruan hanya dipasang bila ditandatangani pembuat yang sama dengan versi ini.",
                    "Version \(Updater.current). PY-Sys reads the latest release from this repo's GitHub Releases (must be public). Updates are installed only if signed by the same publisher as this version."))
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
