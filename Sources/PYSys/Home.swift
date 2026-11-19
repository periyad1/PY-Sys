import SwiftUI
import AppKit

// MARK: - Beranda: ringkasan, pencarian, favorit, dan semua fitur berlabel

struct HomeView: View {
    @ObservedObject var core: AetherCore
    @ObservedObject var settings: Settings
    @ObservedObject private var ui = UIState.shared

    private var visible: [AppTab] {
        AppTab.allCases.filter { $0 == .settings || !settings.hiddenTabs.contains($0.rawValue) }
    }

    private var favorites: [AppTab] {
        settings.favorites.compactMap { AppTab(rawValue: $0) }.filter { visible.contains($0) }
    }

    private var results: [AppTab] {
        let q = ui.search.trimmingCharacters(in: .whitespaces).lowercased()
        return visible.filter { t in
            [t.short, t.title, t.keywords, t.category.title].joined(separator: " ").lowercased().contains(q)
        }
    }

    private func open(_ t: AppTab) {
        ui.editFavorites = false
        ui.tab = t.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SummaryCard(core: core)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(tr("Cari fitur…", "Search features…"), text: $ui.search)
                        .textFieldStyle(.plain)
                        .onSubmit { if let first = results.first { ui.search = ""; open(first) } }
                    if !ui.search.isEmpty {
                        Button { ui.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))

                Button {
                    core.freeUpRAM()
                } label: {
                    Label(tr("Bebaskan RAM", "Free up RAM"), systemImage: "wind")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brand)
                .controlSize(.regular)
                .help(tr("Bekukan app idle yang tidak terlihat supaya macOS bisa mengompres memorinya",
                         "Freeze idle, hidden apps so macOS can compress their memory"))
            }
            FreeRAMToast(core: core)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !ui.search.isEmpty {
                        if results.isEmpty {
                            Text(tr("Tidak ada fitur yang cocok.", "No matching feature.")).font(.caption).foregroundStyle(.secondary)
                        } else {
                            TileGrid(tabs: results, highlight: false, onTap: { t in ui.search = ""; open(t) })
                        }
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
                            SectionTitle(text: tr("Favorit", "Favorites"))
                            Spacer()
                            Button(ui.editFavorites ? tr("Selesai", "Done") : tr("Ubah", "Edit")) { ui.editFavorites.toggle() }
                                .buttonStyle(.borderless).font(.caption)
                        }
                        if ui.editFavorites {
                            Text(tr("Ketuk bintang pada fitur di bawah untuk menambah atau menghapus favorit (maks. 10).",
                                    "Tap the star on any feature below to add or remove it (max. 10)."))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if favorites.isEmpty {
                            Text(tr("Belum ada favorit. Klik Ubah, lalu pilih bintang pada fitur.", "No favorites yet. Click Edit, then star a feature."))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            TileGrid(tabs: favorites, highlight: true, onTap: open)
                        }

                        ForEach(TabCategory.allCases, id: \.self) { c in
                            let tabs = visible.filter { $0.category == c }
                            if !tabs.isEmpty {
                                HStack {
                                    SectionTitle(text: c.title)
                                    Spacer()
                                    Text(tr("\(tabs.count) fitur", "\(tabs.count) features")).font(.caption2).foregroundStyle(.secondary)
                                }
                                TileGrid(tabs: tabs, highlight: false, onTap: open)
                            }
                        }
                    }
                }
                .padding(.trailing, 4)
                .padding(.bottom, 6)
            }
        }
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(.caption, design: .rounded).weight(.heavy)).foregroundStyle(.secondary).tracking(0.6)
    }
}

struct TileGrid: View {
    let tabs: [AppTab]
    let highlight: Bool
    let onTap: (AppTab) -> Void
    @ObservedObject private var ui = UIState.shared
    @ObservedObject private var settings = AetherCore.shared.settings

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
            ForEach(tabs, id: \.self) { t in
                let fav = settings.favorites.contains(t.rawValue)
                Button {
                    if ui.editFavorites && t != .settings { settings.toggleFavorite(t) } else { onTap(t) }
                } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            FeatureIcon(tab: t, size: 30)
                            if ui.editFavorites && t != .settings {
                                Image(systemName: fav ? "star.fill" : "star")
                                    .font(.system(size: 10))
                                    .foregroundStyle(fav ? Color.yellow : Color.secondary)
                                    .offset(x: 6, y: -5)
                            }
                        }
                        Text(t.short)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.045)))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.08)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t.title)
            }
        }
    }
}

/// Ringkasan RAM, swap, CPU, dan suhu di bagian atas Beranda. Klik untuk membuka detailnya.
struct SummaryCard: View {
    @ObservedObject var core: AetherCore
    @ObservedObject private var ui = UIState.shared

    private func item(_ title: String, _ value: String, _ frac: Double, _ color: Color, _ tab: AppTab) -> some View {
        Button { ui.tab = tab.rawValue } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        Capsule().fill(color).frame(width: max(2, g.size.width * min(max(frac, 0), 1)))
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        let m = core.mem
        let swapGB = Double(m.swapUsed) / 1_073_741_824
        let cpu = 1 - core.cpu.idle
        HStack(spacing: 12) {
            item("RAM", "\(Int((m.usedFraction * 100).rounded()))%", m.usedFraction, m.pressure.color, .ram)
            item("Swap", String(format: "%.1f GB", swapGB), min(swapGB / 8, 1), swapGB > 6 ? .red : (swapGB > 3 ? .orange : .green), .ram)
            item("CPU", "\(Int((cpu * 100).rounded()))%", cpu, cpu > 0.7 ? .orange : .green, .cpu)
            if let t = core.cpu.cpuTemp {
                item(tr("Suhu", "Temp"), "\(Int(t.rounded()))°C", (t - 30) / 70, t > 85 ? .red : (t > 70 ? .orange : .green), .sensors)
            } else {
                item(tr("Beku", "Frozen"), "\(core.freezer.frozen.count) app",
                     Double(core.freezer.frozen.count) / 10, Theme.accent, .cryo)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}
