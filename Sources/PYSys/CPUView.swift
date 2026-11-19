import SwiftUI
import Charts

extension ProcessInfo.ThermalState {
    var label: String {
        switch self {
        case .nominal: return tr("Normal", "Nominal")
        case .fair: return tr("Hangat", "Fair")
        case .serious: return tr("Panas", "Serious")
        case .critical: return tr("Kritis", "Critical")
        @unknown default: return "–"
        }
    }
    var color: Color {
        switch self {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .secondary
        }
    }
}

struct CPUTab: View {
    @ObservedObject var core: AetherCore

    private var c: CPUSnapshot { core.cpu }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Grafik User + System
            GroupBox("CPU") {
                VStack(spacing: 6) {
                    Chart {
                        ForEach(Array(core.cpuHistory.enumerated()), id: \.offset) { item in
                            AreaMark(x: .value("t", item.element.date),
                                     y: .value("%", item.element.system * 100), stacking: .standard)
                                .foregroundStyle(by: .value("type", "System"))
                            AreaMark(x: .value("t", item.element.date),
                                     y: .value("%", item.element.user * 100), stacking: .standard)
                                .foregroundStyle(by: .value("type", "User"))
                        }
                    }
                    .chartForegroundStyleScale(["System": Color.red, "User": Color.cyan])
                    .chartLegend(.hidden)
                    .chartXAxis(.hidden)
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(values: [0, 50, 100]) { v in
                            AxisGridLine()
                            AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(.system(size: 8)) }
                        }
                    }
                    .frame(height: 80)

                    LegendRow(color: .cyan, title: "User", value: pct(c.user))
                    LegendRow(color: .red, title: "System", value: pct(c.system))
                    LegendRow(color: .secondary.opacity(0.3), title: "Idle", value: pct(c.idle))
                }
            }

            // Per inti
            GroupBox(tr("Per inti", "Per core")) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(0..<c.cores.count, id: \.self) { i in
                        let label = i < CPUStats.coreLabels.count ? CPUStats.coreLabels[i] : "\(i + 1)"
                        VStack(spacing: 2) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.15))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(label.hasPrefix("P") ? Color.blue : Color.cyan)
                                    .frame(height: max(1, 50 * c.cores[i]))
                            }
                            .frame(height: 50)
                            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }

            // Proses teratas
            GroupBox(tr("Proses teratas", "Top processes")) {
                VStack(spacing: 3) {
                    if core.topCPU.isEmpty {
                        Text(tr("Memuat…", "Loading…")).font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(core.topCPU) { p in
                        StatRow(title: p.name, value: String(format: "%.1f%%", p.cpu))
                    }
                }
            }

            // GPU & termal
            GroupBox(tr("Apple Silicon", "Apple Silicon")) {
                VStack(spacing: 6) {
                    MeterRow(title: tr("Prosesor", "Processor"), value: 1 - c.idle, color: .cyan)
                    if let g = c.gpu { MeterRow(title: "GPU", value: g / 100, color: .purple) }
                    HStack {
                        Text(tr("Suhu CPU", "CPU temperature")).foregroundStyle(.secondary)
                        Spacer()
                        if let t = c.cpuTemp {
                            Text(String(format: "%.0f°C", t)).monospacedDigit().bold()
                                .foregroundStyle(t >= 90 ? Color.red : (t >= 75 ? Color.orange : Color.primary))
                            if let m = c.cpuTempMax {
                                Text(String(format: tr("(maks %.0f°)", "(max %.0f°)"), m))
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        } else {
                            Text(tr("tidak tersedia", "unavailable")).foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                    HStack {
                        Text(tr("Status termal", "Thermal state")).foregroundStyle(.secondary)
                        Spacer()
                        Text(c.thermal.label).foregroundStyle(c.thermal.color).bold()
                    }
                    .font(.callout)
                }
            }

            // Load average
            GroupBox("Load average") {
                VStack(spacing: 6) {
                    Chart {
                        ForEach(Array(core.loadHistory.enumerated()), id: \.offset) { item in
                            LineMark(x: .value("t", item.element.date), y: .value("l", item.element.l15),
                                     series: .value("k", "15m"))
                                .foregroundStyle(by: .value("k", "15m"))
                            LineMark(x: .value("t", item.element.date), y: .value("l", item.element.l5),
                                     series: .value("k", "5m"))
                                .foregroundStyle(by: .value("k", "5m"))
                            LineMark(x: .value("t", item.element.date), y: .value("l", item.element.l1),
                                     series: .value("k", "1m"))
                                .foregroundStyle(by: .value("k", "1m"))
                        }
                    }
                    .chartForegroundStyleScale(["1m": Color.cyan, "5m": Color.red, "15m": Color.gray])
                    .chartLegend(.hidden)
                    .chartXAxis(.hidden)
                    .frame(height: 60)

                    HStack {
                        LoadChip(color: .cyan, title: "1m", value: c.load[0])
                        Spacer()
                        LoadChip(color: .red, title: "5m", value: c.load[1])
                        Spacer()
                        LoadChip(color: .gray, title: "15m", value: c.load[2])
                    }
                }
            }

            // Uptime
            GroupBox("Uptime") {
                VStack(spacing: 4) {
                    if let b = c.bootDate {
                        StatRow(title: tr("Menyala sejak", "Powered on"),
                                value: b.formatted(date: .abbreviated, time: .shortened))
                        StatRow(title: "Uptime", value: Fmt.duration(Date().timeIntervalSince(b)))
                    }
                    StatRow(title: tr("Waktu aktif", "Time awake"), value: Fmt.duration(c.awake))
                    StatRow(title: tr("Waktu tidur", "Time sleeping"), value: Fmt.duration(c.sleeping))
                }
            }
        }
        .onAppear { core.setCPUTabVisible(true) }
        .onDisappear { core.setCPUTabVisible(false) }
    }

    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
}

struct LegendRow: View {
    let color: Color
    let title: String
    let value: String
    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}

struct MeterRow: View {
    let title: String
    let value: Double
    let color: Color
    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3).fill(color)
                        .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
                }
            }
            .frame(height: 10)
            Text("\(Int((value * 100).rounded()))%").monospacedDigit().frame(width: 40, alignment: .trailing)
        }
        .font(.callout)
    }
}

struct LoadChip: View {
    let color: Color
    let title: String
    let value: Double
    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(title).foregroundStyle(.secondary)
            Text(String(format: "%.2f", value)).monospacedDigit()
        }
        .font(.callout)
    }
}
