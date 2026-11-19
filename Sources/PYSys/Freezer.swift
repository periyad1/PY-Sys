import Foundation
import AppKit
import Darwin

/// Cryo-Sleep: membekukan (SIGSTOP) aplikasi yang tidak dipakai dan tidak terlihat,
/// supaya halamannya bisa dikompres/di-swap tanpa terus "dibangunkan" lagi.
/// Dicairkan (SIGCONT) otomatis saat aplikasi diaktifkan atau jendelanya muncul di layar.
final class Freezer: ObservableObject {
    struct Frozen: Codable, Identifiable {
        var id: Int32 { mainPID }
        let mainPID: Int32
        let name: String
        let bundleID: String
        let pids: [Int32]
        let since: Date
        let footprint: UInt64
        let manual: Bool
    }

    @Published private(set) var frozen: [Frozen] = []
    var frozenBytes: UInt64 { frozen.reduce(0) { $0 + $1.footprint } }

    private let settings: Settings
    private var lastActive: [pid_t: Date] = [:]
    private var observers: [NSObjectProtocol] = []
    private var signalSources: [DispatchSourceSignal] = []
    private var pollTimer: Timer?

    /// Tidak boleh dibekukan, bahkan secara manual.
    private static let protected: Set<String> = [
        "com.apple.finder", "com.apple.loginwindow", "com.apple.dock", "com.apple.systemuiserver",
    ]

    private let stateURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PY-Sys", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("frozen.json")
    }()

    init(settings: Settings) {
        self.settings = settings
        recoverFromCrash()

        let now = Date()
        for app in NSWorkspace.shared.runningApplications { lastActive[app.processIdentifier] = now }

        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                        object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self.lastActive[app.processIdentifier] = Date()
            self.thaw(app.processIdentifier)
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification,
                                        object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.lastActive[app.processIdentifier] = Date()
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                        object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.lastActive[app.processIdentifier] = Date()
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                        object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self.lastActive[app.processIdentifier] = nil
            if self.isFrozen(app.processIdentifier) { self.thaw(app.processIdentifier) }
        })
        // Logout/shutdown: app yang beku tidak bisa menjawab "quit" dan akan membatalkan logout.
        observers.append(nc.addObserver(forName: NSWorkspace.willPowerOffNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.thawAll()
        })

        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t

        installSignalHandlers()
    }

    func isFrozen(_ pid: pid_t) -> Bool { frozen.contains { $0.mainPID == pid } }

    func canAutoFreeze(_ bundleID: String) -> Bool {
        !Self.protected.contains(bundleID) && !settings.whitelist.contains(bundleID)
            && bundleID != Bundle.main.bundleIdentifier
    }

    // MARK: - Otomatis

    func autoFreeze(groups: [AppGroup]) {
        guard settings.cryoEnabled else { return }
        let now = Date()
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let visible = WindowInfo.visiblePIDs()
        let idleLimit = Double(settings.idleMinutes) * 60
        let minBytes: UInt64 = 100 * 1_048_576   // app kecil tidak sebanding risikonya

        for g in groups where g.isApp {
            guard let bid = g.bundleID, canAutoFreeze(bid),
                  g.mainPID != front, g.mainPID != getpid(), !isFrozen(g.mainPID) else { continue }
            // Terlihat di salah satu monitor = dianggap sedang dipakai → reset timer idle.
            if g.pids.contains(where: visible.contains) { lastActive[g.mainPID] = now; continue }
            guard let last = lastActive[g.mainPID] else { lastActive[g.mainPID] = now; continue }
            guard now.timeIntervalSince(last) >= idleLimit,
                  g.cpu < settings.cpuGuard,           // masih kerja (download, audio, render) → lewati
                  g.footprint >= minBytes else { continue }
            freeze(g, manual: false)
        }
    }

    /// Bebaskan RAM dengan rincian: bekukan yang aman, catat yang dilewati beserta alasannya.
    /// aggressive = app yang jendelanya terlihat ikut disembunyikan lalu dibekukan.
    func freeUp(groups: [AppGroup], aggressive: Bool) -> (frozen: [FreeItem], skipped: [FreeItem]) {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let visible = WindowInfo.visiblePIDs()
        let multi = NSScreen.screens.count > 1
        let now = Date()
        var frozenList: [FreeItem] = []
        var skipped: [FreeItem] = []
        for g in groups where g.isApp && g.footprint >= 50 * 1_048_576 {
            guard let bid = g.bundleID, bid != Bundle.main.bundleIdentifier, g.mainPID != getpid(), !isFrozen(g.mainPID) else { continue }
            func skip(_ why: String, visible v: Bool = false) {
                skipped.append(FreeItem(id: g.mainPID, name: g.name, icon: g.icon, bytes: g.footprint, note: why, visible: v))
            }
            if Self.protected.contains(bid) { skip(tr("app sistem", "system app")); continue }
            if settings.whitelist.contains(bid) { skip(tr("whitelist, tidak pernah dibekukan", "whitelist, never frozen")); continue }
            if g.mainPID == front { skip(tr("app yang sedang aktif", "the active app")); continue }
            if g.cpu >= settings.cpuGuard { skip(tr("sedang bekerja (CPU \(Int(g.cpu))%)", "busy (CPU \(Int(g.cpu))%)")); continue }
            if g.pids.contains(where: visible.contains) {
                if aggressive {
                    manualFreeze(g)
                    frozenList.append(FreeItem(id: g.mainPID, name: g.name, icon: g.icon, bytes: g.footprint,
                                               note: tr("disembunyikan lalu dibekukan", "hidden, then frozen"), visible: true))
                } else {
                    let n = WindowInfo.screenNumber(of: g.pids)
                    skip(multi && n != nil ? tr("jendela terlihat di monitor \(n!)", "window visible on display \(n!)")
                                           : tr("jendelanya terlihat di layar", "its window is on screen"), visible: true)
                }
                continue
            }
            freeze(g, manual: false)
            guard isFrozen(g.mainPID) else { continue }
            let idle = lastActive[g.mainPID].map { Int(now.timeIntervalSince($0) / 60) }
            let note: String
            if let m = idle, m >= 60 { note = tr("tidak dipakai \(m / 60) jam", "unused for \(m / 60) h") }
            else if let m = idle, m >= 1 { note = tr("tidak dipakai \(m) menit", "unused for \(m) min") }
            else { note = tr("tidak terlihat dan tidak aktif", "hidden and idle") }
            frozenList.append(FreeItem(id: g.mainPID, name: g.name, icon: g.icon, bytes: g.footprint, note: note, visible: false))
        }
        return (frozenList.sorted { $0.bytes > $1.bytes }, skipped.sorted { $0.bytes > $1.bytes })
    }

    /// Untuk tombol "Bebaskan RAM": abaikan batas waktu idle, tetap hormati whitelist,
    /// jendela yang terlihat, app aktif dan penjaga CPU.
    @discardableResult
    func freezeIdleNow(groups: [AppGroup]) -> (count: Int, bytes: UInt64) {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let visible = WindowInfo.visiblePIDs()
        var count = 0
        var bytes: UInt64 = 0
        for g in groups where g.isApp {
            guard let bid = g.bundleID, canAutoFreeze(bid), g.mainPID != front, g.mainPID != getpid(),
                  !isFrozen(g.mainPID), !g.pids.contains(where: visible.contains),
                  g.cpu < settings.cpuGuard, g.footprint >= 50 * 1_048_576 else { continue }
            freeze(g, manual: false)
            if isFrozen(g.mainPID) { count += 1; bytes += g.footprint }
        }
        return (count, bytes)
    }

    private func poll() {
        guard !frozen.isEmpty else { return }
        if let f = NSWorkspace.shared.frontmostApplication?.processIdentifier, isFrozen(f) { thaw(f) }
        let visible = WindowInfo.visiblePIDs()
        for f in frozen where !f.manual && f.pids.contains(where: visible.contains) {
            thaw(f.mainPID)
        }
    }

    // MARK: - Manual

    /// Sembunyikan dulu (supaya tidak ada jendela "beku" di layar), lalu bekukan.
    func manualFreeze(_ g: AppGroup) {
        guard g.isApp else { return }
        NSRunningApplication(processIdentifier: g.mainPID)?.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.freeze(g, manual: true)
        }
    }

    private func freeze(_ g: AppGroup, manual: Bool) {
        guard let bid = g.bundleID, !Self.protected.contains(bid),
              bid != Bundle.main.bundleIdentifier, g.mainPID != getpid(),
              !isFrozen(g.mainPID) else { return }
        guard kill(g.mainPID, SIGSTOP) == 0 else { return }
        for p in g.pids where p != g.mainPID { kill(p, SIGSTOP) }
        frozen.append(Frozen(mainPID: g.mainPID, name: g.name, bundleID: bid, pids: g.pids,
                             since: Date(), footprint: g.footprint, manual: manual))
        save()
    }

    func thaw(_ pid: pid_t) {
        guard let i = frozen.firstIndex(where: { $0.mainPID == pid }) else { return }
        let f = frozen.remove(at: i)
        resume(f)
        lastActive[f.mainPID] = Date()
        save()
    }

    func thawAll() {
        guard !frozen.isEmpty else { return }
        frozen.forEach(resume)
        let now = Date()
        for f in frozen { lastActive[f.mainPID] = now }
        frozen.removeAll()
        save()
    }

    private func resume(_ f: Frozen) {
        kill(f.mainPID, SIGCONT)
        for p in f.pids where p != f.mainPID { kill(p, SIGCONT) }
    }

    // MARK: - Pengaman

    private func save() {
        if frozen.isEmpty { try? FileManager.default.removeItem(at: stateURL); return }
        if let data = try? JSONEncoder().encode(frozen) { try? data.write(to: stateURL, options: .atomic) }
    }

    /// Kalau PY-Sys pernah crash/di-force-quit saat ada app beku, cairkan semuanya saat start.
    private func recoverFromCrash() {
        guard let data = try? Data(contentsOf: stateURL),
              let stale = try? JSONDecoder().decode([Frozen].self, from: data) else { return }
        stale.forEach(resume)
        try? FileManager.default.removeItem(at: stateURL)
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in
                self?.thawAll()
                AgentMonitor.shared.resumeAll()
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }
    }
}


struct FreeItem: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage?
    let bytes: UInt64
    let note: String
    let visible: Bool
}

struct FreeRAMReport {
    let date: Date
    let beforePct: Double
    let beforePressure: PressureLevel
    var frozen: [FreeItem]
    var skipped: [FreeItem]
    var afterPct: Double?
    var afterPressure: PressureLevel?
    var frozenBytes: UInt64 { frozen.reduce(0) { $0 + $1.bytes } }
}
