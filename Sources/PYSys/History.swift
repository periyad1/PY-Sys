import AppKit
import SwiftUI
import Charts

// MARK: - Riwayat 24 jam / 7 hari + tulis SSD harian + pengingat restart

struct HSample: Codable {
    let t: Date
    let ram: Float        // % RAM terpakai
    let swap: Float       // GB
    let pressure: Float   // % tekanan memori
    let cpu: Float        // % CPU total
    let temp: Float?      // °C
}

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var samples: [HSample] = []
    @Published private(set) var dailyWrites: [String: UInt64] = [:]   // "yyyy-MM-dd" → byte
    @Published private(set) var advice: [String] = []                  // alasan saran restart

    private var lastCounter: UInt64?
    private var lastAdviceAlert: Date?
    private var timer: Timer?
    private var tick = 0

    private struct Stored: Codable {
        var samples: [HSample]
        var dailyWrites: [String: UInt64]
        var lastCounter: UInt64?
        var lastAdviceAlert: Date?
    }

    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PY-Sys", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func start() {
        load()
        record()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.record() }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func load() {
        guard let d = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        guard let s = try? dec.decode(Stored.self, from: d) else { return }
        samples = s.samples
        dailyWrites = s.dailyWrites
        lastCounter = s.lastCounter
        lastAdviceAlert = s.lastAdviceAlert
    }

    func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        let s = Stored(samples: samples, dailyWrites: dailyWrites, lastCounter: lastCounter, lastAdviceAlert: lastAdviceAlert)
        if let d = try? enc.encode(s) { try? d.write(to: url, options: .atomic) }
    }

    private func record() {
        let core = AetherCore.shared
        let m = core.mem
        let now = Date()
        samples.append(HSample(t: now, ram: Float(m.usedFraction * 100),
                               swap: Float(Double(m.swapUsed) / 1_073_741_824),
                               pressure: Float(m.pressureFraction * 100),
                               cpu: Float((1 - core.cpu.idle) * 100),
                               temp: core.cpu.cpuTemp.map { Float($0) }))
        let cutoff = now.addingTimeInterval(-7 * 86_400)
        if let i = samples.firstIndex(where: { $0.t >= cutoff }), i > 0 { samples.removeFirst(i) }

        // Tulis SSD: penghitung sejak boot; bila mengecil berarti Mac baru restart.
        let c = core.diskWrittenSinceBoot
        if c > 0 {
            let delta: UInt64 = lastCounter.map { c >= $0 ? c - $0 : c } ?? 0
            lastCounter = c
            let key = Self.dayFormat.string(from: now)
            dailyWrites[key, default: 0] += delta
            if dailyWrites.count > 60 {
                for k in dailyWrites.keys.sorted().prefix(dailyWrites.count - 60) { dailyWrites[k] = nil }
            }
        }

        evaluateRestart(now: now)
        tick += 1
        if tick % 10 == 0 { save() }   // tiap ±10 menit
    }

    // MARK: Pengingat restart cerdas

    private func evaluateRestart(now: Date) {
        let core = AetherCore.shared
        var reasons: [String] = []
        let uptimeDays = core.cpu.bootDate.map { now.timeIntervalSince($0) / 86_400 } ?? 0
        let swapGB = Double(core.mem.swapUsed) / 1_073_741_824
        let lastHour = samples.filter { now.timeIntervalSince($0.t) <= 3600 }
        let strained = lastHour.filter { $0.pressure >= 50 }.count
        if swapGB >= 6 {
            reasons.append(tr(String(format: "Swap sudah %.1f GB: SSD terus ditulisi dan Mac terasa lambat.", swapGB),
                              String(format: "Swap is at %.1f GB: the SSD keeps being written and the Mac feels slow.", swapGB)))
        } else if uptimeDays >= 7 && swapGB >= 3 {
            reasons.append(tr(String(format: "Mac menyala %.0f hari tanpa restart dan swap %.1f GB.", uptimeDays, swapGB),
                              String(format: "The Mac has been up %.0f days without a restart and swap is %.1f GB.", uptimeDays, swapGB)))
        }
        if lastHour.count >= 30 && Double(strained) / Double(lastHour.count) >= 0.5 {
            reasons.append(tr("Tekanan memori tinggi lebih dari separuh waktu dalam 1 jam terakhir.",
                              "Memory pressure has been high for more than half of the last hour."))
        }
        if uptimeDays >= 14 {
            reasons.append(tr(String(format: "Uptime %.0f hari: restart membersihkan memori yang bocor dan memasang pembaruan.", uptimeDays),
                              String(format: "Up %.0f days: a restart clears leaked memory and applies updates.", uptimeDays)))
        }
        advice = reasons
        guard !reasons.isEmpty, core.settings.restartReminder,
              lastAdviceAlert.map({ now.timeIntervalSince($0) > 86_400 }) ?? true else { return }
        lastAdviceAlert = now
        Notifier.post(title: tr("Saran: restart Mac", "Suggestion: restart your Mac"), body: reasons.joined(separator: " "))
    }

    static func restartMac() {
        let a = NSAlert()
        a.messageText = tr("Restart Mac sekarang?", "Restart your Mac now?")
        a.informativeText = tr("macOS akan meminta Anda menyimpan dokumen yang belum disimpan.",
                               "macOS will ask you to save any unsaved documents.")
        a.addButton(withTitle: "Restart")
        a.addButton(withTitle: tr("Batal", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        HistoryStore.shared.save()
        var err: NSDictionary?
        _ = NSAppleScript(source: "tell application \"System Events\" to restart")?.executeAndReturnError(&err)
    }

    // MARK: Agregasi untuk grafik

    struct Point: Identifiable {
        let id: Date
        let value: Double
    }

    enum Metric: String, CaseIterable, Identifiable {
        case ram, pressure, swap, cpu, temp
        var id: String { rawValue }
        var title: String {
            switch self {
            case .ram: return "RAM %"
            case .pressure: return tr("Tekanan", "Pressure")
            case .swap: return "Swap GB"
            case .cpu: return "CPU %"
            case .temp: return tr("Suhu °C", "Temp °C")
            }
        }
        func value(_ s: HSample) -> Double? {
            switch self {
            case .ram: return Double(s.ram)
            case .pressure: return Double(s.pressure)
            case .swap: return Double(s.swap)
            case .cpu: return Double(s.cpu)
            case .temp: return s.temp.map(Double.init)
            }
        }
    }

    /// Rata-rata per ember waktu (24 jam → 5 menit, 7 hari → 30 menit) supaya grafik ringan.
    func series(_ metric: Metric, hours: Int) -> [Point] {
        let now = Date()
        let bucket: TimeInterval = hours <= 24 ? 300 : 1800
        var sums: [Date: (Double, Int)] = [:]
        for s in samples where now.timeIntervalSince(s.t) <= Double(hours) * 3600 {
            guard let v = metric.value(s) else { continue }
            let k = Date(timeIntervalSince1970: (s.t.timeIntervalSince1970 / bucket).rounded(.down) * bucket)
            let cur = sums[k] ?? (0, 0)
            sums[k] = (cur.0 + v, cur.1 + 1)
        }
        return sums.map { Point(id: $0.key, value: $0.value.0 / Double($0.value.1)) }.sorted { $0.id < $1.id }
    }

    func days(_ n: Int) -> [(day: String, bytes: UInt64)] {
        let cal = Calendar.current
        return (0..<n).reversed().compactMap { i in
            guard let d = cal.date(byAdding: .day, value: -i, to: Date()) else { return nil }
            let k = Self.dayFormat.string(from: d)
            return (k, dailyWrites[k] ?? 0)
        }
    }
}

struct DayWrite: Identifiable {
    let id: String
    let label: String
    let gb: Double
}

struct HistoryTab: View {
    @ObservedObject var core: AetherCore
    @ObservedObject private var store = HistoryStore.shared
    @ObservedObject private var ui = UIState.shared

    private var hours: Int { ui.historyRange == "7d" ? 168 : 24 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !store.advice.isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(tr("Disarankan restart", "Restart recommended"), systemImage: "arrow.clockwise.circle")
                            .font(.callout.bold()).foregroundStyle(.orange)
                        ForEach(store.advice, id: \.self) { Text("• " + $0).font(.caption) }
                        Button(tr("Restart sekarang…", "Restart now…")) { HistoryStore.restartMac() }
                            .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack {
                Picker("", selection: $ui.historyRange) {
                    Text(tr("24 jam", "24 hours")).tag("24h")
                    Text(tr("7 hari", "7 days")).tag("7d")
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 160)
                Spacer()
                Picker("", selection: $ui.historyMetric) {
                    ForEach(HistoryStore.Metric.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden().frame(width: 120)
            }

            let metric = HistoryStore.Metric(rawValue: ui.historyMetric) ?? .ram
            let pts = store.series(metric, hours: hours)
            if pts.count < 2 {
                Text(tr("Data dikumpulkan tiap menit. Grafik muncul setelah beberapa menit, dan tetap tersimpan walau PY-Sys ditutup.",
                        "Data is collected every minute. The chart appears after a few minutes and is kept even if PY-Sys quits."))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(height: 140)
            } else {
                Chart(pts) { p in
                    AreaMark(x: .value("t", p.id), y: .value(metric.title, p.value))
                        .foregroundStyle(Theme.accent.opacity(0.18))
                    LineMark(x: .value("t", p.id), y: .value(metric.title, p.value))
                        .foregroundStyle(Theme.accent)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: hours <= 24 ? Date.FormatStyle.dateTime.hour() : Date.FormatStyle.dateTime.weekday(.abbreviated))
                    }
                }
                .frame(height: 150)
                let vals = pts.map(\.value)
                HStack(spacing: 10) {
                    DashStat(title: tr("Rata-rata", "Average"), value: String(format: "%.1f", vals.reduce(0, +) / Double(vals.count)))
                    DashStat(title: tr("Tertinggi", "Peak"), value: String(format: "%.1f", vals.max() ?? 0))
                    DashStat(title: tr("Terendah", "Lowest"), value: String(format: "%.1f", vals.min() ?? 0))
                }
            }

            Divider()
            SSDDailyView(core: core, store: store)
        }
    }
}

struct SSDDailyView: View {
    @ObservedObject var core: AetherCore
    @ObservedObject var store: HistoryStore

    private static let short: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d/M"
        return f
    }()

    /// "63.2 TB" / "512 GB" → byte
    private static func parse(_ s: String?) -> Double? {
        guard let s else { return nil }
        let parts = s.replacingOccurrences(of: ",", with: ".").split(separator: " ")
        guard parts.count >= 2, let v = Double(parts[0]) else { return nil }
        switch parts[1].uppercased() {
        case "TB": return v * 1e12
        case "GB": return v * 1e9
        case "PB": return v * 1e15
        default: return nil
        }
    }

    var body: some View {
        let days = store.days(14)
        let fmt = Self.short
        let items = days.map { d -> DayWrite in
            let label = HistoryStore.dayFormat.date(from: d.day).map { fmt.string(from: $0) } ?? d.day
            return DayWrite(id: d.day, label: label, gb: Double(d.bytes) / 1e9)
        }
        let measured = items.filter { $0.gb > 0 }
        let avg = measured.isEmpty ? 0 : measured.map(\.gb).reduce(0, +) / Double(measured.count)

        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Tulis SSD per hari", "SSD writes per day")).font(.subheadline.bold())
            Chart(items) { d in
                BarMark(x: .value(tr("Hari", "Day"), d.label), y: .value("GB", d.gb))
                    .foregroundStyle(d.gb > 100 ? Color.orange : Theme.accent)
            }
            .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.system(size: 8)) } }
            .frame(height: 110)
            HStack(spacing: 10) {
                DashStat(title: tr("Hari ini", "Today"), value: String(format: "%.1f GB", items.last?.gb ?? 0))
                DashStat(title: tr("Rata-rata/hari", "Average/day"), value: String(format: "%.1f GB", avg))
            }
            if let ssd = core.ssd, let pct = ssd.percentUsed, pct > 0, let written = Self.parse(ssd.written), avg > 0 {
                let endurance = written / (Double(pct) / 100)
                let years = (endurance - written) / (avg * 1e9 * 365)
                Text(tr(String(format: "Dengan pola ini, sisa umur tulis SSD diperkirakan ±%.0f tahun (sudah terpakai %ld%%, total ditulis %@).", years, pct, ssd.written ?? "?"),
                        String(format: "At this rate the SSD's remaining write life is about %.0f years (%ld%% used, %@ written in total).", years, pct, ssd.written ?? "?")))
                    .font(.caption).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(tr("Perkiraan sisa umur SSD muncul bila data kesehatan SSD (smartctl) tersedia dan sudah ada data tulis harian.",
                        "The SSD life estimate appears once SSD health data (smartctl) and daily write data are available."))
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(tr("Lebih dari ±100 GB/hari pada Mac 8 GB biasanya tanda swap berlebihan.",
                    "More than about 100 GB/day on an 8 GB Mac usually means heavy swapping."))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
