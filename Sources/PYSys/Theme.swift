import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Penyimpanan & penerapan tema

enum Theme {
    /// Warna aksen aktif (tombol, sakelar, tautan). Selalu versi yang terbaca di mode terang dan gelap.
    static var accent: Color {
        let s = AetherCore.shared.settings
        return Color(nsColor: (AccentPreset(rawValue: s.accentPreset) ?? .brand).color(hue: s.accentHue))
    }

    /// Oranye identitas PY-Sys untuk nama aplikasi: oranye tua di mode terang, oranye terang di mode gelap.
    static let brand = Color(nsColor: adaptive(hex(0xC2410C), hex(0xFB923C)))

    static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// Warna yang berganti otomatis mengikuti mode terang/gelap.
    static func adaptive(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { ap in ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }

    /// Kunci perubahan tema, dipakai untuk menggambar ulang seluruh panel.
    static func key(_ s: Settings) -> String {
        "\(s.accentPreset)|\(s.iconStyle)|\(s.themeMode)|\(s.bgKind)|\(s.bgImageName)"
    }

    static func applyAppearance(_ mode: String) {
        switch mode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark", "darkPure": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    private static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PY-Sys", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static var cache: (name: String, image: NSImage)?

    static func image(_ name: String) -> NSImage? {
        guard !name.isEmpty else { return nil }
        if let c = cache, c.name == name { return c.image }
        guard let img = NSImage(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        cache = (name, img)
        return img
    }

    /// Pilih gambar lewat dialog, salin ke folder PY-Sys, kembalikan nama filenya.
    static func pickImage() -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = tr("Pilih gambar latar untuk PY-Sys", "Choose a background image for PY-Sys")
        guard panel.runModal() == .OK, let src = panel.url else { return nil }
        removeImages()
        let ext = src.pathExtension.isEmpty ? "png" : src.pathExtension.lowercased()
        let name = "background-\(Int(Date().timeIntervalSince1970)).\(ext)"
        do {
            try FileManager.default.copyItem(at: src, to: dir.appendingPathComponent(name))
        } catch {
            return nil
        }
        cache = nil
        return name
    }

    static func removeImages() {
        let fm = FileManager.default
        for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where f.hasPrefix("background-") {
            try? fm.removeItem(at: dir.appendingPathComponent(f))
        }
        cache = nil
    }
}

// MARK: - Latar panel

struct ThemeBackground: View {
    @ObservedObject var settings: Settings

    var body: some View {
        ZStack {
            if settings.themeMode == "darkPure" { Color.black.opacity(0.92) }
            switch settings.bgKind {
            case "color":
                Color(hue: settings.bgHue / 360, saturation: 0.55, brightness: settings.bgBrightness)
                    .opacity(settings.bgOpacity)
            case "image":
                if let img = Theme.image(settings.bgImageName) {
                    GeometryReader { g in
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: g.size.width, height: g.size.height)
                            .blur(radius: settings.bgBlur)
                            .clipped()
                    }
                    .opacity(settings.bgOpacity)
                }
            default:
                Color.clear
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - Bagian "Tema" di Pengaturan

struct HueSlider: View {
    @Binding var hue: Double
    var body: some View {
        VStack(spacing: 2) {
            Slider(value: $hue, in: 0...360)
            LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 12).map { Color(hue: $0, saturation: 0.72, brightness: 0.88) },
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 5)
                .clipShape(Capsule())
                .padding(.horizontal, 2)
        }
    }
}

struct ThemeSettingsSection: View {
    @ObservedObject var settings: Settings

    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Tema", "Theme")).font(.subheadline.bold())

            Picker(tr("Tampilan", "Appearance"), selection: Binding(
                get: { settings.themeMode },
                set: { settings.themeMode = $0; Theme.applyAppearance($0) })) {
                ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)

            Text(tr("Gaya ikon", "Icon style")).font(.caption.bold())
            IconStylePicker(settings: settings)

            Text(tr("Warna aksen", "Accent color")).font(.caption.bold())
            AccentPicker(settings: settings)
            if settings.accentPreset == AccentPreset.custom.rawValue {
                HueSlider(hue: $settings.accentHue)
            }

            Picker(tr("Latar", "Background"), selection: $settings.bgKind) {
                Text(tr("Tidak ada", "None")).tag("none")
                Text(tr("Warna", "Color")).tag("color")
                Text(tr("Gambar", "Image")).tag("image")
            }
            .pickerStyle(.segmented)

            if settings.bgKind == "color" {
                HStack(spacing: 8) {
                    Text(tr("Warna", "Hue")).font(.caption).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
                    HueSlider(hue: $settings.bgHue)
                }
                HStack(spacing: 8) {
                    Text(tr("Kecerahan", "Brightness")).font(.caption).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
                    Slider(value: $settings.bgBrightness, in: 0.1...1)
                }
            }

            if settings.bgKind == "image" {
                HStack(spacing: 10) {
                    if let img = Theme.image(settings.bgImageName) {
                        Image(nsImage: img).resizable().scaledToFill()
                            .frame(width: 64, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15))
                            .frame(width: 64, height: 40)
                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                    }
                    Button(tr("Pilih gambar…", "Choose image…")) {
                        if let name = Theme.pickImage() { settings.bgImageName = name }
                    }
                    if !settings.bgImageName.isEmpty {
                        Button(tr("Hapus", "Remove")) {
                            Theme.removeImages()
                            settings.bgImageName = ""
                        }
                    }
                }
                .controlSize(.small)
                HStack(spacing: 8) {
                    Text("Blur").font(.caption).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
                    Slider(value: $settings.bgBlur, in: 0...30)
                    Text("\(Int(settings.bgBlur))").font(.caption).monospacedDigit().frame(width: 30, alignment: .trailing)
                }
            }

            if settings.bgKind != "none" {
                HStack(spacing: 8) {
                    Text(tr("Opasitas", "Opacity")).font(.caption).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
                    Slider(value: $settings.bgOpacity, in: 0.05...1)
                    Text(pct(settings.bgOpacity)).font(.caption).monospacedDigit().frame(width: 38, alignment: .trailing)
                }
                Text(tr("Tip: opasitas 25–45% dan sedikit blur menjaga teks tetap mudah dibaca.",
                        "Tip: 25–45% opacity with a little blur keeps text easy to read."))
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Button(tr("Kembali ke tema bawaan PY-Sys", "Back to the default PY-Sys theme")) {
                settings.themeMode = "system"
                Theme.applyAppearance("system")
                settings.accentPreset = AccentPreset.brand.rawValue
                settings.iconStyle = IconStyle.category.rawValue
                settings.accentHue = Brand.accentHue
                settings.bgKind = "none"
                settings.bgHue = Brand.bgHue
                settings.bgBrightness = Brand.bgBrightness
                settings.bgOpacity = Brand.bgOpacity
                settings.bgBlur = 8
            }
            .controlSize(.small)
        }
    }
}


// MARK: - Pilihan tema: tampilan, gaya ikon, warna aksen

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark, darkPure
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return tr("Sistem", "System")
        case .light: return tr("Terang", "Light")
        case .dark: return tr("Gelap", "Dark")
        case .darkPure: return tr("Gelap pekat", "Pure dark")
        }
    }
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        case .darkPure: return "moon.fill"
        }
    }
}

enum AccentPreset: String, CaseIterable, Identifiable {
    case brand, graphite, system, blue, green, purple, pink, teal, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .brand: return tr("Oranye PY-Sys", "PY-Sys orange")
        case .graphite: return tr("Grafit", "Graphite")
        case .system: return tr("Aksen macOS", "macOS accent")
        case .blue: return tr("Biru", "Blue")
        case .green: return tr("Hijau", "Green")
        case .purple: return tr("Ungu", "Purple")
        case .pink: return tr("Merah muda", "Pink")
        case .teal: return "Teal"
        case .custom: return tr("Kustom", "Custom")
        }
    }
    /// Setiap warna punya versi gelap untuk mode terang dan versi terang untuk mode gelap, supaya teks tetap terbaca.
    func color(hue: Double) -> NSColor {
        switch self {
        case .brand: return Theme.adaptive(Theme.hex(0xC2410C), Theme.hex(0xFB923C))
        case .graphite: return Theme.adaptive(Theme.hex(0x3A3A3C), Theme.hex(0xD1D1D6))
        case .system: return .controlAccentColor
        case .blue: return Theme.adaptive(Theme.hex(0x0A64D6), Theme.hex(0x4C9BFF))
        case .green: return Theme.adaptive(Theme.hex(0x15803D), Theme.hex(0x4ADE80))
        case .purple: return Theme.adaptive(Theme.hex(0x6D28D9), Theme.hex(0xA78BFA))
        case .pink: return Theme.adaptive(Theme.hex(0xBE185D), Theme.hex(0xF472B6))
        case .teal: return Theme.adaptive(Theme.hex(0x0F766E), Theme.hex(0x2DD4BF))
        case .custom:
            return Theme.adaptive(NSColor(hue: hue / 360, saturation: 0.80, brightness: 0.62, alpha: 1),
                                 NSColor(hue: hue / 360, saturation: 0.55, brightness: 0.95, alpha: 1))
        }
    }
}

enum IconStyle: String, CaseIterable, Identifiable {
    case mono, category = "cat", feature = "feat", outline
    var id: String { rawValue }
    var letter: String {
        switch self { case .mono: return "A"; case .category: return "B"; case .feature: return "C"; case .outline: return "D" }
    }
    var title: String {
        switch self {
        case .mono: return tr("Monokrom", "Monochrome")
        case .category: return tr("Per kategori", "By category")
        case .feature: return tr("Per fitur", "By feature")
        case .outline: return tr("Garis", "Outline")
        }
    }
    static var current: IconStyle {
        IconStyle(rawValue: AetherCore.shared.settings.iconStyle) ?? .category
    }
}

extension TabCategory {
    var color: NSColor {
        switch self {
        case .monitoring: return Theme.hex(0x0A64D6)
        case .cleaner: return Theme.hex(0x15803D)
        case .utility: return Theme.hex(0x6D28D9)
        }
    }
}

extension AppTab {
    /// Warna khas per fitur (gaya C), cukup gelap agar simbol putih terbaca.
    var color: NSColor {
        let h: UInt32
        switch self {
        case .dashboard: h = 0x1D4ED8
        case .overview: h = 0x0F766E
        case .ram: h = 0x2563EB
        case .cpu: h = 0x4F46E5
        case .network: h = 0x0E7490
        case .sensors: h = 0xDC2626
        case .agents: h = 0x7C3AED
        case .browser: h = 0x0369A1
        case .history: h = 0x475569
        case .apps: h = 0x334155
        case .cryo: h = 0x0891B2
        case .focus: h = 0x9333EA
        case .tabsleep: h = 0x4338CA
        case .storage: h = 0x64748B
        case .uninstall: h = 0xB91C1C
        case .files: h = 0xA16207
        case .toggles: h = 0x4B5563
        case .clickmenu: h = 0x2563EB
        case .windows: h = 0x0D9488
        case .clipboard: h = 0x475569
        case .displays: h = 0xCA8A04
        case .scheduler: h = 0xDB2777
        case .scroll: h = 0x7C3AED
        case .tools: h = 0x57534E
        case .settings: h = 0x6B7280
        }
        return Theme.hex(h)
    }
}

/// Ikon fitur sesuai gaya yang dipilih.
struct FeatureIcon: View {
    let tab: AppTab
    var size: CGFloat = 30
    var style: IconStyle = .current

    var body: some View {
        let glyph = Image(systemName: tab.icon).font(.system(size: size * 0.5, weight: style == .outline ? .semibold : .medium))
        switch style {
        case .mono:
            glyph.frame(width: size, height: size).foregroundStyle(Color.primary.opacity(0.8))
                .background(RoundedRectangle(cornerRadius: size * 0.27).fill(Color.primary.opacity(0.08)))
        case .category:
            glyph.frame(width: size, height: size).foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: size * 0.27).fill(Color(nsColor: tab.category.color)))
        case .feature:
            glyph.frame(width: size, height: size).foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: size * 0.27).fill(Color(nsColor: tab.color)))
        case .outline:
            Image(systemName: tab.icon).font(.system(size: size * 0.62, weight: .semibold))
                .frame(width: size, height: size).foregroundStyle(Color.primary)
        }
    }
}

struct IconStylePicker: View {
    @ObservedObject var settings: Settings
    var body: some View {
        HStack(spacing: 6) {
            ForEach(IconStyle.allCases) { st in
                let on = IconStyle.current == st
                Button { settings.iconStyle = st.rawValue } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 2) {
                            FeatureIcon(tab: .ram, size: 18, style: st)
                            FeatureIcon(tab: .cryo, size: 18, style: st)
                            FeatureIcon(tab: .clipboard, size: 18, style: st)
                        }
                        Text("\(st.letter) · \(st.title)").font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(on ? Theme.accent.opacity(0.15) : Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Theme.accent : Color.clear, lineWidth: 1.5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AccentPicker: View {
    @ObservedObject var settings: Settings
    var body: some View {
        HStack(spacing: 8) {
            ForEach(AccentPreset.allCases) { p in
                let on = settings.accentPreset == p.rawValue
                Button { settings.accentPreset = p.rawValue } label: {
                    ZStack {
                        if p == .custom {
                            Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center))
                        } else {
                            Circle().fill(Color(nsColor: p.color(hue: settings.accentHue)))
                        }
                        if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
                    }
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(Color.primary.opacity(on ? 0.6 : 0.15), lineWidth: on ? 2 : 1))
                }
                .buttonStyle(.plain)
                .help(p.title)
            }
        }
    }
}

/// Tombol cepat di kepala panel: ganti tampilan, gaya ikon, dan warna aksen tanpa membuka Pengaturan.
struct QuickThemeMenu: View {
    @ObservedObject var settings: Settings
    var body: some View {
        Menu {
            Picker(tr("Tampilan", "Appearance"), selection: Binding(
                get: { settings.themeMode },
                set: { settings.themeMode = $0; Theme.applyAppearance($0) })) {
                ForEach(AppearanceMode.allCases) { Label($0.title, systemImage: $0.symbol).tag($0.rawValue) }
            }
            .pickerStyle(.inline)
            Picker(tr("Gaya ikon", "Icon style"), selection: Binding(
                get: { IconStyle.current.rawValue },
                set: { settings.iconStyle = $0 })) {
                ForEach(IconStyle.allCases) { Text("\($0.letter) · \($0.title)").tag($0.rawValue) }
            }
            .pickerStyle(.inline)
            Picker(tr("Warna aksen", "Accent color"), selection: Binding(
                get: { settings.accentPreset },
                set: { v in
                    settings.accentPreset = v
                    // Kustom butuh slider warna: tampilkan panel kecil di atas panel PY-Sys
                    UIState.shared.customColorOpen = (v == AccentPreset.custom.rawValue)
                })) {
                ForEach(AccentPreset.allCases) { Text($0 == .custom ? $0.title + "…" : $0.title).tag($0.rawValue) }
            }
            .pickerStyle(.inline)
            Divider()
            Button(tr("Kembali ke tema bawaan", "Reset to default theme")) {
                settings.themeMode = "system"
                Theme.applyAppearance("system")
                settings.iconStyle = "cat"
                settings.accentPreset = AccentPreset.brand.rawValue
                settings.bgKind = "none"
            }
        } label: {
            Image(systemName: "paintpalette")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("Tema cepat", "Quick theme"))
    }
}


/// Panel kecil pemilih warna kustom, muncul setelah memilih "Kustom…" di menu tema cepat.
struct CustomColorCard: View {
    @ObservedObject var settings: Settings
    @ObservedObject private var ui = UIState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(Theme.accent).frame(width: 14, height: 14)
                Text(tr("Warna aksen kustom", "Custom accent color")).font(.callout.bold())
                Spacer()
                Button(tr("Selesai", "Done")) { ui.customColorOpen = false }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
            HueSlider(hue: $settings.accentHue)
            HStack(spacing: 8) {
                Text(tr("Contoh:", "Preview:")).font(.caption).foregroundStyle(.secondary)
                Button(tr("Tombol", "Button")) {}.buttonStyle(.borderedProminent).controlSize(.small)
                Toggle("", isOn: .constant(true)).toggleStyle(.switch).labelsHidden().controlSize(.mini)
                Text(tr("Tautan", "Link")).font(.caption.bold()).foregroundStyle(Theme.accent)
                Spacer()
            }
            .allowsHitTesting(false)
            Text(tr("Geser untuk memilih warna. PY-Sys otomatis memakai versi lebih gelap di mode terang dan lebih terang di mode gelap supaya tetap terbaca.",
                    "Slide to pick a colour. PY-Sys uses a darker shade in light mode and a lighter one in dark mode so it stays readable."))
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
        .tint(Theme.accent)
    }
}
