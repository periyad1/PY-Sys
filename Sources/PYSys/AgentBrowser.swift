import AppKit
import SwiftUI
import Darwin
import IOKit.ps

// MARK: - Argumen proses (KERN_PROCARGS2)

enum ProcArgs {
    /// Baris perintah lengkap sebuah proses milik user ini. Kosong bila tidak bisa dibaca.
    static func args(_ pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        let argc = buf.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        var i = MemoryLayout<Int32>.size
        while i < size && buf[i] != 0 { i += 1 }      // lewati path executable
        while i < size && buf[i] == 0 { i += 1 }      // lewati padding
        var out: [String] = []
        var start = i
        while i < size && out.count < argc {
            if buf[i] == 0 {
                out.append(String(decoding: buf[start..<i], as: UTF8.self))
                start = i + 1
            }
            i += 1
        }
        return out
    }
}

// MARK: - Agen AI

struct AgentProc: Identifiable {
    let id: pid_t
    let kind: String
    let detail: String
    let footprint: UInt64
    let cpu: Double
    let busyMinutes: Int
    let paused: Bool
}

final class AgentMonitor: ObservableObject {
    static let shared = AgentMonitor()

    @Published private(set) var agents: [AgentProc] = []
    @Published private(set) var paused: Set<pid_t> = [] { didSet { savePaused() } }

    /// Daftar agen yang dijeda disimpan ke disk, supaya bila PY-Sys crash agen itu dilanjutkan saat PY-Sys dibuka lagi.
    private static let pausedURL: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PY-Sys", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("paused-agents.json")
    }()

    private func savePaused() {
        if paused.isEmpty { try? FileManager.default.removeItem(at: Self.pausedURL); return }
        if let d = try? JSONEncoder().encode(Array(paused)) { try? d.write(to: Self.pausedURL, options: .atomic) }
    }

    /// Dipanggil saat PY-Sys mulai: lanjutkan agen yang tertinggal dalam keadaan dijeda.
    func recoverAfterCrash() {
        guard let d = try? Data(contentsOf: Self.pausedURL), let pids = try? JSONDecoder().decode([pid_t].self, from: d) else { return }
        for pid in pids { _ = kill(pid, SIGCONT) }   // SIGCONT ke proses yang tidak dijeda tidak berpengaruh
        try? FileManager.default.removeItem(at: Self.pausedURL)
    }

    private var busySeconds: [pid_t: Double] = [:]
    private var alerted: Set<pid_t> = []
    private var argCache: [pid_t: [String]] = [:]

    /// Nama proses yang hampir pasti agen AI / model lokal / runtime-nya.
    private static let candidates: Set<String> = [
        "node", "python", "python3", "bun", "deno", "uv", "uvx",
        "ollama", "ollama_llama_server", "llama-server", "llama-cli", "llamafile", "mlx_lm.server",
        "claude", "codex", "gemini", "aider", "goose", "opencode", "cursor-agent", "amp", "qwen",
        "lms", "LM Studio", "com.docker.backend", "com.docker.virtualization", "qemu-system-aarch64",
    ]

    private static func label(name: String, path: String, args: [String]) -> (kind: String, detail: String)? {
        let n = name.lowercased()
        let joined = args.joined(separator: " ").lowercased()
        let short = args.dropFirst().first { !$0.hasPrefix("-") }.map { ($0 as NSString).lastPathComponent } ?? ""
        func has(_ s: String) -> Bool { joined.contains(s) || n.contains(s) }

        if n.hasPrefix("ollama") { return ("Ollama", n == "ollama" ? "server" : tr("model sedang jalan", "model running")) }
        if n.hasPrefix("llama") || n == "llamafile" { return ("llama.cpp", short) }
        if has("mlx_lm") || has("mlx-lm") { return ("MLX", "mlx_lm") }
        if path.contains("LM Studio") || n == "lms" { return ("LM Studio", name) }
        if n.hasPrefix("com.docker") || n.hasPrefix("qemu") { return ("Docker", name) }
        if has("claude") && !path.contains("Claude.app") { return ("Claude Code", short) }
        if has("codex") { return ("Codex CLI", short) }
        if has("gemini") { return ("Gemini CLI", short) }
        if has("aider") { return ("Aider", short) }
        if has("goose") { return ("Goose", short) }
        if has("opencode") { return ("OpenCode", short) }
        if has("cursor-agent") { return ("Cursor Agent", short) }
        if has("qwen") { return ("Qwen Code", short) }
        if has("modelcontextprotocol") || has("mcp-server") || has(" mcp") { return ("MCP server", short) }
        for fw in ["langgraph", "langchain", "crewai", "autogen", "openhands", "smolagents", "llamaindex", "vllm", "transformers", "torch"] where has(fw) {
            return (fw.capitalized, short)
        }
        if n.hasPrefix("python") || n == "uv" || n == "uvx" { return ("Python", short) }
        if n == "node" || n == "bun" || n == "deno" { return (name.capitalized, short) }
        return nil
    }

    func update(samples: [pid_t: ProcSample], cpu: [pid_t: Double], threshold: Double, minutes: Int, interval: Double) {
        var list: [AgentProc] = []
        var seen: Set<pid_t> = []
        let needSeconds = Double(max(1, minutes) * 60)
        for (pid, s) in samples where Self.candidates.contains(s.name) || Self.candidates.contains((s.path as NSString).lastPathComponent) {
            let args = argCache[pid] ?? ProcArgs.args(pid)
            argCache[pid] = args
            guard let l = Self.label(name: s.name, path: s.path, args: args) else { continue }
            seen.insert(pid)
            let c = cpu[pid] ?? 0
            busySeconds[pid] = c >= threshold && !paused.contains(pid) ? (busySeconds[pid] ?? 0) + interval : 0
            let busyMin = Int((busySeconds[pid] ?? 0) / 60)
            if (busySeconds[pid] ?? 0) >= needSeconds && !alerted.contains(pid) {
                alerted.insert(pid)
                Notifier.post(title: tr("Agen AI terus memakai CPU", "AI agent keeps using CPU"),
                              body: tr("\(l.kind) (PID \(pid)) memakai CPU \(Int(c))% selama \(busyMin) menit. Jeda atau hentikan di PY-Sys › Agen AI.",
                                       "\(l.kind) (PID \(pid)) has used \(Int(c))% CPU for \(busyMin) min. Pause or stop it in PY-Sys › AI Agents."))
            }
            list.append(AgentProc(id: pid, kind: l.kind, detail: l.detail.isEmpty ? s.name : l.detail,
                                  footprint: s.footprint, cpu: c, busyMinutes: busyMin,
                                  paused: paused.contains(pid)))
        }
        for pid in Array(argCache.keys) where samples[pid] == nil { argCache[pid] = nil }
        for pid in Array(busySeconds.keys) where !seen.contains(pid) {
            busySeconds[pid] = nil
            alerted.remove(pid)
            paused.remove(pid)
        }
        agents = list.sorted { $0.footprint > $1.footprint }
    }

    func pause(_ pid: pid_t) {
        if kill(pid, SIGSTOP) == 0 { paused.insert(pid); refreshPausedFlag(pid, true) }
    }

    func resume(_ pid: pid_t) {
        _ = kill(pid, SIGCONT)
        paused.remove(pid)
        refreshPausedFlag(pid, false)
    }

    func stop(_ pid: pid_t) {
        if paused.contains(pid) { _ = kill(pid, SIGCONT) }
        _ = kill(pid, SIGTERM)
        paused.remove(pid)
        agents.removeAll { $0.id == pid }
    }

    /// Dipanggil saat PY-Sys keluar: jangan tinggalkan agen dalam keadaan dijeda.
    func resumeAll() {
        for pid in paused { _ = kill(pid, SIGCONT) }
        paused.removeAll()
    }

    private func refreshPausedFlag(_ pid: pid_t, _ on: Bool) {
        agents = agents.map { a in
            a.id == pid ? AgentProc(id: a.id, kind: a.kind, detail: a.detail, footprint: a.footprint,
                                    cpu: a.cpu, busyMinutes: a.busyMinutes, paused: on) : a
        }
    }
}

struct AgentsTab: View {
    @ObservedObject var settings: Settings
    @ObservedObject private var mon = AgentMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let total = mon.agents.reduce(UInt64(0)) { $0 + $1.footprint }
            let cpu = mon.agents.reduce(0.0) { $0 + $1.cpu }
            HStack(spacing: 10) {
                DashStat(title: tr("Proses agen", "Agent processes"), value: "\(mon.agents.count)")
                DashStat(title: "RAM", value: Fmt.bytes(total))
                DashStat(title: "CPU", value: "\(Int(cpu))%")
            }

            if mon.agents.isEmpty {
                Text(tr("Tidak ada agen AI, model lokal, atau skrip Node/Python yang berjalan.",
                        "No AI agents, local models or Node/Python scripts are running."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(mon.agents) { a in
                HStack(spacing: 8) {
                    Image(systemName: a.paused ? "pause.circle.fill" : (a.busyMinutes > 0 ? "flame" : "sparkles"))
                        .foregroundStyle(a.paused ? Color.blue : (a.busyMinutes > 0 ? Color.orange : Color.secondary))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.kind).font(.callout.bold())
                        Text("\(a.detail) · PID \(a.id)").font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Fmt.bytes(a.footprint)).font(.caption.monospacedDigit())
                        Text("CPU \(Int(a.cpu))%").font(.caption2.monospacedDigit())
                            .foregroundStyle(a.cpu >= settings.agentCPU ? Color.orange : Color.secondary)
                    }
                    .frame(width: 80, alignment: .trailing)
                    Button {
                        a.paused ? mon.resume(a.id) : mon.pause(a.id)
                    } label: { Image(systemName: a.paused ? "play.fill" : "pause.fill") }
                        .buttonStyle(.borderless)
                        .help(a.paused ? tr("Lanjutkan", "Resume") : tr("Jeda (SIGSTOP)", "Pause (SIGSTOP)"))
                    Button {
                        let al = NSAlert()
                        al.messageText = tr("Hentikan \(a.kind) (PID \(a.id))?", "Stop \(a.kind) (PID \(a.id))?")
                        al.informativeText = tr("Proses diminta berhenti (SIGTERM). Pekerjaan yang belum disimpan bisa hilang.",
                                                "The process is asked to quit (SIGTERM). Unsaved work may be lost.")
                        al.addButton(withTitle: tr("Hentikan", "Stop"))
                        al.addButton(withTitle: tr("Batal", "Cancel"))
                        NSApp.activate(ignoringOtherApps: true)
                        if al.runModal() == .alertFirstButtonReturn { mon.stop(a.id) }
                    } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.borderless)
                        .help(tr("Hentikan", "Stop"))
                }
                Divider()
            }

            GroupBox(tr("Peringatan agen macet", "Runaway agent alert")) {
                VStack(alignment: .leading, spacing: 6) {
                    Stepper(String(format: tr("Batas CPU: %.0f%%", "CPU limit: %.0f%%"), settings.agentCPU),
                            value: $settings.agentCPU, in: 30...300, step: 10)
                    Stepper(tr("Selama \(settings.agentMinutes) menit", "For \(settings.agentMinutes) minutes"),
                            value: $settings.agentMinutes, in: 1...60)
                    Text(tr("100% = satu inti penuh. Data diperbarui tiap 15 detik (30 detik saat panel tertutup). Agen yang dijeda otomatis dilanjutkan saat PY-Sys ditutup.",
                            "100% = one full core. Updated every 15 seconds (30 when the panel is closed). Paused agents are resumed when PY-Sys quits."))
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
            }
        }
    }
}

struct DashStat: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - Browser

struct BrowserProc: Identifiable {
    let id: pid_t
    let role: String
    let footprint: UInt64
    let cpu: Double
}

struct RoleUse: Identifiable {
    let id: String
    let bytes: UInt64
}

struct BrowserUsage: Identifiable {
    let id: String            // bundle ID
    let name: String
    let icon: NSImage?
    let footprint: UInt64
    let cpu: Double
    let tabs: Int?            // dari AppleScript (nil = tidak bisa dihitung)
    let renderers: Int
    let extensions: Int
    let roles: [RoleUse]
    let heaviest: [BrowserProc]
}

final class BrowserMonitor: ObservableObject {
    static let shared = BrowserMonitor()

    @Published private(set) var browsers: [BrowserUsage] = []
    @Published private(set) var tabCounts: [String: Int] = [:]
    @Published var note: String?

    private var argCache: [pid_t: [String]] = [:]
    var visible = false

    static let known: [String: (name: String, script: String?)] = [
        "com.google.Chrome": ("Google Chrome", "Google Chrome"),
        "com.google.Chrome.beta": ("Chrome Beta", "Google Chrome Beta"),
        "com.microsoft.edgemac": ("Microsoft Edge", "Microsoft Edge"),
        "com.brave.Browser": ("Brave", "Brave Browser"),
        "com.vivaldi.Vivaldi": ("Vivaldi", "Vivaldi"),
        "com.operasoftware.Opera": ("Opera", "Opera"),
        "company.thebrowser.Browser": ("Arc", "Arc"),
        "com.apple.Safari": ("Safari", "Safari"),
        "org.mozilla.firefox": ("Firefox", nil),
    ]

    private func role(of s: ProcSample, args: [String]) -> String {
        let a = args.joined(separator: " ")
        if a.contains("--type=renderer") { return a.contains("--extension-process") ? "ext" : "tab" }
        if a.contains("--type=gpu-process") { return "gpu" }
        if a.contains("--type=utility") || a.contains("--type=") { return "util" }
        let n = s.name
        if n.contains("WebContent") { return "tab" }
        if n.contains("WebKit.GPU") { return "gpu" }
        if n.contains("WebKit.Networking") { return "util" }
        if a.contains("-contentproc") { return a.contains(" tab") ? "tab" : (a.contains("extension") ? "ext" : "util") }
        return "main"
    }

    static func roleTitle(_ r: String) -> String {
        switch r {
        case "tab": return tr("Tab / halaman", "Tabs / pages")
        case "ext": return tr("Ekstensi", "Extensions")
        case "gpu": return "GPU"
        case "util": return tr("Utilitas & jaringan", "Utility & network")
        default: return tr("Proses utama", "Main process")
        }
    }

    func update(groups: [AppGroup], samples: [pid_t: ProcSample], cpu: [pid_t: Double]) {
        guard visible else { return }
        var out: [BrowserUsage] = []
        var alive: Set<pid_t> = []
        for g in groups {
            guard let b = g.bundleID, let info = Self.known[b] else { continue }
            var roles: [String: UInt64] = [:]
            var procs: [BrowserProc] = []
            var renderers = 0, exts = 0
            for pid in g.pids {
                guard let s = samples[pid] else { continue }
                alive.insert(pid)
                let args = argCache[pid] ?? ProcArgs.args(pid)
                argCache[pid] = args
                let r = role(of: s, args: args)
                roles[r, default: 0] += s.footprint
                if r == "tab" { renderers += 1 }
                if r == "ext" { exts += 1 }
                procs.append(BrowserProc(id: pid, role: r, footprint: s.footprint, cpu: cpu[pid] ?? 0))
            }
            let order = ["tab", "ext", "gpu", "main", "util"]
            out.append(BrowserUsage(id: b, name: info.name, icon: g.icon, footprint: g.footprint, cpu: g.cpu,
                                    tabs: tabCounts[b], renderers: renderers, extensions: exts,
                                    roles: order.compactMap { k in roles[k].map { RoleUse(id: k, bytes: $0) } },
                                    heaviest: Array(procs.filter { $0.role == "tab" }.sorted { $0.footprint > $1.footprint }.prefix(5))))
        }
        for pid in Array(argCache.keys) where !alive.contains(pid) { argCache[pid] = nil }
        browsers = out.sorted { $0.footprint > $1.footprint }
    }

    /// Hitung tab lewat AppleScript (butuh izin Automation untuk tiap browser). Hanya browser yang sedang jalan.
    func countTabs() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let targets = Self.known.filter { running.contains($0.key) && $0.value.script != nil }
        DispatchQueue.main.async {
            var counts: [String: Int] = [:]
            var failed: [String] = []
            for (bid, info) in targets {
                let src = """
                tell application "\(info.script!)"
                    set n to 0
                    repeat with w in windows
                        set n to n + (count of tabs of w)
                    end repeat
                    return n
                end tell
                """
                var err: NSDictionary?
                if let r = NSAppleScript(source: src)?.executeAndReturnError(&err), err == nil {
                    counts[bid] = Int(r.int32Value)
                } else {
                    failed.append(info.name)
                }
            }
            DispatchQueue.main.async {
                self.tabCounts = counts
                self.note = failed.isEmpty ? nil :
                    tr("Tab \(failed.joined(separator: ", ")) belum bisa dihitung. Izinkan PY-Sys di Privacy & Security → Automation.",
                       "Couldn't count tabs in \(failed.joined(separator: ", ")). Allow PY-Sys in Privacy & Security → Automation.")
                AetherCore.shared.refreshBrowsers()
            }
        }
    }
}

struct BrowserTab: View {
    @ObservedObject private var mon = BrowserMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("Diperbarui tiap 15 detik", "Updated every 15 seconds")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(tr("Hitung tab", "Count tabs")) { mon.countTabs() }.controlSize(.small)
            }
            if mon.browsers.isEmpty {
                Text(tr("Tidak ada browser yang sedang berjalan.", "No browser is running."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(mon.browsers) { b in
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            if let i = b.icon { Image(nsImage: i).resizable().frame(width: 22, height: 22) }
                            Text(b.name).font(.callout.bold())
                            Spacer()
                            Text(Fmt.bytes(b.footprint)).font(.callout.bold().monospacedDigit())
                        }
                        HStack(spacing: 12) {
                            Label(b.tabs.map { tr("\($0) tab", "\($0) tabs") } ?? tr("? tab", "? tabs"), systemImage: "square.on.square")
                            Label(tr("\(b.renderers) proses halaman", "\(b.renderers) page processes"), systemImage: "doc.richtext")
                            Label("CPU \(Int(b.cpu))%", systemImage: "cpu")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        if let t = b.tabs, t > 0 {
                            let tabRAM = b.roles.first { $0.id == "tab" }?.bytes ?? 0
                            Text(tr("Rata-rata ±\(Fmt.bytes(tabRAM / UInt64(t))) per tab", "About \(Fmt.bytes(tabRAM / UInt64(t))) per tab on average"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        ForEach(b.roles) { r in
                            HStack {
                                Text(BrowserMonitor.roleTitle(r.id) + (r.id == "ext" ? " (\(b.extensions))" : ""))
                                Spacer()
                                Text(Fmt.bytes(r.bytes)).monospacedDigit()
                            }
                            .font(.caption)
                            ProgressView(value: Double(r.bytes), total: Double(max(b.footprint, 1)))
                                .progressViewStyle(.linear)
                        }
                        if !b.heaviest.isEmpty {
                            Text(tr("Proses halaman terberat", "Heaviest page processes")).font(.caption.bold()).padding(.top, 2)
                            ForEach(b.heaviest) { p in
                                HStack {
                                    Text("PID \(p.id)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("CPU \(Int(p.cpu))%").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                    Text(Fmt.bytes(p.footprint)).font(.caption2.monospacedDigit()).frame(width: 70, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }
            if let n = mon.note {
                Text(n).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Text(tr("Satu proses halaman bisa menampung beberapa tab dari situs yang sama, jadi macOS tidak bisa menunjukkan RAM per tab secara persis. Untuk itu buka Task Manager browser (Chrome/Edge/Brave: Shift + Esc).",
                    "One page process can host several tabs from the same site, so macOS can't show exact RAM per tab. For that, open the browser's Task Manager (Chrome/Edge/Brave: Shift + Esc)."))
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            mon.visible = true
            AetherCore.shared.refreshBrowsers()
        }
        .onDisappear { mon.visible = false }
    }
}

// MARK: - Widget menu bar

enum BarItem: String, CaseIterable, Identifiable {
    case ram, pressure, cpu, temp, net, swap, agents, frozen, battery, disk
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ram: return "RAM %"
        case .pressure: return tr("Titik warna tekanan memori", "Memory pressure dot")
        case .cpu: return "CPU %"
        case .temp: return tr("Suhu CPU", "CPU temperature")
        case .net: return tr("Jaringan ↓↑", "Network ↓↑")
        case .swap: return "Swap"
        case .agents: return tr("Jumlah agen AI", "AI agent count")
        case .frozen: return tr("Jumlah app beku ❄︎", "Frozen app count ❄︎")
        case .battery: return tr("Baterai (% dan sisa waktu)", "Battery (% and time left)")
        case .disk: return tr("Ruang disk tersisa", "Free disk space")
        }
    }
}

/// Baterai untuk menu bar, dibaca lewat IOPowerSources (ringan).
struct BarBattery: Equatable {
    var percent: Int
    var charging: Bool
    var onAC: Bool
    var minutesLeft: Int?

    static func read() -> BarBattery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let cur = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let onAC = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let tte = d[kIOPSTimeToEmptyKey] as? Int ?? -1
            return BarBattery(percent: Int((Double(cur) / Double(max) * 100).rounded()),
                              charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                              onAC: onAC, minutesLeft: (!onAC && tte > 0) ? tte : nil)
        }
        return nil
    }

    var text: String {
        var s = (charging || onAC ? "⚡︎" : "Bat ") + "\(percent)%"
        if let m = minutesLeft { s += String(format: " %d:%02d", m / 60, m % 60) }
        return s
    }
}

/// Titik warna (bukan template) agar warnanya tetap tampil di menu bar.
enum PressureDot {
    private static var cache: [Int: NSImage] = [:]
    static func image(_ level: PressureLevel) -> NSImage {
        if let i = cache[level.rawValue] { return i }
        let color: NSColor = level == .normal ? .systemGreen : (level == .warning ? .systemYellow : .systemRed)
        let img = NSImage(size: NSSize(width: 9, height: 9), flipped: false) { r in
            color.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        img.isTemplate = false
        cache[level.rawValue] = img
        return img
    }
}

enum BarFmt {
    static func rate(_ b: Double) -> String {
        if b < 1_000 { return "0K" }
        if b < 1_000_000 { return String(format: "%.0fK", b / 1_000) }
        return String(format: "%.1fM", b / 1_000_000)
    }
    static func gb(_ b: UInt64) -> String { String(format: "%.1fG", Double(b) / 1_073_741_824) }
}
