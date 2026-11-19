import AppKit
import SwiftUI
import CoreText
import UniformTypeIdentifiers

// MARK: - Ekspor laporan sistem ke PDF

enum SystemReport {
    private static func h(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s + "\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.black])
    }
    private static func row(_ k: String, _ v: String) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.tabStops = [NSTextTab(textAlignment: .left, location: 200)]
        return NSAttributedString(string: "\(k)\t\(v)\n", attributes: [.font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: NSColor.black, .paragraphStyle: p])
    }
    private static let gap = NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 6)])

    static func build() -> NSAttributedString {
        let core = AetherCore.shared
        let out = NSMutableAttributedString()
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .short
        df.locale = Locale(identifier: AppLanguage.isEnglish ? "en_US" : "id_ID")
        out.append(NSAttributedString(string: tr("Laporan Sistem Mac", "Mac System Report") + "\n",
                                      attributes: [.font: NSFont.boldSystemFont(ofSize: 20), .foregroundColor: NSColor.black]))
        out.append(NSAttributedString(string: "PY-Sys \(AppInfo.version) · \(df.string(from: Date()))\n\n",
                                      attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.darkGray]))

        out.append(h(tr("Perangkat", "Hardware")))
        out.append(row(tr("Model", "Model"), SysInfo.model))
        out.append(row("Chip", "\(SysInfo.chip) (\(SysInfo.cores))"))
        out.append(row("RAM", SysInfo.ram))
        out.append(row("macOS", SysInfo.macOS))
        if let b = core.cpu.bootDate {
            out.append(row(tr("Menyala sejak", "Up since"), df.string(from: b) + " (" + Fmt.duration(Date().timeIntervalSince(b)) + ")"))
        }
        out.append(row(tr("Monitor", "Displays"), NSScreen.screens.map { "\($0.localizedName) \(Int($0.frame.width))×\(Int($0.frame.height))" }.joined(separator: ", ")))
        out.append(gap)

        let m = core.mem
        out.append(h(tr("Memori saat ini", "Memory now")))
        out.append(row(tr("Terpakai", "Used"), "\(Int(m.usedFraction * 100))%"))
        out.append(row(tr("Tekanan memori", "Memory pressure"), "\(m.pressure.label) (\(Int(m.pressureFraction * 100))%)"))
        out.append(row("App / Wired / Compressed", "\(Fmt.bytes(m.app)) / \(Fmt.bytes(m.wired)) / \(Fmt.bytes(m.compressed))"))
        out.append(row("Swap", Fmt.bytes(m.swapUsed)))
        let hist = HistoryStore.shared.samples.filter { Date().timeIntervalSince($0.t) <= 86_400 }
        if !hist.isEmpty {
            let avg = { (f: (HSample) -> Float) in Double(hist.map(f).reduce(0, +)) / Double(hist.count) }
            out.append(row(tr("Rata-rata 24 jam: RAM / swap", "24-hour average: RAM / swap"),
                           String(format: "%.0f%% / %.1f GB", avg { $0.ram }, avg { $0.swap })))
            out.append(row(tr("Puncak swap 24 jam", "24-hour peak swap"), String(format: "%.1f GB", Double(hist.map(\.swap).max() ?? 0))))
        }
        out.append(gap)

        out.append(h("CPU"))
        out.append(row(tr("Beban sekarang", "Load now"), "\(Int((1 - core.cpu.idle) * 100))%"))
        out.append(row("Load average", core.cpu.load.map { String(format: "%.2f", $0) }.joined(separator: " · ")))
        if let t = core.cpu.cpuTemp { out.append(row(tr("Suhu CPU", "CPU temperature"), String(format: "%.0f °C", t))) }
        out.append(gap)

        out.append(h(tr("Penyimpanan", "Storage")))
        if let v = core.volume {
            out.append(row(v.name, tr("\(Fmt.disk(v.free)) kosong dari \(Fmt.disk(v.total))", "\(Fmt.disk(v.free)) free of \(Fmt.disk(v.total))")))
        }
        if let s = core.ssd {
            if let p = s.percentUsed { out.append(row(tr("Keausan SSD", "SSD wear"), "\(p)%")) }
            if let w = s.written { out.append(row(tr("Total ditulis", "Total written"), w)) }
            if let a = s.availableSpare { out.append(row("Available spare", "\(a)%")) }
            if let h = s.powerOnHours { out.append(row("Power-on hours", "\(h)")) }
        }
        let days = HistoryStore.shared.days(14).filter { $0.bytes > 0 }
        if !days.isEmpty {
            let avg = Double(days.reduce(UInt64(0)) { $0 + $1.bytes }) / Double(days.count) / 1e9
            out.append(row(tr("Rata-rata tulis SSD per hari", "Average SSD writes per day"), String(format: "%.1f GB", avg)))
        }
        out.append(gap)

        let ab = AppleBatteryInfo.shared
        if let b = SensorReader.battery() {
            out.append(h(tr("Baterai", "Battery")))
            if let c = ab.cycles ?? b.cycles { out.append(row(tr("Siklus pengisian", "Cycle count"), "\(c)")) }
            if let mx = ab.maxCapacity ?? b.health.map({ $0 * 100 }) { out.append(row(tr("Kapasitas maksimum", "Maximum capacity"), String(format: "%.0f%%", mx))) }
            if let cond = ab.condition { out.append(row(tr("Kondisi", "Condition"), cond)) }
            out.append(gap)
        }

        out.append(h(tr("Aplikasi pemakai RAM terbesar", "Top apps by memory")))
        for g in core.groups.prefix(10) { out.append(row(g.name, Fmt.bytes(g.footprint))) }
        let agents = AgentMonitor.shared.agents
        if !agents.isEmpty {
            out.append(gap)
            out.append(h(tr("Agen AI yang berjalan", "AI agents running")))
            for a in agents.prefix(10) { out.append(row("\(a.kind) (PID \(a.id))", Fmt.bytes(a.footprint))) }
        }
        let advice = HistoryStore.shared.advice
        if !advice.isEmpty {
            out.append(gap)
            out.append(h(tr("Saran", "Recommendations")))
            for a in advice { out.append(NSAttributedString(string: "• \(a)\n", attributes: [.font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: NSColor.black])) }
        }
        out.append(NSAttributedString(string: "\n\(AppInfo.name) · \(AppInfo.author) · \(AppInfo.email)\n",
                                      attributes: [.font: NSFont.systemFont(ofSize: 8.5), .foregroundColor: NSColor.gray]))
        return out
    }

    /// Tulis teks ke PDF A4, berhalaman bila perlu.
    static func pdf(_ text: NSAttributedString, to url: URL) -> Bool {
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &page, nil) else { return false }
        let setter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        var start = 0
        let frameRect = page.insetBy(dx: 50, dy: 56)
        repeat {
            ctx.beginPDFPage(nil)
            let path = CGPath(rect: frameRect, transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: start, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            let visible = CTFrameGetVisibleStringRange(frame)
            ctx.endPDFPage()
            if visible.length == 0 { break }
            start += visible.length
        } while start < text.length
        ctx.closePDF()
        return true
    }

    static func export() {
        AppleBatteryInfo.shared.refresh(force: false)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmm"
        let p = NSSavePanel()
        p.nameFieldStringValue = "PY-Sys-Report-\(df.string(from: Date())).pdf"
        p.allowedContentTypes = [.pdf]
        p.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return }
        if pdf(build(), to: url) { NSWorkspace.shared.open(url) }
    }
}

// MARK: - Jendela "Tentang & fitur"

enum FeatureCatalog {
    struct Item: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let detail: String
        let since: String
    }
    struct Section: Identifiable {
        let id = UUID()
        let title: String
        let items: [Item]
    }

    /// Versi terbaru yang menambah fitur (diberi label BARU di jendela Tentang).
    static var newestFeature: String {
        sections.flatMap { $0.items.map(\.since) }.max { Updater.newer($1, than: $0) } ?? ""
    }

    static var sections: [Section] {
        [
            Section(title: "Monitoring", items: [
                Item(symbol: "rectangle.grid.2x2", title: "Dashboard", detail: tr("Ringkasan CPU, GPU, disk, RAM, kipas, internet dalam satu layar.", "CPU, GPU, disk, RAM, fan and network at a glance."), since: "1.0"),
                Item(symbol: "memorychip", title: "RAM", detail: tr("Tekanan memori, komposisi, swap, page-in/out, grafik 10 menit.", "Memory pressure, composition, swap, page-ins/outs, 10-minute charts."), since: "1.0"),
                Item(symbol: "cpu", title: "CPU & GPU", detail: tr("Beban per inti (P/E di Apple Silicon), suhu, GPU, load average, proses teratas.", "Per-core load (P/E on Apple Silicon), temperature, GPU, load average, top processes."), since: "1.0"),
                Item(symbol: "network", title: tr("Jaringan & Sensor", "Network & Sensors"), detail: tr("Kecepatan, antarmuka, IP publik; suhu, kipas, daya, baterai.", "Speed, interfaces, public IP; temperatures, fans, power, battery."), since: "1.0"),
                Item(symbol: "sparkles", title: tr("Agen AI", "AI Agents"), detail: tr("Claude Code, Codex, Gemini, Ollama, MLX, Node/Python: RAM, CPU, jeda/hentikan, peringatan macet.", "Claude Code, Codex, Gemini, Ollama, MLX, Node/Python: RAM, CPU, pause/stop, runaway alerts."), since: "1.2"),
                Item(symbol: "globe", title: "Browser", detail: tr("RAM per browser dirinci tab, ekstensi, GPU; jumlah tab.", "RAM per browser split into tabs, extensions, GPU; tab count."), since: "1.2"),
                Item(symbol: "clock.arrow.circlepath", title: tr("Riwayat", "History"), detail: tr("Grafik 24 jam/7 hari, tulis SSD per hari, perkiraan umur SSD, saran restart.", "24-hour/7-day charts, daily SSD writes, SSD life estimate, restart advice."), since: "1.3"),
            ]),
            Section(title: "Cleaner", items: [
                Item(symbol: "square.grid.2x2", title: tr("Aplikasi", "Apps"), detail: tr("Pemakaian RAM per aplikasi, bekukan atau tutup.", "Memory per app, freeze or quit."), since: "1.0"),
                Item(symbol: "snowflake", title: "Cryo-Sleep", detail: tr("Membekukan app idle yang tidak terlihat; cair otomatis saat dibuka.", "Freezes idle, hidden apps; thaws automatically when opened."), since: "1.0"),
                Item(symbol: "scope", title: tr("Mode fokus", "Focus mode"), detail: tr("Profil kerja yang membekukan app di luar profil dengan satu klik.", "Work profiles that freeze everything outside the profile in one click."), since: "1.3"),
                Item(symbol: "moon.zzz", title: tr("Tab browser", "Browser tabs"), detail: tr("Simpan & tutup tab, tutup duplikat, buka lagi kapan saja.", "Save & close tabs, close duplicates, reopen anytime."), since: "1.3"),
                Item(symbol: "internaldrive", title: tr("Penyimpanan", "Storage"), detail: tr("Cache, log, cache developer, Sampah, unduhan lama.", "Caches, logs, developer caches, Trash, old downloads."), since: "1.0"),
                Item(symbol: "trash.square", title: "Uninstaller", detail: tr("Hapus aplikasi beserta file sisanya di ~/Library.", "Remove apps along with their leftovers in ~/Library."), since: "1.5"),
                Item(symbol: "doc.on.doc", title: tr("File besar & duplikat", "Large & duplicate files"), detail: tr("Temukan file besar dan salinan identik, pindahkan ke Sampah.", "Find large files and identical copies, move them to the Trash."), since: "1.5"),
            ]),
            Section(title: "Utility", items: [
                Item(symbol: "switch.2", title: tr("Toggle cepat", "Quick toggles"), detail: tr("Tutup semua app, tetap terjaga, kunci layar, Dark Mode, Dock, dll.", "Quit all apps, keep awake, lock screen, Dark Mode, Dock and more."), since: "1.0"),
                Item(symbol: "cursorarrow.click.2", title: tr("Klik Kanan+", "Right-Click+"), detail: tr("Menu Finder tambahan: file baru, salin path, pindah ke, warna folder…", "Extra Finder menu: new file, copy path, move to, folder colors…"), since: "1.1"),
                Item(symbol: "macwindow.on.rectangle", title: tr("Jendela", "Windows"), detail: tr("Snap jendela dengan ⌃⌥, pindah monitor, simpan tata letak dua monitor.", "Snap windows with ⌃⌥, move between displays, save dual-monitor layouts."), since: "1.4"),
                Item(symbol: "doc.on.clipboard", title: "Clipboard", detail: tr("Riwayat salin dengan ⌃⌥V, item yang disematkan.", "Copy history with ⌃⌥V, pinned items."), since: "1.4"),
                Item(symbol: "sun.max", title: tr("Monitor", "Displays"), detail: tr("Kecerahan DDC dan peredup software untuk semua layar.", "DDC brightness and a software dimmer for every display."), since: "1.4"),
                Item(symbol: "calendar.badge.clock", title: tr("Jadwal", "Schedule"), detail: tr("Tugas perawatan otomatis pada jam tertentu.", "Automatic maintenance tasks at set times."), since: "1.4"),
                Item(symbol: "arrow.up.arrow.down", title: "Scroll Reverser", detail: tr("Arah scroll terpisah untuk trackpad dan mouse.", "Separate scroll direction for trackpad and mouse."), since: "1.0"),
                Item(symbol: "wrench.and.screwdriver", title: tr("Alat", "Tools"), detail: tr("Info sistem, kesehatan baterai, ekspor laporan PDF.", "System info, battery health, PDF report export."), since: "1.5"),
            ]),
        ]
    }

    struct Change: Identifiable {
        var id: String { version }
        let version: String
        let id_: String
        let en: String
        init(_ v: String, _ i: String, _ e: String) { version = v; id_ = i; en = e }
    }

    static let changelog: [Change] = [
        Change("1.6.3", "Ikon fitur berwarna per kategori (bisa diganti 4 gaya), warna aksen pilihan (oranye, grafit, aksen macOS, biru, hijau, ungu, merah muda, teal, kustom), mode Gelap pekat, menu tema cepat, tombol Bebaskan RAM di Beranda, repo pembaruan bawaan.",
                "Feature icons coloured by category (4 styles), accent presets (orange, graphite, macOS accent, blue, green, purple, pink, teal, custom), Pure dark mode, quick theme menu, Free up RAM on Home, built-in update repo."),
        Change("1.6.2", "Keamanan: shortcut Desktop tanpa AppleScript, nama file aneh tidak bisa menyisipkan perintah, pembaruan lebih kebal, agen AI yang dijeda pulih setelah crash, SHA-256 di catatan rilis.",
                "Security: Desktop shortcuts without AppleScript, odd file names can't inject commands, sturdier updates, paused AI agents recover after a crash, SHA-256 in release notes."),
        Change("1.6.1", "Keamanan: pembaruan otomatis hanya menerima rilis bertanda tangan pembuat yang sama; skrip pengaman GitHub dan cadangan sertifikat.",
                "Security: automatic updates only accept releases signed by the same publisher; GitHub hardening and certificate backup scripts."),
        Change("1.6", "Logo oranye baru dan tema PY-Sys; tampilan Beranda dengan ringkasan, pencarian fitur, favorit, dan semua fitur berlabel.",
                "New orange logo and PY-Sys theme; a Home screen with a summary, feature search, favorites and labelled features."),
        Change("1.5.3", "Deskripsi berlaku untuk semua ukuran RAM; uji pertama pembaruan otomatis.",
                "Description now covers every RAM size; first test of automatic updates."),
        Change("1.5.2", "Pembaruan otomatis: tanda di menu bar, banner di panel, dan pasang versi baru dengan satu klik.",
                "Automatic updates: a menu bar badge, a banner in the panel, and one-click install of new versions."),
        Change("1.5.1", "Mode hemat: pembaruan data lebih jarang saat panel tertutup, sensor suhu dan GPU dibaca seperlunya.",
                "Power saving: slower updates while the panel is closed, temperature and GPU read only when needed."),
        Change("1.5", "Uninstaller, file besar & duplikat, laporan PDF, cek pembaruan, jendela Tentang & fitur.",
                "Uninstaller, large & duplicate files, PDF report, update check, About & features window."),
        Change("1.4", "Pengatur jendela, riwayat clipboard, kecerahan monitor, penjadwal tugas.",
                "Window manager, clipboard history, display brightness, task scheduler."),
        Change("1.3", "Riwayat 24 jam/7 hari, tulis SSD harian, saran restart, mode fokus, tab browser.",
                "24-hour/7-day history, daily SSD writes, restart advice, focus mode, browser tabs."),
        Change("1.2", "Agen AI, browser, widget menu bar, sertifikat lokal.", "AI agents, browsers, menu bar widgets, local certificate."),
        Change("1.1", "Klik Kanan+ untuk Finder.", "Right-Click+ for Finder."),
        Change("1.0", "Rilis pertama: monitoring, Cryo-Sleep, pembersih, toggle, Scroll Reverser, tema, Intel + Apple Silicon.",
                "First release: monitoring, Cryo-Sleep, cleaner, toggles, Scroll Reverser, themes, Intel + Apple Silicon."),
    ]
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PY-Sys").font(.system(.title, design: .rounded).weight(.heavy)).foregroundStyle(Theme.brand)
                        Text(tr("Versi \(AppInfo.version) · oleh \(AppInfo.author)", "Version \(AppInfo.version) · by \(AppInfo.author)"))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(tr("PY-Sys adalah aplikasi menu bar untuk memantau, membersihkan, dan merawat Mac, untuk semua Mac dengan RAM berapa pun (8, 16, 24 GB atau lebih). Paling terasa manfaatnya di Mac 8 GB yang dipakai untuk banyak tab browser, beberapa monitor, dan agen AI, tetapi juga membantu Mac dengan RAM besar tetap rapi dan terpantau. PY-Sys tidak mengubah sistem dan tidak butuh hak admin: ia membaca data dari macOS, membekukan aplikasi yang tidak dipakai, membersihkan file yang bisa dibuat ulang, dan menyediakan alat produktivitas dalam satu tempat. Berjalan di Mac Apple Silicon dan Intel dengan macOS 13 atau lebih baru.",
                        "PY-Sys is a menu bar app that monitors, cleans and looks after your Mac, for any Mac, whatever its RAM (8, 16, 24 GB or more). It helps most on 8 GB Macs running many browser tabs, several displays and AI agents, and keeps larger Macs tidy and well monitored too. It doesn't modify the system or need admin rights: it reads data from macOS, freezes apps you're not using, cleans files that can be rebuilt, and puts productivity tools in one place. Runs on Apple Silicon and Intel Macs with macOS 13 or later."))
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(FeatureCatalog.sections) { s in
                    Text(s.title).font(.headline).padding(.top, 4)
                    ForEach(s.items) { i in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: i.symbol).frame(width: 20).foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(i.title).font(.callout.bold())
                                    if i.since == FeatureCatalog.newestFeature {
                                        Text(tr("BARU", "NEW")).font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(Capsule().fill(Color.orange.opacity(0.25)))
                                    } else {
                                        Text("v\(i.since)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Text(i.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                Text(tr("Riwayat versi", "Version history")).font(.headline).padding(.top, 4)
                ForEach(FeatureCatalog.changelog) { c in
                    HStack(alignment: .top) {
                        Text(c.version).font(.callout.monospacedDigit().bold()).frame(width: 34, alignment: .leading)
                        Text(tr(c.id_, c.en)).font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider()
                Text("© 2026 \(AppInfo.author) · \(AppInfo.email)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, height: 640)
    }
}

enum AboutWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = tr("Tentang PY-Sys & fitur", "About PY-Sys & features")
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.contentViewController = NSHostingController(rootView: AboutView())
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
