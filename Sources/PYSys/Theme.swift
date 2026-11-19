import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Penyimpanan & penerapan tema

enum Theme {
    /// Warna aksen aktif: kustom dari slider, atau aksen bawaan macOS.
    static var accent: Color {
        let s = AetherCore.shared.settings
        return s.accentCustom ? Color(hue: s.accentHue / 360, saturation: 0.72, brightness: 0.88) : Color.accentColor
    }

    /// Kunci perubahan tema, dipakai untuk menggambar ulang seluruh panel.
    static func key(_ s: Settings) -> String {
        "\(s.accentCustom)|\(s.bgKind)|\(s.bgImageName)"
    }

    static func applyAppearance(_ mode: String) {
        switch mode {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
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
                Text(tr("Ikuti sistem", "System")).tag("system")
                Text(tr("Terang", "Light")).tag("light")
                Text(tr("Gelap", "Dark")).tag("dark")
            }
            .pickerStyle(.segmented)

            Toggle(tr("Warna aksen kustom", "Custom accent color"), isOn: $settings.accentCustom)
            if settings.accentCustom {
                HStack(spacing: 8) {
                    Circle().fill(Theme.accent).frame(width: 16, height: 16)
                    HueSlider(hue: $settings.accentHue)
                }
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

            Button(tr("Kembali ke tema PY-Sys (oranye)", "Back to the PY-Sys theme (orange)")) {
                settings.themeMode = "system"
                Theme.applyAppearance("system")
                settings.accentCustom = true
                settings.accentHue = Brand.accentHue
                settings.bgKind = "color"
                settings.bgHue = Brand.bgHue
                settings.bgBrightness = Brand.bgBrightness
                settings.bgOpacity = Brand.bgOpacity
                settings.bgBlur = 8
            }
            .controlSize(.small)
        }
    }
}
