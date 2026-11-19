import Foundation
import SwiftUI
import Charts

// MARK: - Riwayat harian

struct BatterySample: Codable, Identifiable {
    var id: String { day }
    let day: String       // yyyy-MM-dd
    let health: Double    // %
    let cycles: Int
}

/// Mencatat kesehatan baterai sekali sehari ke ~/Library/Application Support/PY-Sys/battery-history.json,
/// karena macOS sendiri tidak menyimpan riwayatnya.
final class BatteryHistory: ObservableObject {
    static let shared = BatteryHistory()

    @Published private(set) var samples: [BatterySample] = []

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PY-Sys", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("battery-history.json")
    }()

    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {
        if let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([BatterySample].self, from: data) {
            samples = list
        }
    }

    func recordIfNeeded() {
        AppleBatteryInfo.shared.refresh()
        let today = Self.dayFormat.string(from: Date())
        guard samples.last?.day != today, let b = SensorReader.battery() else { return }
        let apple = AppleBatteryInfo.shared
        guard let health = apple.maxCapacity ?? b.health.map({ $0 * 100 }),
              let c = b.cycles ?? apple.cycles else { return }
        samples.append(BatterySample(day: today, health: health, cycles: c))
        if samples.count > 2000 { samples.removeFirst(samples.count - 2000) }
        if let data = try? JSONEncoder().encode(samples) { try? data.write(to: url, options: .atomic) }
    }
}

// MARK: - Perhitungan

struct BatteryReport {
    let health: Double          // %
    let design: Int?
    let current: Int?
    let cycles: Int
    let ratePer100: Double?     // % turun per 100 siklus
    let fromHistory: Bool
    let cyclesAt80: Int?

    static let appleRatePer100 = 2.0   // ±80% setelah 1.000 siklus

    var statusText: String {
        if health >= 85 { return "Normal" }
        if health >= 80 { return tr("Mendekati batas", "Nearing limit") }
        return tr("Servis disarankan", "Service recommended")
    }
    var statusColor: Color { health >= 85 ? .green : (health >= 80 ? .orange : .red) }

    static func make(_ b: BatteryInfo, history: [BatterySample], appleMax: Double?, appleCycles: Int?) -> BatteryReport? {
        guard let health = appleMax ?? b.health.map({ $0 * 100 }),
              let cycles = b.cycles ?? appleCycles else { return nil }
        var rate: Double?
        var fromHistory = false
        if let first = history.first, let last = history.last, last.cycles - first.cycles >= 30 {
            rate = max(0, (first.health - last.health) / Double(last.cycles - first.cycles) * 100)
            fromHistory = true
        } else if cycles > 0 {
            rate = max(0, (100 - health) / Double(cycles) * 100)
        }
        var at80: Int?
        if let r = rate, r > 0.05, health > 80 {
            at80 = cycles + Int(((health - 80) / r * 100).rounded())
        }
        return BatteryReport(health: health, design: b.designCapacity, current: b.rawMaxCapacity, cycles: cycles,
                             ratePer100: rate, fromHistory: fromHistory, cyclesAt80: at80)
    }
}

private func num(_ v: Double, _ digits: Int = 1) -> String {
    let s = String(format: "%.\(digits)f", v)
    return AppLanguage.isEnglish ? s : s.replacingOccurrences(of: ".", with: ",")
}

private func mah(_ v: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: AppLanguage.isEnglish ? "en_US" : "id_ID")
    return (f.string(from: NSNumber(value: v)) ?? "\(v)") + " mAh"
}

// MARK: - Tampilan

struct ChartPt: Identifiable {
    let id: Int
    let x: Double
    let y: Double
}

struct BatteryDepreciationView: View {
    @ObservedObject private var history = BatteryHistory.shared
    @ObservedObject private var apple = AppleBatteryInfo.shared

    var body: some View {
        if let b = SensorReader.battery(),
           let r = BatteryReport.make(b, history: history.samples, appleMax: apple.maxCapacity, appleCycles: apple.cycles) {
            let apple = [ChartPt(id: 0, x: 0, y: 100), ChartPt(id: 1, x: 1000, y: 80)]
            let macPts: [ChartPt] = {
                var pts = [ChartPt(id: 0, x: 0, y: 100)]
                for (i, s) in history.samples.enumerated() { pts.append(ChartPt(id: i + 1, x: Double(s.cycles), y: s.health)) }
                if pts.last.map({ Int($0.x) != r.cycles }) ?? true {
                    pts.append(ChartPt(id: pts.count, x: Double(r.cycles), y: r.health))
                }
                return pts
            }()
            let proj: [ChartPt] = r.cyclesAt80.map {
                [ChartPt(id: 0, x: Double(r.cycles), y: r.health), ChartPt(id: 1, x: Double($0), y: 80)]
            } ?? []
            let xMax = Double(max(1000, (r.cyclesAt80 ?? 0) + 50, r.cycles + 50))
            let yMin = min(70.0, (r.health - 5).rounded(.down))

            GroupBox(tr("Depresiasi baterai", "Battery depreciation")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(tr("Kesehatan", "Health")).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(num(r.health, 0))%").font(.title3).monospacedDigit()
                        Text(r.statusText)
                            .font(.caption)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(r.statusColor.opacity(0.18), in: Capsule())
                            .foregroundStyle(r.statusColor)
                    }
                    .font(.callout)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.18))
                            Capsule().fill(r.statusColor).frame(width: geo.size.width * CGFloat(min(r.health, 100) / 100))
                            Rectangle().fill(Color.orange).frame(width: 2, height: 14)
                                .offset(x: geo.size.width * 0.8 - 1)
                        }
                    }
                    .frame(height: 8)
                    .padding(.vertical, 4)

                    if let d = r.design { StatRow(title: tr("Kapasitas awal", "Design capacity"), value: mah(d)) }
                    if let c = r.current { StatRow(title: tr("Kapasitas sekarang", "Current capacity"), value: mah(c)) }
                    StatRow(title: tr("Siklus", "Cycles"), value: "\(r.cycles)")
                    if let rate = r.ratePer100 {
                        HStack {
                            Text(tr("Penurunan per 100 siklus", "Loss per 100 cycles")).foregroundStyle(.secondary)
                            Spacer()
                            Text("−\(num(rate))%").monospacedDigit()
                                .foregroundStyle(rate > BatteryReport.appleRatePer100 ? Color.orange : Color.primary)
                            Text(tr("(Apple ±2%)", "(Apple ±2%)")).foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                    StatRow(title: tr("Perkiraan 80%", "Reaches 80% at"),
                            value: r.cyclesAt80.map { tr("± siklus \($0)", "± cycle \($0)") }
                                ?? (r.health <= 80 ? tr("Sudah di bawah 80%", "Already below 80%") : "–"))

                    Chart {
                        ForEach(apple) { p in
                            LineMark(x: .value("Siklus", p.x), y: .value("%", p.y), series: .value("s", "Apple"))
                                .foregroundStyle(Color.gray)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        }
                        ForEach(macPts) { p in
                            LineMark(x: .value("Siklus", p.x), y: .value("%", p.y), series: .value("s", "Mac"))
                                .foregroundStyle(Color.green)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        ForEach(proj) { p in
                            LineMark(x: .value("Siklus", p.x), y: .value("%", p.y), series: .value("s", "Proj"))
                                .foregroundStyle(Color.green)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        }
                        PointMark(x: .value("Siklus", Double(r.cycles)), y: .value("%", r.health))
                            .foregroundStyle(Color.green)
                        RuleMark(y: .value("Batas", 80))
                            .foregroundStyle(Color.orange)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    .chartXScale(domain: 0...xMax)
                    .chartYScale(domain: yMin...100)
                    .chartXAxis { AxisMarks(values: [0, 500, 1000]) }
                    .chartYAxis { AxisMarks(position: .leading, values: [80, 90, 100]) }
                    .frame(height: 110)
                    .padding(.top, 6)

                    HStack(spacing: 12) {
                        LegendLine(color: .green, dashed: false, title: tr("Mac ini", "This Mac"))
                        LegendLine(color: .gray, dashed: true, title: tr("Patokan Apple", "Apple reference"))
                        LegendLine(color: .orange, dashed: true, title: tr("Batas servis", "Service limit"))
                    }
                    Text(history.samples.count < 2
                         ? tr("Riwayat mulai dicatat hari ini (sekali sehari). Sementara ini garis hijau adalah rata-rata sejak baru.",
                              "History is recorded once a day from today. Until then the green line is the lifetime average.")
                         : tr("\(history.samples.count) hari tercatat · \(r.fromHistory ? "laju dari riwayat" : "laju rata-rata seumur pakai")",
                              "\(history.samples.count) days recorded · \(r.fromHistory ? "rate from history" : "lifetime average rate")"))
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if SensorReader.battery() != nil {
            GroupBox(tr("Depresiasi baterai", "Battery depreciation")) {
                Text(tr("Data kapasitas baterai tidak terbaca di Mac ini.", "Battery capacity data can't be read on this Mac."))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct LegendLine: View {
    let color: Color
    let dashed: Bool
    let title: String
    var body: some View {
        HStack(spacing: 4) {
            Path { p in p.move(to: CGPoint(x: 0, y: 4)); p.addLine(to: CGPoint(x: 14, y: 4)) }
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [3, 3] : []))
                .frame(width: 14, height: 8)
            Text(title)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Nilai resmi macOS (sama dengan System Settings → Battery)

/// Membaca "Maximum Capacity" dan kondisi baterai persis seperti yang ditampilkan macOS,
/// lewat `system_profiler SPPowerDataType -json` (diperbarui paling sering tiap 30 menit).
final class AppleBatteryInfo: ObservableObject {
    static let shared = AppleBatteryInfo()

    @Published private(set) var maxCapacity: Double?   // %
    @Published private(set) var condition: String?
    @Published private(set) var cycles: Int?
    private var lastRead: Date?
    private var loading = false

    func refresh(force: Bool = false) {
        if loading { return }
        if !force, let l = lastRead, Date().timeIntervalSince(l) < 1800 { return }
        loading = true
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["SPPowerDataType", "-json"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            var maxCap: Double?, cond: String?, cyc: Int?
            if (try? p.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = root["SPPowerDataType"] as? [[String: Any]] {
                    for item in items {
                        guard let info = item["sppower_battery_health_info"] as? [String: Any] else { continue }
                        if let s = info["sppower_battery_health_maximum_capacity"] as? String {
                            maxCap = Double(s.filter { $0.isNumber || $0 == "." })
                        } else if let n = info["sppower_battery_health_maximum_capacity"] as? NSNumber {
                            maxCap = n.doubleValue
                        }
                        cond = info["sppower_battery_health"] as? String
                        cyc = (info["sppower_battery_cycle_count"] as? NSNumber)?.intValue
                    }
                }
            }
            DispatchQueue.main.async {
                self.maxCapacity = maxCap
                self.condition = cond
                self.cycles = cyc
                self.lastRead = Date()
                self.loading = false
            }
        }
    }

    /// Kondisi dalam bahasa aplikasi.
    var conditionText: String? {
        guard let c = condition else { return nil }
        switch c.lowercased() {
        case "good", "normal": return "Normal"
        case "service recommended": return tr("Servis disarankan", "Service recommended")
        default: return c
        }
    }
}
