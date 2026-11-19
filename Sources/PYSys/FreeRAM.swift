import SwiftUI
import AppKit

// MARK: - Bebaskan RAM: kabar singkat di Beranda + halaman rincian

enum FreeRAMRoute { static let tab = "freeram" }

/// Hitung mundur kotak hasil: hilang 20 detik setelah angka "sesudah" muncul; berhenti saat kursor di atasnya.
final class ToastTimer: ObservableObject {
    static let shared = ToastTimer()
    @Published private(set) var progress: Double = 1       // 1 → 0
    @Published private(set) var dismissed: Date?
    var hovering = false
    private var timer: Timer?
    private var stamp: Date?
    private let duration = 20.0

    /// Laporan baru: tampilkan penuh, belum menghitung mundur.
    func reset(for date: Date) {
        timer?.invalidate()
        timer = nil
        stamp = date
        progress = 1
        dismissed = nil
    }

    /// Angka "sesudah" sudah ada: mulai hitung mundur.
    func start(for date: Date) {
        guard stamp == date else { return }
        timer?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard !hovering else { return }
        progress = max(0, progress - 0.1 / duration)
        if progress <= 0 { dismiss() }
    }

    func dismiss() {
        timer?.invalidate()
        timer = nil
        dismissed = stamp
    }
}

/// Kotak hasil di bawah tombol Bebaskan RAM (Beranda), dengan tombol × dan hilang otomatis.
struct FreeRAMToast: View {
    @ObservedObject var core: AetherCore
    @ObservedObject private var ui = UIState.shared
    @ObservedObject private var timer = ToastTimer.shared

    var body: some View {
        if let r = core.freeReport, timer.dismissed != r.date {
            let ok = !r.frozen.isEmpty
            let tint = ok ? Color.green : Color.orange
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ok ? tr("\(r.frozen.count) app dibekukan, ±\(Fmt.bytes(r.frozenBytes))", "\(r.frozen.count) apps frozen, about \(Fmt.bytes(r.frozenBytes))")
                                : tr("Tidak ada app idle yang aman dibekukan", "No idle apps are safe to freeze"))
                            .font(.callout.bold())
                        Text(beforeAfter(r)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(tr("Rincian ›", "Details ›")).font(.caption.bold()).foregroundStyle(Theme.accent)
                }
                .contentShape(Rectangle())
                .onTapGesture { ui.tab = FreeRAMRoute.tab }

                Button { timer.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(tr("Tutup", "Close"))
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.12)))
            .overlay(alignment: .bottomLeading) {
                if r.afterPct != nil {
                    GeometryReader { g in
                        Capsule().fill(tint.opacity(0.7)).frame(width: g.size.width * timer.progress, height: 3)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .padding(.horizontal, 6)
                    .allowsHitTesting(false)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.35)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onHover { timer.hovering = $0 }
        }
    }

    private func beforeAfter(_ r: FreeRAMReport) -> String {
        if let a = r.afterPct { return "RAM \(Int(r.beforePct.rounded()))% → \(Int(a.rounded()))%" }
        return tr("RAM \(Int(r.beforePct.rounded()))% → mengukur…", "RAM \(Int(r.beforePct.rounded()))% → measuring…")
    }
}

struct FreeRAMView: View {
    @ObservedObject var core: AetherCore
    @ObservedObject private var ui = UIState.shared

    private func row(_ i: FreeItem, trailing: some View) -> some View {
        HStack(spacing: 8) {
            if let ic = i.icon { Image(nsImage: ic).resizable().frame(width: 20, height: 20) }
            else { Image(systemName: "app").frame(width: 20, height: 20) }
            VStack(alignment: .leading, spacing: 1) {
                Text(i.name).font(.callout.weight(.semibold)).lineLimit(1)
                Text(i.note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            trailing
        }
    }

    private func box<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionTitle(text: title)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let r = core.freeReport {
                // Sebelum → sesudah
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Sebelum", "Before")).font(.caption2).foregroundStyle(.secondary)
                        Text("\(Int(r.beforePct.rounded()))%").font(.system(size: 22, weight: .heavy, design: .rounded))
                    }
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Sesudah", "After")).font(.caption2).foregroundStyle(.secondary)
                        if let a = r.afterPct {
                            Text("\(Int(a.rounded()))%").font(.system(size: 22, weight: .heavy, design: .rounded))
                                .foregroundStyle(a < r.beforePct ? Color.green : Color.primary)
                        } else {
                            HStack(spacing: 4) { ProgressView().controlSize(.small); Text(tr("mengukur…", "measuring…")).font(.caption) }
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(tr("Tekanan memori", "Memory pressure")).font(.caption2).foregroundStyle(.secondary)
                        Text(r.afterPressure.map { r.beforePressure == $0 ? $0.label : "\(r.beforePressure.label) → \($0.label)" } ?? r.beforePressure.label)
                            .font(.caption.bold()).foregroundStyle((r.afterPressure ?? r.beforePressure).color)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))

                if r.frozen.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "eye.circle.fill").font(.title2).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("Tidak ada app idle yang aman dibekukan", "No idle apps are safe to freeze")).font(.callout.bold())
                            Text(tr("App besar sedang terlihat di layar, aktif, sedang bekerja, atau ada di whitelist. Pilih salah satu cara di bawah.",
                                    "Large apps are on screen, active, busy or whitelisted. Pick one of the options below."))
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    box(tr("Dibekukan · \(r.frozen.count) app · ±\(Fmt.bytes(r.frozenBytes))", "Frozen · \(r.frozen.count) apps · about \(Fmt.bytes(r.frozenBytes))")) {
                        ForEach(r.frozen) { i in row(i, trailing: Text(Fmt.bytes(i.bytes)).font(.caption.bold().monospacedDigit())) }
                        Text(tr("App beku otomatis cair saat Anda membukanya lagi.", "Frozen apps thaw automatically when you open them."))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                if !r.skipped.isEmpty {
                    box(tr("Dilewati · \(r.skipped.count) app", "Skipped · \(r.skipped.count) apps")) {
                        ForEach(r.skipped) { i in row(i, trailing: Text(Fmt.bytes(i.bytes)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)) }
                        let visible = r.skipped.filter(\.visible)
                        if !visible.isEmpty {
                            HStack(spacing: 8) {
                                Button(tr("Bekukan lebih banyak", "Freeze more")) { core.freeUpRAM(aggressive: true) }
                                    .buttonStyle(.borderedProminent).tint(Theme.brand).controlSize(.small)
                                Text(tr("\(visible.map(\.name).prefix(3).joined(separator: ", ")) disembunyikan lalu dibekukan (±\(Fmt.bytes(visible.reduce(0) { $0 + $1.bytes })))",
                                        "\(visible.map(\.name).prefix(3).joined(separator: ", ")) are hidden, then frozen (about \(Fmt.bytes(visible.reduce(0) { $0 + $1.bytes })))"))
                                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button(tr("Tidurkan tab browser", "Put browser tabs to sleep")) { ui.tab = AppTab.tabsleep.rawValue }
                        .controlSize(.small)
                    Text(tr("Simpan & tutup tab yang tidak dipakai.", "Save & close tabs you aren't using."))
                        .font(.caption2).foregroundStyle(.secondary)
                }

                let top = core.groups.filter { $0.isApp && !core.freezer.isFrozen($0.mainPID) && $0.bundleID != Bundle.main.bundleIdentifier }.prefix(3)
                if !top.isEmpty {
                    box(tr("Pemakai RAM terbesar · tutup untuk langsung membebaskan", "Largest memory users · quit to free right away")) {
                        ForEach(Array(top)) { g in
                            row(FreeItem(id: g.mainPID, name: g.name, icon: g.icon, bytes: g.footprint, note: Fmt.bytes(g.footprint), visible: false),
                                trailing: Button(tr("Tutup", "Quit")) {
                                    NSRunningApplication(processIdentifier: g.mainPID)?.terminate()
                                }.controlSize(.small))
                        }
                    }
                }
            } else {
                Text(tr("Belum ada hasil. Klik Bebaskan RAM di Beranda.", "No results yet. Click Free up RAM on Home."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
