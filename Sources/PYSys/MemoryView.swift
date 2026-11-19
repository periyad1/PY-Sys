import SwiftUI
import Charts

struct MemoryTab: View {
    @ObservedObject var core: AetherCore

    private var m: MemorySnapshot { core.mem }
    private var totalGB: Double { max(1, Double(m.total) / 1_073_741_824) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tekanan
            GroupBox(tr("Tekanan memori", "Memory pressure")) {
                VStack(spacing: 6) {
                    MeterRow(title: tr("Tekanan", "Pressure"), value: m.pressureFraction,
                             color: m.pressure.color)
                    Chart {
                        ForEach(Array(core.history.enumerated()), id: \.offset) { item in
                            AreaMark(x: .value("t", item.element.date), y: .value("%", item.element.pressurePct))
                                .foregroundStyle(m.pressure.color.opacity(0.35))
                            LineMark(x: .value("t", item.element.date), y: .value("%", item.element.pressurePct))
                                .foregroundStyle(m.pressure.color)
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(values: [0, 50, 100]) { v in
                            AxisGridLine()
                            AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%").font(.system(size: 8)) }
                        }
                    }
                    .frame(height: 60)
                    StatRow(title: tr("Memori aplikasi", "App memory"), value: Fmt.bytes(m.app))
                    StatRow(title: "Wired", value: Fmt.bytes(m.wired))
                    StatRow(title: tr("Terkompresi", "Compressed"), value: Fmt.bytes(m.compressed))
                    StatRow(title: "Cache", value: Fmt.bytes(m.cachedFiles))
                    HStack {
                        Text(tr("Status kernel", "Kernel level")).foregroundStyle(.secondary)
                        Spacer()
                        PressureBadge(level: m.pressure)
                    }
                    .font(.callout)
                }
            }

            // Komposisi memori
            GroupBox(tr("Memori", "Memory")) {
                VStack(spacing: 6) {
                    CompositionBar(segments: [
                        (m.wired, Color.cyan), (m.active, Color.red), (m.compressed, Color.purple),
                    ], total: m.total)
                    Chart {
                        ForEach(Array(core.history.enumerated()), id: \.offset) { item in
                            AreaMark(x: .value("t", item.element.date), y: .value("GB", item.element.wiredGB),
                                     stacking: .standard)
                                .foregroundStyle(by: .value("k", "Wired"))
                            AreaMark(x: .value("t", item.element.date), y: .value("GB", item.element.activeGB),
                                     stacking: .standard)
                                .foregroundStyle(by: .value("k", "Active"))
                            AreaMark(x: .value("t", item.element.date), y: .value("GB", item.element.compressedGB),
                                     stacking: .standard)
                                .foregroundStyle(by: .value("k", "Compressed"))
                        }
                    }
                    .chartForegroundStyleScale(["Wired": Color.cyan, "Active": Color.red, "Compressed": Color.purple])
                    .chartLegend(.hidden)
                    .chartXAxis(.hidden)
                    .chartYScale(domain: 0...totalGB)
                    .frame(height: 70)
                    LegendRow(color: .cyan, title: "Wired", value: Fmt.bytes(m.wired))
                    LegendRow(color: .red, title: tr("Aktif", "Active"), value: Fmt.bytes(m.active))
                    LegendRow(color: .purple, title: tr("Terkompresi", "Compressed"), value: Fmt.bytes(m.compressed))
                    LegendRow(color: .secondary.opacity(0.3), title: tr("Bebas", "Free"), value: Fmt.bytes(m.free))
                }
            }

            // Aplikasi terbesar
            GroupBox(tr("Proses", "Processes")) {
                VStack(spacing: 4) {
                    ForEach(Array(core.groups.prefix(6))) { g in
                        HStack(spacing: 6) {
                            if let icon = g.icon {
                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "terminal").frame(width: 16, height: 16)
                            }
                            Text(g.name).lineLimit(1)
                            Spacer()
                            Text(Fmt.bytes(g.footprint)).monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
            }

            // Swap
            GroupBox("Swap") {
                VStack(spacing: 6) {
                    MeterRow(title: tr("Terpakai", "Used"),
                             value: m.swapTotal == 0 ? 0 : Double(m.swapUsed) / Double(m.swapTotal),
                             color: .cyan)
                    Text(tr("\(Fmt.bytes(m.swapUsed)) dari \(Fmt.bytes(m.swapTotal))",
                            "\(Fmt.bytes(m.swapUsed)) of \(Fmt.bytes(m.swapTotal))"))
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Chart {
                        ForEach(Array(core.history.enumerated()), id: \.offset) { item in
                            AreaMark(x: .value("t", item.element.date), y: .value("GB", item.element.swapGB))
                                .foregroundStyle(Color.cyan.opacity(0.6))
                        }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: 50)
                }
            }

            // Pages
            GroupBox("Pages") {
                VStack(spacing: 6) {
                    Chart {
                        ForEach(Array(core.history.enumerated()), id: \.offset) { item in
                            LineMark(x: .value("t", item.element.date), y: .value("MB/s", item.element.pageInMBps),
                                     series: .value("k", "In"))
                                .foregroundStyle(by: .value("k", "In"))
                            LineMark(x: .value("t", item.element.date), y: .value("MB/s", item.element.pageOutMBps),
                                     series: .value("k", "Out"))
                                .foregroundStyle(by: .value("k", "Out"))
                        }
                    }
                    .chartForegroundStyleScale(["In": Color.cyan, "Out": Color.red])
                    .chartLegend(.hidden)
                    .chartXAxis(.hidden)
                    .frame(height: 50)
                    LegendRow(color: .cyan, title: "Page ins", value: Fmt.rate(core.pageInRate))
                    LegendRow(color: .red, title: "Page outs", value: Fmt.rate(core.pageOutRate))
                    LegendRow(color: .purple, title: "Swap-out", value: Fmt.rate(core.swapOutRate))
                }
            }
        }
    }
}

struct CompositionBar: View {
    let segments: [(UInt64, Color)]
    let total: UInt64

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(0..<segments.count, id: \.self) { i in
                    Rectangle()
                        .fill(segments[i].1)
                        .frame(width: max(0, geo.size.width * CGFloat(Double(segments[i].0) / Double(max(total, 1)))))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 12)
        .background(Color.secondary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
