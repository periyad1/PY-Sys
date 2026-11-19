import Foundation
import AppKit
import UserNotifications

struct HistoryPoint {
    let date: Date
    let usedPct: Double
    let swapOutMBps: Double
    var pressurePct: Double = 0
    var wiredGB: Double = 0
    var activeGB: Double = 0
    var compressedGB: Double = 0
    var swapGB: Double = 0
    var pageInMBps: Double = 0
    var pageOutMBps: Double = 0
}

enum SSDMessage {
    case notInstalled, runFailed(String), noData
    var text: String {
        switch self {
        case .notInstalled:
            return tr("Untuk melihat total tulis & keausan SSD seumur hidup, install: brew install smartmontools",
                      "To see lifetime SSD writes & wear, install: brew install smartmontools")
        case .runFailed(let e):
            return tr("Gagal menjalankan smartctl: \(e)", "Failed to run smartctl: \(e)")
        case .noData:
            return tr("smartctl tidak mengembalikan data SMART untuk disk0.", "smartctl returned no SMART data for disk0.")
        }
    }
}

struct SSDHealth {
    var written: String?
    var percentUsed: Int?
    var availableSpare: Int?
    var powerOnHours: Int?
}

final class AetherCore: ObservableObject {
    static let shared = AetherCore()

    let settings: Settings
    let freezer: Freezer

    @Published var mem = MemorySnapshot()
    @Published var history: [HistoryPoint] = []
    @Published var swapOutRate = 0.0
    @Published var pageInRate = 0.0
    @Published var pageOutRate = 0.0
    @Published var diskWriteRate = 0.0
    @Published var diskWrittenSinceBoot: UInt64 = 0
    @Published var diskReadRate = 0.0
    @Published var volume: (name: String, total: Int64, free: Int64)?
    @Published var diskProcs: [DiskProc] = []
    @Published var interfaces: [NetInterface] = []
    @Published var netHistory: [NetPoint] = []
    @Published var netUp = 0.0
    @Published var netDown = 0.0
    @Published var netProcs: [NetProc] = []
    @Published var publicIP: PublicIP?
    @Published var sensors = SensorSnapshot()
    @Published var groups: [AppGroup] = []
    @Published var ssd: SSDHealth?
    @Published var ssdMessage: SSDMessage?
    @Published var cpu = CPUSnapshot()
    @Published var cpuHistory: [CPUPoint] = []
    @Published var gpuHistory: [GPUPoint] = []
    @Published var freeUpMessage: String?
    @Published var loadHistory: [LoadPoint] = []
    @Published var topCPU: [TopProc] = []

    private var lastMemTime: Date?
    private var lastSwapouts: UInt64 = 0
    private var lastPageins: UInt64 = 0
    private var lastPageouts: UInt64 = 0
    private var lastDisk: UInt64 = 0
    private var lastDiskRead: UInt64 = 0
    private var overviewVisible = false
    private var prevIO: [pid_t: (name: String, read: UInt64, written: UInt64)] = [:]
    private var prevIOTime: Date?
    private var ioInFlight = false
    private var volumeTick = 0
    private var prevNet: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var prevNetTime: Date?
    private var networkVisible = false
    private var sensorsVisible = false
    private var netProcInFlight = false
    private var publicIPDate: Date?
    private var prevCPU: [pid_t: UInt64] = [:]
    private var prevScan: Date?
    private var lastSamples: [pid_t: ProcSample] = [:]
    private var lastCPUMap: [pid_t: Double] = [:]
    private var lastAlert: [String: Date] = [:]
    private var timers: [Timer] = []
    private var prevCores: [CPUTicks] = []
    private var cpuTabVisible = false
    private var topInFlight = false

    private init() {
        settings = Settings()
        freezer = Freezer(settings: settings)
        fastTick()
        slowTick()
        refreshSSD()
        reschedule()
        schedule(every: 1800) { [weak self] in self?.refreshSSD() }
    }

    // MARK: Mode hemat: cepat saat panel terbuka, lambat saat tertutup

    private(set) var panelOpen = false
    private var fastTimer: Timer?
    private var slowTimer: Timer?
    private var lastTempRead: Date?

    private func makeTimer(_ interval: TimeInterval, _ block: @escaping () -> Void) -> Timer {
        let t = Timer(timeInterval: interval, repeats: true) { _ in block() }
        t.tolerance = interval * 0.25
        RunLoop.main.add(t, forMode: .common)
        return t
    }

    private func reschedule() {
        fastTimer?.invalidate()
        slowTimer?.invalidate()
        fastTimer = makeTimer(panelOpen ? 3 : 5) { [weak self] in self?.fastTick() }
        slowTimer = makeTimer(panelOpen ? 15 : 30) { [weak self] in self?.slowTick() }
    }

    /// Dipanggil saat panel menu bar dibuka/ditutup.
    func setPanelOpen(_ open: Bool) {
        guard open != panelOpen else { return }
        panelOpen = open
        reschedule()
        if open { fastTick() }
    }

    private func schedule(every interval: TimeInterval, _ block: @escaping () -> Void) {
        let t = Timer(timeInterval: interval, repeats: true) { _ in block() }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timers.append(t)
    }

    // Tiap 3 detik: statistik memori, swap, tulis SSD.
    func fastTick() {
        let s = SystemStats.snapshot()
        let io = SystemStats.internalDiskIO()
        let disk = io.written
        if let last = lastMemTime {
            let dt = s.date.timeIntervalSince(last)
            if dt > 0 {
                let dSwap = s.swapouts >= lastSwapouts ? s.swapouts - lastSwapouts : 0
                swapOutRate = Double(dSwap * SystemStats.pageSize) / dt
                let dDisk = disk >= lastDisk ? disk - lastDisk : 0
                diskWriteRate = Double(dDisk) / dt
                let dRead = io.read >= lastDiskRead ? io.read - lastDiskRead : 0
                diskReadRate = Double(dRead) / dt
                let dIn = s.pageins >= lastPageins ? s.pageins - lastPageins : 0
                let dOut = s.pageouts >= lastPageouts ? s.pageouts - lastPageouts : 0
                pageInRate = Double(dIn * SystemStats.pageSize) / dt
                pageOutRate = Double(dOut * SystemStats.pageSize) / dt
            }
        }
        lastMemTime = s.date
        lastSwapouts = s.swapouts
        lastPageins = s.pageins
        lastPageouts = s.pageouts
        lastDisk = disk
        lastDiskRead = io.read
        if volumeTick % 10 == 0 { volume = SystemStats.volumeSpace() }   // tiap ±30 detik
        volumeTick += 1
        if overviewVisible { refreshDiskProcs() }
        netTick(now: s.date)
        if networkVisible { refreshNetProcs() }
        if sensorsVisible { sensors = SensorReader.snapshot() }
        mem = s
        diskWrittenSinceBoot = disk
        cpuTick(now: s.date)

        let gb = 1_073_741_824.0
        history.append(HistoryPoint(date: s.date, usedPct: s.usedFraction * 100,
                                    swapOutMBps: swapOutRate / 1_000_000,
                                    pressurePct: s.pressureFraction * 100,
                                    wiredGB: Double(s.wired) / gb,
                                    activeGB: Double(s.active) / gb,
                                    compressedGB: Double(s.compressed) / gb,
                                    swapGB: Double(s.swapUsed) / gb,
                                    pageInMBps: pageInRate / 1_000_000,
                                    pageOutMBps: pageOutRate / 1_000_000))
        if history.count > 200 { history.removeFirst(history.count - 200) }   // ±10 menit

        if s.pressure == .critical {
            maybeAlert(key: "pressure", every: 1800,
                       title: tr("Tekanan memori KRITIS", "Memory pressure CRITICAL"),
                       body: tr("Pemakai terbesar: \(topSummary()). Tutup sesuatu atau bekukan app yang tidak dipakai.",
                                "Top users: \(topSummary()). Close something or freeze unused apps."))
        }
    }

    // Tiap 15 detik: daftar proses, CPU, Cryo-Sleep, peringatan app bengkak.
    func slowTick() {
        let now = Date()
        BatteryHistory.shared.recordIfNeeded()
        let samples = ProcessScanner.scan()
        let elapsed = prevScan.map { now.timeIntervalSince($0) } ?? 0
        var cpu: [pid_t: Double] = [:]
        if elapsed > 0 {
            for (pid, s) in samples {
                if let p = prevCPU[pid], s.cpuNanos >= p {
                    cpu[pid] = Double(s.cpuNanos - p) / (elapsed * 1e9) * 100
                }
            }
        }
        prevCPU = samples.mapValues { $0.cpuNanos }
        prevScan = now

        let g = AppGrouper.group(samples: samples, cpu: cpu)
        groups = g
        lastSamples = samples
        lastCPUMap = cpu
        AgentMonitor.shared.update(samples: samples, cpu: cpu, threshold: settings.agentCPU, minutes: settings.agentMinutes,
                                   interval: elapsed > 0 ? elapsed : 15)
        BrowserMonitor.shared.update(groups: g, samples: samples, cpu: cpu)
        if elapsed > 0 { freezer.autoFreeze(groups: g) }   // butuh data CPU dulu

        let limit = UInt64(settings.bloatGB * 1_073_741_824)
        for grp in g where grp.footprint > limit && !freezer.isFrozen(grp.mainPID) {
            maybeAlert(key: "bloat:\(grp.name)", every: 3600,
                       title: tr("\(grp.name) membengkak", "\(grp.name) is bloating"),
                       body: tr("Memakai \(Fmt.bytes(grp.footprint)). Tutup tab/jendela yang tidak perlu atau restart aplikasinya.",
                                "Using \(Fmt.bytes(grp.footprint)). Close unneeded tabs/windows or restart the app."))
        }
    }

    private func cpuTick(now: Date) {
        let cores = CPUStats.perCoreTicks()
        var snap = cpu
        if prevCores.count == cores.count, !cores.isEmpty {
            var tu = 0.0, ts = 0.0, ti = 0.0
            var perCore: [Double] = []
            for (a, b) in zip(prevCores, cores) {
                let u = Double(b.user &- a.user) + Double(b.nice &- a.nice)
                let sy = Double(b.system &- a.system)
                let i = Double(b.idle &- a.idle)
                perCore.append((u + sy) / max(u + sy + i, 1))
                tu += u; ts += sy; ti += i
            }
            let total = max(tu + ts + ti, 1)
            snap.user = tu / total
            snap.system = ts / total
            snap.idle = ti / total
            snap.cores = perCore
            cpuHistory.append(CPUPoint(date: now, user: snap.user, system: snap.system))
            if cpuHistory.count > 200 { cpuHistory.removeFirst(cpuHistory.count - 200) }
        }
        prevCores = cores

        snap.load = CPUStats.loadAverage()
        loadHistory.append(LoadPoint(date: now, l1: snap.load[0], l5: snap.load[1], l15: snap.load[2]))
        if loadHistory.count > 200 { loadHistory.removeFirst(loadHistory.count - 200) }

        // GPU hanya dibaca saat panel terbuka (grafiknya hanya terlihat di sana)
        if panelOpen {
            let g = CPUStats.gpuStats()
            snap.gpu = g.device
            snap.gpuRenderer = g.renderer
            snap.gpuTiler = g.tiler
            if let c = g.cores { snap.gpuCores = c }
            if let d = g.device {
                gpuHistory.append(GPUPoint(date: now, device: d))
                if gpuHistory.count > 200 { gpuHistory.removeFirst(gpuHistory.count - 200) }
            }
        }
        snap.thermal = ProcessInfo.processInfo.thermalState
        // Sensor suhu adalah bacaan termahal: tiap tick saat panel terbuka, tiap 10 detik bila suhu
        // tampil di menu bar, selain itu tiap 60 detik (cukup untuk grafik Riwayat).
        let tempEvery: TimeInterval = panelOpen ? 0 : (settings.barItems.contains("temp") ? 10 : 60)
        if lastTempRead.map({ now.timeIntervalSince($0) >= tempEvery }) ?? true {
            lastTempRead = now
            if let t = TempSensors.cpu() ?? SMCTemps.cpu() {
                snap.cpuTemp = t.avg
                snap.cpuTempMax = t.max
            } else {
                snap.cpuTemp = nil
                snap.cpuTempMax = nil
            }
        }
        if snap.bootDate == nil { snap.bootDate = CPUStats.bootDate() }
        let t = CPUStats.awakeAndSleeping()
        snap.awake = t.awake
        snap.sleeping = t.sleeping
        cpu = snap

        if cpuTabVisible { refreshTopCPU() }
    }

    /// Daftar proses teratas (pakai /bin/ps) hanya diperbarui saat tab CPU terbuka, supaya hemat.
    func setCPUTabVisible(_ visible: Bool) {
        cpuTabVisible = visible
        if visible { refreshTopCPU() }
    }

    private func refreshTopCPU() {
        guard !topInFlight else { return }
        topInFlight = true
        DispatchQueue.global(qos: .utility).async {
            let top = CPUStats.topProcesses()
            DispatchQueue.main.async {
                self.topCPU = top
                self.topInFlight = false
            }
        }
    }

    // MARK: Jaringan

    private func netTick(now: Date) {
        if volumeTick % 5 == 1 || interfaces.isEmpty { interfaces = NetworkStats.interfaces() }
        let active = Set(interfaces.filter { $0.connected }.map { $0.bsd })
        let cur = NetworkStats.counters()
        if let t0 = prevNetTime {
            let dt = max(now.timeIntervalSince(t0), 0.5)
            var rx = 0.0, tx = 0.0
            for (name, c) in cur where active.contains(name) {
                guard let old = prevNet[name] else { continue }
                rx += Double(c.rx &- old.rx)
                tx += Double(c.tx &- old.tx)
            }
            netDown = rx / dt
            netUp = tx / dt
            netHistory.append(NetPoint(date: now, upKBps: netUp / 1000, downKBps: netDown / 1000))
            if netHistory.count > 200 { netHistory.removeFirst(netHistory.count - 200) }
        }
        prevNet = cur
        prevNetTime = now
    }

    func setNetworkVisible(_ visible: Bool) {
        networkVisible = visible
        if visible {
            interfaces = NetworkStats.interfaces()
            refreshNetProcs()
            refreshPublicIP(force: false)
        }
    }

    func refreshPublicIP(force: Bool) {
        guard settings.showPublicIP else { return }
        if !force, let d = publicIPDate, Date().timeIntervalSince(d) < 600 { return }
        publicIPDate = Date()
        NetworkStats.fetchPublicIP { ip in
            DispatchQueue.main.async { self.publicIP = ip }
        }
    }

    private func refreshNetProcs() {
        guard !netProcInFlight else { return }
        netProcInFlight = true
        DispatchQueue.global(qos: .utility).async {
            let procs = NetworkStats.topProcesses()
            DispatchQueue.main.async {
                self.netProcs = procs
                self.netProcInFlight = false
            }
        }
    }

    // MARK: Sensor

    private var sensorsViewers = 0

    /// Dihitung per tampilan (Dashboard dan tab Sensor) supaya pindah tab tidak saling mematikan.
    func setSensorsVisible(_ visible: Bool) {
        sensorsViewers = max(0, sensorsViewers + (visible ? 1 : -1))
        sensorsVisible = sensorsViewers > 0
        if visible {
            sensors = SensorReader.snapshot()
            volume = SystemStats.volumeSpace()
            if interfaces.isEmpty { interfaces = NetworkStats.interfaces() }
        }
    }

    @Published var freeReport: FreeRAMReport?
    @Published var freeMeasuring = false

    /// Tombol "Bebaskan RAM": bekukan app idle yang aman (aggressive = ikut yang jendelanya terlihat),
    /// lalu ukur ulang RAM ±15 detik kemudian karena macOS mengompres memorinya bertahap.
    func freeUpRAM(aggressive: Bool = false) {
        let before = SystemStats.snapshot()
        let r = freezer.freeUp(groups: groups, aggressive: aggressive)
        var rep = FreeRAMReport(date: Date(), beforePct: before.usedFraction * 100, beforePressure: before.pressure,
                                frozen: r.frozen, skipped: r.skipped)
        if aggressive, let old = freeReport {
            // "Bekukan lebih banyak": gabungkan dengan hasil sebelumnya dan pakai angka "sebelum" yang pertama
            rep = FreeRAMReport(date: old.date, beforePct: old.beforePct, beforePressure: old.beforePressure,
                                frozen: old.frozen + r.frozen, skipped: r.skipped)
        }
        freeReport = rep
        ToastTimer.shared.reset(for: rep.date)
        freeUpMessage = r.frozen.isEmpty
            ? tr("Tidak ada app idle yang aman dibekukan.", "No idle apps are safe to freeze.")
            : tr("\(rep.frozen.count) app dibekukan, ±\(Fmt.bytes(rep.frozenBytes)).", "\(rep.frozen.count) apps frozen, about \(Fmt.bytes(rep.frozenBytes)).")
        freeMeasuring = true
        let stamp = rep.date
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.freeReport?.date == stamp else { return }
            let after = SystemStats.snapshot()
            self.freeReport?.afterPct = after.usedFraction * 100
            self.freeReport?.afterPressure = after.pressure
            self.freeMeasuring = false
            ToastTimer.shared.start(for: stamp)
        }
    }

    /// Daftar baca/tulis per proses hanya dihitung saat tab Ringkasan terbuka.
    func setOverviewVisible(_ visible: Bool) {
        overviewVisible = visible
        if visible {
            prevIO = [:]
            prevIOTime = nil
            volume = SystemStats.volumeSpace()
            refreshDiskProcs()
        }
    }

    private func refreshDiskProcs() {
        guard !ioInFlight else { return }
        ioInFlight = true
        let before = prevIO
        let beforeTime = prevIOTime
        DispatchQueue.global(qos: .utility).async {
            let now = Date()
            let sample = DiskIOScanner.sample()
            var procs: [DiskProc] = []
            if let t0 = beforeTime {
                let dt = max(now.timeIntervalSince(t0), 0.5)
                for (pid, cur) in sample {
                    guard let old = before[pid] else { continue }
                    let r = cur.read >= old.read ? Double(cur.read - old.read) / dt : 0
                    let w = cur.written >= old.written ? Double(cur.written - old.written) / dt : 0
                    if r > 0 || w > 0 { procs.append(DiskProc(id: pid, name: cur.name, read: r, write: w)) }
                }
                procs.sort { ($0.read + $0.write) > ($1.read + $1.write) }
            }
            DispatchQueue.main.async {
                self.prevIO = sample
                self.prevIOTime = now
                if beforeTime != nil { self.diskProcs = Array(procs.prefix(5)) }
                self.ioInFlight = false
            }
        }
    }

    func refreshSSD() {
        DispatchQueue.global(qos: .utility).async {
            let r = SSDHealthReader.read()
            DispatchQueue.main.async {
                self.ssd = r.health
                self.ssdMessage = r.message
            }
        }
    }

    /// Dipanggil saat tab Browser dibuka / tab dihitung ulang: pakai data proses terakhir.
    func refreshBrowsers() {
        BrowserMonitor.shared.update(groups: groups, samples: lastSamples, cpu: lastCPUMap)
    }

    private func topSummary() -> String {
        groups.prefix(2).map { "\($0.name) (\(Fmt.bytes($0.footprint)))" }.joined(separator: ", ")
    }

    private func maybeAlert(key: String, every interval: TimeInterval, title: String, body: String) {
        let now = Date()
        if let last = lastAlert[key], now.timeIntervalSince(last) < interval { return }
        lastAlert[key] = now
        Notifier.post(title: title, body: body)
    }
}

enum Notifier {
    // UNUserNotificationCenter crash kalau dijalankan tanpa bundle .app (mis. `swift run`).
    private static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        guard available else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

/// Kesehatan SSD seumur hidup via smartctl (opsional: `brew install smartmontools`).
enum SSDHealthReader {
    private static let candidates = ["/opt/homebrew/bin/smartctl", "/usr/local/bin/smartctl"]

    static func read() -> (health: SSDHealth?, message: SSDMessage?) {
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return (nil, .notInstalled)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["-a", "disk0"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return (nil, .runFailed(error.localizedDescription)) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)

        var h = SSDHealth()
        for line in text.split(separator: "\n") {
            let l = String(line)
            if l.hasPrefix("Data Units Written:"), let a = l.firstIndex(of: "["), let b = l.firstIndex(of: "]") {
                h.written = String(l[l.index(after: a)..<b])
            } else if l.hasPrefix("Percentage Used:") {
                h.percentUsed = number(in: l)
            } else if l.hasPrefix("Available Spare:") {
                h.availableSpare = number(in: l)
            } else if l.hasPrefix("Power On Hours:") {
                h.powerOnHours = number(in: l)
            }
        }
        if h.written == nil && h.percentUsed == nil {
            return (nil, .noData)
        }
        return (h, nil)
    }

    private static func number(in line: String) -> Int? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let digits = line[line.index(after: colon)...].filter { $0.isNumber }
        return Int(digits)
    }
}
