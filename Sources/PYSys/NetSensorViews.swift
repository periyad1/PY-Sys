import SwiftUI
import Charts

// MARK: - Jaringan / Network

struct NetworkTab: View {
    @ObservedObject var core: AetherCore
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if settings.showPublicIP {
                GroupBox(tr("IP publik", "Public IP")) {
                    HStack {
                        if let p = core.publicIP {
                            Text(p.ip).monospacedDigit().textSelection(.enabled)
                            Text(p.flag)
                        } else {
                            Text(tr("Memuat…", "Loading…")).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { core.refreshPublicIP(force: true) } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless)
                            .help(tr("Segarkan", "Refresh"))
                    }
                    .font(.callout)
                }
            }

            ForEach(core.interfaces.filter { $0.connected }) { i in
                GroupBox {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: i.isWiFi ? "wifi" : "cable.connector")
                                .foregroundStyle(Theme.accent)
                            Text(i.name).bold()
                            Text("(\(i.bsd))").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(tr("Terhubung", "Connected")).foregroundStyle(.green)
                        }
                        ForEach(i.ipv4 + i.ipv6, id: \.self) { a in
                            Text(a).font(.caption.monospaced()).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .font(.callout)
                }
            }

            GroupBox(tr("Lalu lintas", "Traffic")) {
                VStack(spacing: 6) {
                    Chart {
                        ForEach(Array(core.netHistory.enumerated()), id: \.offset) { item in
                            AreaMark(x: .value("t", item.element.date), y: .value("KB/s", item.element.upKBps))
                                .foregroundStyle(Color.red.opacity(0.8))
                            AreaMark(x: .value("t", item.element.date), y: .value("KB/s", -item.element.downKBps))
                                .foregroundStyle(Color.cyan.opacity(0.8))
                        }
                        RuleMark(y: .value("0", 0)).foregroundStyle(Color.secondary.opacity(0.4))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 70)
                    HStack {
                        LegendRow(color: .red, title: tr("Puncak ↑", "Peak ↑"),
                                  value: Fmt.ioRate((core.netHistory.map { $0.upKBps }.max() ?? 0) * 1000))
                        Spacer(minLength: 16)
                        LegendRow(color: .cyan, title: tr("Puncak ↓", "Peak ↓"),
                                  value: Fmt.ioRate((core.netHistory.map { $0.downKBps }.max() ?? 0) * 1000))
                    }
                    HStack {
                        Text("↑").foregroundStyle(.secondary)
                        Text(Fmt.ioRate(core.netUp)).monospacedDigit().bold()
                        Spacer()
                        Text("↓").foregroundStyle(.secondary)
                        Text(Fmt.ioRate(core.netDown)).monospacedDigit().bold()
                    }
                    .font(.callout)
                }
            }

            let off = core.interfaces.filter { !$0.connected }
            if !off.isEmpty {
                GroupBox(tr("Tidak terhubung", "Not connected")) {
                    VStack(spacing: 3) {
                        ForEach(off) { i in
                            HStack {
                                Text("\(i.name) (\(i.bsd))").foregroundStyle(.secondary).lineLimit(1)
                                Spacer()
                                Image(systemName: "network.slash").foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                    }
                }
            }

            GroupBox(tr("Proses", "Processes")) {
                VStack(spacing: 4) {
                    HStack {
                        Spacer()
                        Text("↑").frame(width: 80, alignment: .trailing)
                        Text("↓").frame(width: 80, alignment: .trailing)
                    }
                    .font(.caption.bold()).foregroundStyle(.secondary)
                    if core.netProcs.isEmpty {
                        Text(tr("Memuat… / tidak ada lalu lintas.", "Loading… / no traffic."))
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(core.netProcs) { p in
                        HStack {
                            Text(p.name).lineLimit(1)
                            Spacer()
                            Text(Fmt.ioRate(p.up)).monospacedDigit().frame(width: 80, alignment: .trailing)
                            Text(Fmt.ioRate(p.down)).monospacedDigit().frame(width: 80, alignment: .trailing)
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .onAppear { core.setNetworkVisible(true) }
        .onDisappear { core.setNetworkVisible(false) }
    }
}

// MARK: - Sensor / Sensors

struct SensorsTab: View {
    @ObservedObject var core: AetherCore

    private var s: SensorSnapshot { core.sensors }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox(tr("Kipas", "Fans")) {
                VStack(spacing: 4) {
                    if s.fans.isEmpty {
                        StatRow(title: tr("Kipas", "Fans"), value: tr("tidak terbaca", "not readable"))
                    }
                    ForEach(s.fans) { f in
                        SensorBar(title: tr("Kipas \(f.id + 1)", "Fan \(f.id + 1)"),
                                  value: String(format: "%.0f rpm", f.rpm),
                                  fraction: f.max > 0 ? f.rpm / f.max : 0)
                    }
                    StatRow(title: tr("Kendali", "Control"), value: tr("Otomatis oleh sistem", "System controlled"))
                }
            }

            GroupBox(tr("Suhu", "Temperatures")) {
                VStack(spacing: 4) {
                    if let c = core.cpu.cpuTemp {
                        SensorBar(title: tr("Rata-rata CPU", "CPU average"),
                                  value: String(format: "%.0f°", c), fraction: c / 110)
                    }
                    if s.temps.isEmpty {
                        Text(tr("Sensor suhu tidak tersedia.", "Temperature sensors unavailable."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(s.temps) { t in
                        SensorBar(title: t.name, value: String(format: "%.0f°", t.celsius), fraction: t.celsius / 110)
                    }
                }
            }

            GroupBox(tr("Daya & baterai", "Power & battery")) {
                VStack(spacing: 4) {
                    if let p = s.totalPowerW {
                        SensorBar(title: tr("Daya total", "Total power"),
                                  value: String(format: "%.2f W", p), fraction: p / 60)
                    }
                    if let b = s.battery {
                        if let pct = b.percent {
                            StatRow(title: tr("Baterai", "Battery"),
                                    value: "\(pct)%" + (b.charging ? tr(" · mengisi", " · charging")
                                                         : b.external ? tr(" · adaptor", " · on adapter") : ""))
                        }
                        if let v = b.voltage { SensorBar(title: tr("Tegangan baterai", "Battery voltage"),
                                                         value: String(format: "%.2f V", v), fraction: v / 13) }
                        if let a = b.amperage { SensorBar(title: tr("Arus baterai", "Battery current"),
                                                          value: String(format: "%.2f A", a), fraction: abs(a) / 5) }
                        if let t = b.temperature { SensorBar(title: tr("Suhu baterai", "Battery temperature"),
                                                             value: String(format: "%.0f°", t), fraction: t / 60) }
                        if let c = b.cycles { StatRow(title: tr("Siklus pengisian", "Cycle count"), value: "\(c)") }
                        if let h = b.health { StatRow(title: tr("Kesehatan baterai", "Battery health"),
                                                      value: "\(Int((h * 100).rounded()))%") }
                    }
                }
            }
        }
        .onAppear { core.setSensorsVisible(true) }
        .onDisappear { core.setSensorsVisible(false) }
    }
}

struct SensorBar: View {
    let title: String
    let value: String
    let fraction: Double
    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Text(value).monospacedDigit()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3).fill(Color.cyan)
                        .frame(width: geo.size.width * CGFloat(min(max(fraction, 0.02), 1)))
                }
            }
            .frame(width: 70, height: 10)
        }
        .font(.callout)
    }
}
