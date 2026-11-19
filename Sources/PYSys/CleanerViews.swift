import SwiftUI
import AppKit

// MARK: - Cleaner › Storage

struct StorageTab: View {
    @ObservedObject var core: AetherCore
    @ObservedObject private var cleaner = StorageCleaner.shared

    private var totalCleanable: UInt64 {
        cleaner.sizes.values.reduce(0, +) + (cleaner.trashSize ?? 0) + cleaner.downloads.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox(tr("Ruang disk", "Disk space")) {
                VStack(spacing: 6) {
                    if let v = core.volume {
                        CompositionBar(segments: [(UInt64(max(0, v.total - v.free)), Color.cyan)], total: UInt64(max(1, v.total)))
                        StatRow(title: tr("Bebas", "Free"), value: Fmt.disk(v.free))
                    }
                    StatRow(title: tr("Bisa dibebaskan", "Can be freed"),
                            value: cleaner.scanning ? tr("Menghitung…", "Scanning…") : Fmt.disk(Int64(totalCleanable)))
                    HStack {
                        if let m = cleaner.message {
                            Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Button(tr("Pindai ulang", "Rescan")) { cleaner.scan() }
                            .controlSize(.small).disabled(cleaner.scanning)
                    }
                }
            }

            GroupBox(tr("Cache & sampah sistem", "Caches & system junk")) {
                VStack(spacing: 8) {
                    ForEach(cleaner.targets) { t in
                        CleanRow(icon: t.icon, title: t.title, note: t.note,
                                 size: cleaner.sizes[t.id], scanning: cleaner.scanning,
                                 button: tr("Bersihkan", "Clean"), disabled: cleaner.busy || (cleaner.sizes[t.id] ?? 0) == 0) {
                            cleaner.clean(t)
                        }
                    }
                    CleanRow(icon: "trash", title: tr("Sampah", "Trash"),
                             note: cleaner.trashSize == nil ? tr("Ukuran butuh izin Full Disk Access; tetap bisa dikosongkan",
                                                                  "Size needs Full Disk Access; can still be emptied")
                                                            : tr("Isi Sampah Finder", "Finder Trash contents"),
                             size: cleaner.trashSize, scanning: cleaner.scanning,
                             button: tr("Kosongkan", "Empty"), disabled: cleaner.busy || cleaner.trashSize == 0) {
                        cleaner.emptyTrash()
                    }
                }
            }

            GroupBox(tr("Downloads lama atau besar", "Old or large downloads")) {
                VStack(spacing: 4) {
                    Text(tr("Lebih tua dari \(StorageCleaner.downloadAgeDays) hari atau lebih besar dari 500 MB. Dipindah ke Sampah, bukan dihapus.",
                            "Older than \(StorageCleaner.downloadAgeDays) days or larger than 500 MB. Moved to Trash, not deleted."))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if cleaner.downloads.isEmpty && !cleaner.scanning {
                        Text(tr("Tidak ada yang perlu dibersihkan.", "Nothing to clean.")).font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(cleaner.downloads) { f in
                        HStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: f.url.path)).resizable().frame(width: 16, height: 16)
                            Text(f.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(Fmt.disk(Int64(f.size))).monospacedDigit()
                            Button { NSWorkspace.shared.activateFileViewerSelecting([f.url]) } label: { Image(systemName: "magnifyingglass") }
                                .help(tr("Tampilkan di Finder", "Show in Finder"))
                            Button { cleaner.moveToTrash([f]) } label: { Image(systemName: "trash") }
                                .help(tr("Pindahkan ke Sampah", "Move to Trash"))
                        }
                        .font(.callout)
                        .buttonStyle(.borderless)
                    }
                    if cleaner.downloads.count > 1 {
                        HStack {
                            Spacer()
                            Button(tr("Pindahkan semua ke Sampah", "Move all to Trash")) { cleaner.moveToTrash(cleaner.downloads) }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
        .onAppear { if cleaner.sizes.isEmpty { cleaner.scan() } }
    }
}

struct CleanRow: View {
    let icon: String
    let title: String
    let note: String
    let size: UInt64?
    let scanning: Bool
    let button: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Text(scanning ? "…" : (size.map { Fmt.disk(Int64($0)) } ?? "–")).monospacedDigit()
            Button(button, action: action).controlSize(.small).disabled(disabled || scanning)
        }
        .font(.callout)
    }
}

// MARK: - Utility › Tools

struct ToolsTab: View {
    @ObservedObject var core: AetherCore
    @ObservedObject private var ui = UIState.shared
    @ObservedObject private var apple = AppleBatteryInfo.shared

    private static let apps = SysApp.all

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                SystemReport.export()
            } label: {
                Label(tr("Ekspor laporan sistem (PDF)", "Export system report (PDF)"), systemImage: "doc.richtext")
            }
            .controlSize(.small)
            GroupBox(tr("Aplikasi sistem", "System apps")) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Self.apps) { a in
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: a.id) {
                            Button {
                                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
                            } label: {
                                HStack(spacing: 8) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24)
                                    Text(tr(a.idn, a.en)).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            GroupBox(tr("Pintasan cepat", "Quick actions")) {
                VStack(spacing: 6) {
                    QuickAction(icon: "internaldrive", title: tr("Pengaturan Penyimpanan macOS", "macOS Storage settings")) {
                        if let u = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") { NSWorkspace.shared.open(u) }
                    }
                    QuickAction(icon: "folder", title: tr("Buka folder Downloads", "Open Downloads folder")) {
                        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))
                    }
                    QuickAction(icon: "archivebox", title: tr("Buka folder Cache", "Open Caches folder")) {
                        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches"))
                    }
                    QuickAction(icon: "lock.shield", title: tr("Privasi & Keamanan", "Privacy & Security")) {
                        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security") { NSWorkspace.shared.open(u) }
                    }
                }
            }

            GroupBox(tr("Info sistem", "System info")) {
                VStack(spacing: 4) {
                    StatRow(title: "Model", value: SysInfo.model)
                    StatRow(title: "Chip", value: "\(SysInfo.chip) · \(SysInfo.cores)")
                    StatRow(title: "RAM", value: SysInfo.ram)
                    StatRow(title: "macOS", value: SysInfo.macOS)
                    if let cycles = SysInfo.batteryCycles ?? apple.cycles {
                        StatRow(title: tr("Siklus baterai", "Battery cycle count"), value: "\(cycles)")
                    }
                    if let m = apple.maxCapacity {
                        StatRow(title: tr("Kapasitas maksimum", "Maximum capacity"),
                                value: "\(Int(m.rounded()))%" + (apple.conditionText.map { " · \($0)" } ?? ""))
                    }
                    if let b = core.cpu.bootDate {
                        StatRow(title: "Uptime", value: Fmt.duration(Date().timeIntervalSince(b)))
                    }
                    HStack {
                        if ui.copied { Text(tr("Disalin ✓", "Copied ✓")).font(.caption).foregroundStyle(.green) }
                        Spacer()
                        Button(tr("Salin info sistem", "Copy system info")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(SysInfo.summary, forType: .string)
                            ui.copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { ui.copied = false }
                        }
                        .controlSize(.small)
                    }
                }
            }

            BatteryDepreciationView()
        }
        .onAppear { AppleBatteryInfo.shared.refresh(force: true) }
    }
}

struct QuickAction: View {
    let icon: String
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).frame(width: 18)
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.forward").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }
}

struct SysApp: Identifiable {
    let id: String
    let idn: String
    let en: String
    static let all = [
        SysApp(id: "com.apple.ActivityMonitor", idn: "Activity Monitor", en: "Activity Monitor"),
        SysApp(id: "com.apple.Console", idn: "Console", en: "Console"),
        SysApp(id: "com.apple.Terminal", idn: "Terminal", en: "Terminal"),
        SysApp(id: "com.apple.SystemProfiler", idn: "Informasi Sistem", en: "System Information"),
        SysApp(id: "com.apple.DiskUtility", idn: "Disk Utility", en: "Disk Utility"),
    ]
}
