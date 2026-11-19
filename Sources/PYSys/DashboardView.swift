import SwiftUI
import Charts

// MARK: - Monitoring › Dashboard

struct DashCard<Content: View>: View {
    let icon: String
    let title: String
    let accessory: String?
    let action: (() -> Void)?
    let content: Content

    init(icon: String, title: String, accessory: String? = nil, action: (() -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.accessory = accessory
        self.action = action
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(.secondary)
                Text(title).font(.headline)
                Spacer()
                if let a = accessory {
                    Text(a).font(.callout).monospacedDigit().foregroundStyle(Theme.accent)
                }
            }
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
        .contentShape(Rectangle())
        .onTapGesture { action?() }
    }
}

struct MiniBar: View {
    let fraction: Double
    let color: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule().fill(color).frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 8)
    }
}

struct DashRow: View {
    let color: Color
    let title: String
    let value: String
    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(title)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }
}

struct DashboardTab: View {
    @ObservedObject var core: AetherCore
    @ObservedObject private var ui = UIState.shared

    private func pct(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))%" } ?? "–" }
    private func go(_ t: AppTab) { ui.tab = t.rawValue }

    var body: some View {
        let c = core.cpu
        let m = core.mem
        let ssdTemp = core.sensors.temps.first { $0.raw.lowercased().contains("nand") }?.celsius
        let fan = core.sensors.fans.first
        let ip = core.interfaces.first { $0.connected }?.ipv4.first
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                DashCard(icon: "cpu", title: "CPU", accessory: c.cpuTemp.map { String(format: "%.1f°C", $0) },
                         action: { go(.cpu) }) {
                    Text(SysInfo.chip).font(.caption).foregroundStyle(.secondary)
                    Chart {
                        ForEach(Array(core.cpuHistory.suffix(60).enumerated()), id: \.offset) { item in
                            AreaMark(x: .value("t", item.element.date), y: .value("%", item.element.system * 100), stacking: .standard)
                                .foregroundStyle(by: .value("k", "System"))
                            AreaMark(x: .value("t", item.element.date), y: .value("%", item.element.user * 100), stacking: .standard)
                                .foregroundStyle(by: .value("k", "User"))
                        }
                    }
                    .chartForegroundStyleScale(["System": Color.red, "User": Color.cyan])
                    .chartLegend(.hidden).chartXAxis(.hidden).chartYAxis(.hidden)
                    .chartYScale(domain: 0...100)
                    .frame(height: 34)
                    DashRow(color: .cyan, title: "User", value: pct(c.user * 100))
                    DashRow(color: .red, title: "System", value: pct(c.system * 100))
                }
                DashCard(icon: "square.stack.3d.up", title: "GPU",
                         accessory: c.gpuCores.map { tr("\($0) core", "\($0) cores") }, action: { go(.cpu) }) {
                    Text(SysInfo.chip).font(.caption).foregroundStyle(.secondary)
                    Chart {
                        ForEach(Array(core.gpuHistory.suffix(60).enumerated()), id: \.offset) { item in
                            AreaMark(x: .value("t", item.element.date), y: .value("%", item.element.device))
                                .foregroundStyle(Color.purple.opacity(0.6))
                        }
                    }
                    .chartXAxis(.hidden).chartYAxis(.hidden)
                    .chartYScale(domain: 0...100)
                    .frame(height: 34)
                    DashRow(color: .purple, title: "Device", value: pct(c.gpu))
                    DashRow(color: .pink, title: "Render", value: pct(c.gpuRenderer))
                    DashRow(color: .teal, title: "Tiler", value: pct(c.gpuTiler))
                }
                DashCard(icon: "internaldrive", title: core.volume?.name ?? "SSD",
                         accessory: ssdTemp.map { String(format: "%.1f°C", $0) }, action: { go(.overview) }) {
                    if let v = core.volume {
                        HStack {
                            Text("U: \(Fmt.disk(v.total - v.free))")
                            Spacer()
                            Text("T: \(Fmt.disk(v.total))")
                        }
                        .font(.caption).monospacedDigit()
                        MiniBar(fraction: Double(v.total - v.free) / Double(max(v.total, 1)), color: .blue)
                    }
                    HStack {
                        Text("R: \(Fmt.ioRate(core.diskReadRate))")
                        Spacer()
                        Text("W: \(Fmt.ioRate(core.diskWriteRate))")
                    }
                    .font(.caption).monospacedDigit()
                    Button(tr("Detail ›", "Details ›")) { go(.overview) }
                        .buttonStyle(.borderless).font(.caption)
                }
                DashCard(icon: "memorychip", title: "RAM", accessory: m.pressure.label, action: { go(.ram) }) {
                    HStack {
                        Text("U: \(Fmt.bytes(m.used))")
                        Spacer()
                        Text("T: \(Fmt.bytes(m.total))")
                    }
                    .font(.caption).monospacedDigit()
                    MiniBar(fraction: m.usedFraction, color: m.pressure.color)
                    Text("Swap: \(Fmt.bytes(m.swapUsed))").font(.caption).foregroundStyle(.secondary)
                    Button(tr("Bebaskan RAM", "Free up RAM")) { core.freeUpRAM() }
                        .controlSize(.small)
                        .help(tr("Bekukan sekarang semua app idle yang tidak terlihat", "Freeze every idle, hidden app now"))
                }
                DashCard(icon: "fanblades", title: tr("Kipas", "Fan"), action: { go(.sensors) }) {
                    Text(fan.map { String(format: "%.0f RPM", $0.rpm) } ?? tr("Tidak terbaca", "Not readable"))
                        .font(.title3).monospacedDigit()
                    Text(tr("Diatur otomatis oleh sistem", "System controlled")).font(.caption).foregroundStyle(.secondary)
                    if let t = c.cpuTemp {
                        Text(tr("CPU \(Int(t.rounded()))°C · \(c.thermal.label)", "CPU \(Int(t.rounded()))°C · \(c.thermal.label)"))
                            .font(.caption).foregroundStyle(c.thermal.color)
                    }
                }
                DashCard(icon: "globe", title: "Internet", accessory: "›", action: { go(.network) }) {
                    HStack {
                        Label(Fmt.ioRate(core.netDown), systemImage: "arrow.down")
                        Spacer()
                        Label(Fmt.ioRate(core.netUp), systemImage: "arrow.up")
                    }
                    .font(.caption).monospacedDigit()
                    if let ip {
                        Text(ip).font(.callout).monospacedDigit().foregroundStyle(Theme.accent)
                            .textSelection(.enabled)
                    }
                }
            }
            if let msg = core.freeUpMessage {
                Text(msg).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let b = c.bootDate {
                StatRow(title: tr("Waktu menyala", "Boot time"), value: Fmt.duration(Date().timeIntervalSince(b)))
            }
        }
        .onAppear { core.setSensorsVisible(true) }
        .onDisappear { core.setSensorsVisible(false) }
    }
}
