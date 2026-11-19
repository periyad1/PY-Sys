import AppKit
import SwiftUI

// MARK: - Penjadwal tugas

enum TaskAction: String, Codable, CaseIterable, Identifiable {
    case freezeIdle, cleanCaches, cleanLogs, cleanDev, emptyTrash
    case focusOn, focusOff, closeDupTabs, saveLayout, restoreLayout, clearClipboard, quitApp, reminder
    var id: String { rawValue }

    var title: String {
        switch self {
        case .freezeIdle: return tr("Bekukan app yang idle", "Freeze idle apps")
        case .cleanCaches: return tr("Bersihkan cache aplikasi", "Clean app caches")
        case .cleanLogs: return tr("Bersihkan log", "Clean logs")
        case .cleanDev: return tr("Bersihkan cache developer", "Clean developer caches")
        case .emptyTrash: return tr("Kosongkan Sampah", "Empty Trash")
        case .focusOn: return tr("Mulai mode fokus", "Start focus mode")
        case .focusOff: return tr("Akhiri mode fokus", "End focus mode")
        case .closeDupTabs: return tr("Tutup tab browser duplikat", "Close duplicate browser tabs")
        case .saveLayout: return tr("Simpan tata letak jendela", "Save window layout")
        case .restoreLayout: return tr("Pulihkan tata letak jendela", "Restore window layout")
        case .clearClipboard: return tr("Hapus riwayat clipboard", "Clear clipboard history")
        case .quitApp: return tr("Tutup aplikasi", "Quit an app")
        case .reminder: return tr("Pengingat", "Reminder")
        }
    }

    var symbol: String {
        switch self {
        case .freezeIdle: return "snowflake"
        case .cleanCaches, .cleanLogs, .cleanDev: return "archivebox"
        case .emptyTrash: return "trash"
        case .focusOn, .focusOff: return "scope"
        case .closeDupTabs: return "moon.zzz"
        case .saveLayout, .restoreLayout: return "rectangle.split.2x1"
        case .clearClipboard: return "doc.on.clipboard"
        case .quitApp: return "xmark.app"
        case .reminder: return "bell"
        }
    }
}

struct ScheduledTask: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var action: TaskAction
    var param = ""              // ID profil, bundle ID app, atau teks pengingat
    var hour = 22
    var minute = 0
    var days: [Int] = [1, 2, 3, 4, 5, 6, 7]   // Calendar.weekday: 1 = Minggu
    var enabled = true
    var lastRun: Date?
}

final class TaskScheduler: ObservableObject {
    static let shared = TaskScheduler()
    private let key = "scheduledTasks"

    @Published var tasks: [ScheduledTask] { didSet { persist() } }
    @Published var draft = ScheduledTask(action: .freezeIdle)
    @Published var adding = false
    @Published var message: String?
    private var timer: Timer?

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let t = try? JSONDecoder().decode([ScheduledTask].self, from: d) {
            tasks = t
        } else {
            tasks = []
        }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(tasks) { UserDefaults.standard.set(d, forKey: key) }
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func check() {
        let now = Date()
        let c = Calendar.current.dateComponents([.weekday, .hour, .minute], from: now)
        for i in tasks.indices where tasks[i].enabled {
            let t = tasks[i]
            guard t.days.contains(c.weekday ?? 0), t.hour == c.hour, t.minute == c.minute,
                  t.lastRun.map({ now.timeIntervalSince($0) > 90 }) ?? true else { continue }
            tasks[i].lastRun = now
            run(t, scheduled: true)
        }
    }

    func describe(_ t: ScheduledTask) -> String {
        var s = t.action.title
        switch t.action {
        case .focusOn:
            s += ": " + (FocusStore.shared.profiles.first { $0.id == t.param }?.name ?? "?")
        case .quitApp:
            s += ": " + (NSWorkspace.shared.urlForApplication(withBundleIdentifier: t.param)?.deletingPathExtension().lastPathComponent ?? t.param)
        case .reminder:
            s += ": " + t.param
        default: break
        }
        return s
    }

    func when(_ t: ScheduledTask) -> String {
        let names = AppLanguage.isEnglish ? ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"] : ["Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab"]
        let days: String
        if t.days.count == 7 { days = tr("Setiap hari", "Every day") }
        else if Set(t.days) == [2, 3, 4, 5, 6] { days = tr("Senin–Jumat", "Weekdays") }
        else { days = t.days.sorted().map { names[$0 - 1] }.joined(separator: ", ") }
        return String(format: "%02d.%02d · ", t.hour, t.minute) + days
    }

    // MARK: Menjalankan

    func run(_ t: ScheduledTask, scheduled: Bool) {
        let core = AetherCore.shared
        var result = ""
        switch t.action {
        case .freezeIdle:
            let r = core.freezer.freezeIdleNow(groups: core.groups)
            result = tr("\(r.count) app dibekukan (\(Fmt.bytes(r.bytes))).", "\(r.count) apps frozen (\(Fmt.bytes(r.bytes))).")
        case .cleanCaches, .cleanLogs, .cleanDev:
            let id = t.action == .cleanCaches ? "caches" : (t.action == .cleanLogs ? "logs" : "dev")
            guard let target = StorageCleaner.shared.targets.first(where: { $0.id == id }) else { return }
            DispatchQueue.global(qos: .utility).async {
                let before = target.folders.reduce(UInt64(0)) { $0 + StorageCleaner.size(of: $1) }
                let fm = FileManager.default
                for f in target.folders {
                    for item in (try? fm.contentsOfDirectory(at: f, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: item) }
                }
                let after = target.folders.reduce(UInt64(0)) { $0 + StorageCleaner.size(of: $1) }
                let freed = before > after ? before - after : 0
                DispatchQueue.main.async {
                    self.finish(t, tr("\(target.title): \(Fmt.disk(Int64(freed))) dibebaskan.", "\(target.title): \(Fmt.disk(Int64(freed))) freed."))
                }
            }
            return
        case .emptyTrash:
            var err: NSDictionary?
            _ = NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&err)
            result = err == nil ? tr("Sampah dikosongkan.", "Trash emptied.") : tr("Gagal: izinkan Automation › Finder.", "Failed: allow Automation › Finder.")
        case .focusOn:
            guard let p = FocusStore.shared.profiles.first(where: { $0.id == t.param }) else { return }
            FocusStore.shared.apply(p)
            result = FocusStore.shared.lastMessage ?? ""
        case .focusOff:
            FocusStore.shared.end()
            result = tr("Mode fokus diakhiri.", "Focus mode ended.")
        case .closeDupTabs:
            let ts = TabSleeper.shared
            ts.refresh()
            let dup = ts.duplicates
            ts.close(dup, save: false)
            result = tr("\(dup.count) tab duplikat ditutup.", "\(dup.count) duplicate tabs closed.")
        case .saveLayout:
            WindowManager.shared.saveLayout()
            result = WindowManager.shared.message ?? ""
        case .restoreLayout:
            WindowManager.shared.restoreLayout()
            result = WindowManager.shared.message ?? ""
        case .clearClipboard:
            ClipboardHistory.shared.clear()
            result = tr("Riwayat clipboard dihapus (kecuali yang disematkan).", "Clipboard history cleared (except pinned).")
        case .quitApp:
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: t.param)
            apps.forEach { $0.terminate() }
            result = apps.isEmpty ? tr("App tidak sedang berjalan.", "The app wasn't running.") : tr("App ditutup.", "App closed.")
        case .reminder:
            Notifier.post(title: tr("Pengingat PY-Sys", "PY-Sys reminder"), body: t.param.isEmpty ? tr("Waktunya!", "It's time!") : t.param)
            return
        }
        finish(t, result)
    }

    private func finish(_ t: ScheduledTask, _ result: String) {
        message = describe(t) + " — " + result
        Notifier.post(title: tr("Tugas terjadwal", "Scheduled task"), body: describe(t) + ". " + result)
    }
}

struct SchedulerTab: View {
    @ObservedObject private var sch = TaskScheduler.shared
    @ObservedObject private var focus = FocusStore.shared

    private struct DayChip: Hashable {
        let day: Int
        let label: String
    }
    private var chips: [DayChip] {
        let id = ["S", "S", "R", "K", "J", "S", "M"], en = ["M", "T", "W", "T", "F", "S", "S"]
        let labels = AppLanguage.isEnglish ? en : id
        return [2, 3, 4, 5, 6, 7, 1].enumerated().map { DayChip(day: $0.element, label: labels[$0.offset]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Jalankan tugas perawatan otomatis pada jam tertentu. Mac harus menyala (tidak tidur) saat jadwalnya tiba.",
                    "Run maintenance tasks automatically at set times. The Mac must be awake when the time comes."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if sch.tasks.isEmpty && !sch.adding {
                Text(tr("Belum ada tugas. Contoh: bekukan app idle setiap jam 22.00, atau bersihkan cache setiap Jumat.",
                        "No tasks yet. For example: freeze idle apps every day at 22:00, or clean caches every Friday."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            ForEach($sch.tasks) { $t in
                HStack(spacing: 8) {
                    Toggle("", isOn: $t.enabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                    Image(systemName: t.action.symbol).frame(width: 16).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sch.describe(t)).font(.caption).lineLimit(1)
                        Text(sch.when(t)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { sch.run(t, scheduled: false) } label: { Image(systemName: "play.fill") }
                        .buttonStyle(.borderless).help(tr("Jalankan sekarang", "Run now"))
                    Button { sch.tasks.removeAll { $0.id == t.id } } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
                Divider()
            }

            if sch.adding {
                GroupBox(tr("Tugas baru", "New task")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker(tr("Tugas", "Task"), selection: $sch.draft.action) {
                            ForEach(TaskAction.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                        switch sch.draft.action {
                        case .focusOn:
                            Picker(tr("Profil", "Profile"), selection: $sch.draft.param) {
                                ForEach(focus.profiles) { Text($0.name).tag($0.id) }
                            }
                        case .quitApp:
                            Picker("App", selection: $sch.draft.param) {
                                ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil },
                                        id: \.processIdentifier) { a in
                                    Text(a.localizedName ?? a.bundleIdentifier!).tag(a.bundleIdentifier!)
                                }
                            }
                        case .reminder:
                            TextField(tr("Teks pengingat, mis. Istirahat & minum", "Reminder text, e.g. Take a break"), text: $sch.draft.param)
                        default:
                            EmptyView()
                        }
                        HStack {
                            Text(tr("Jam", "Time"))
                            Picker("", selection: $sch.draft.hour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
                                .labelsHidden().frame(width: 64)
                            Text(":")
                            Picker("", selection: $sch.draft.minute) { ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
                                .labelsHidden().frame(width: 64)
                        }
                        HStack(spacing: 4) {
                            ForEach(chips, id: \.self) { d in
                                let on = sch.draft.days.contains(d.day)
                                Button(d.label) {
                                    if on { sch.draft.days.removeAll { $0 == d.day } } else { sch.draft.days.append(d.day) }
                                }
                                .buttonStyle(.borderless)
                                .frame(width: 26, height: 22)
                                .background(RoundedRectangle(cornerRadius: 5).fill(on ? Theme.accent.opacity(0.35) : Color.primary.opacity(0.06)))
                            }
                        }
                        HStack {
                            Button(tr("Simpan tugas", "Save task")) {
                                var t = sch.draft
                                if t.action == .focusOn && t.param.isEmpty { t.param = focus.profiles.first?.id ?? "" }
                                sch.tasks.append(t)
                                sch.draft = ScheduledTask(action: .freezeIdle)
                                sch.adding = false
                            }
                            .disabled(sch.draft.days.isEmpty || (sch.draft.action == .quitApp && sch.draft.param.isEmpty))
                            Button(tr("Batal", "Cancel")) { sch.adding = false }
                        }
                        .controlSize(.small)
                    }
                    .font(.caption)
                }
            } else {
                Button(tr("Tambah tugas", "Add task")) {
                    sch.draft = ScheduledTask(action: .freezeIdle)
                    sch.adding = true
                }
                .controlSize(.small)
            }

            if let m = sch.message {
                Text(m).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
