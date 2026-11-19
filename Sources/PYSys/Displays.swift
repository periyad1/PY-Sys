import AppKit
import SwiftUI
import IOKit

// MARK: - Kecerahan monitor eksternal (DDC/CI, Apple Silicon) + peredup software untuk semua layar

final class DDCDisplay: Identifiable {
    let id: Int
    let service: CFTypeRef
    var brightness: Double?     // 0...100
    var maxValue: Double = 100
    init(id: Int, service: CFTypeRef) {
        self.id = id
        self.service = service
    }
}

enum DDC {
    private typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias IOFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private static func sym<T>(_ name: String, _: T.Type) -> T? {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }
    private static let create = sym("IOAVServiceCreateWithService", CreateFn.self)
    private static let readI2C = sym("IOAVServiceReadI2C", IOFn.self)
    private static let writeI2C = sym("IOAVServiceWriteI2C", IOFn.self)

    static var supported: Bool { create != nil && writeI2C != nil }

    /// Layanan AV untuk setiap monitor eksternal yang tersambung langsung (USB-C/HDMI/Thunderbolt).
    /// Monitor lewat DisplayLink tidak muncul di sini.
    static func externalServices() -> [CFTypeRef] {
        guard let create else { return [] }
        var out: [CFTypeRef] = []
        var iter = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iter) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iter) }
        while true {
            let s = IOIteratorNext(iter)
            if s == 0 { break }
            defer { IOObjectRelease(s) }
            let loc = IORegistryEntryCreateCFProperty(s, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            guard loc == "External", let av = create(kCFAllocatorDefault, s)?.takeRetainedValue() else { continue }
            out.append(av)
        }
        return out
    }

    private static func checksum(_ initial: UInt8, _ data: [UInt8]) -> UInt8 {
        data.reduce(initial) { $0 ^ $1 }
    }

    /// Set VCP (mis. 0x10 = kecerahan) ke nilai tertentu.
    static func write(_ service: CFTypeRef, vcp: UInt8, value: UInt16) -> Bool {
        guard let writeI2C else { return false }
        var packet: [UInt8] = [0x84, 0x03, vcp, UInt8(value >> 8), UInt8(value & 0xFF)]
        packet.append(checksum(0x6E ^ 0x51, packet))
        var ok = false
        for _ in 0..<2 {
            usleep(10_000)
            if writeI2C(service, 0x37, 0x51, &packet, UInt32(packet.count)) == KERN_SUCCESS { ok = true }
        }
        return ok
    }

    /// Baca VCP: (nilai sekarang, nilai maksimum)
    static func read(_ service: CFTypeRef, vcp: UInt8) -> (current: UInt16, max: UInt16)? {
        guard let writeI2C, let readI2C else { return nil }
        for initial in [UInt8(0x6E), UInt8(0x6E ^ 0x51)] {
            for _ in 0..<3 {
                var packet: [UInt8] = [0x82, 0x01, vcp]
                packet.append(checksum(initial, packet))
                guard writeI2C(service, 0x37, 0x51, &packet, UInt32(packet.count)) == KERN_SUCCESS else { continue }
                usleep(40_000)
                var reply = [UInt8](repeating: 0, count: 12)
                guard readI2C(service, 0x37, 0x51, &reply, UInt32(reply.count)) == KERN_SUCCESS else { continue }
                // reply: [src, len, 0x02, result, vcp, type, maxHi, maxLo, curHi, curLo, chk]
                guard reply[2] == 0x02, reply[3] == 0x00, reply[4] == vcp else { continue }
                let mx = UInt16(reply[6]) << 8 | UInt16(reply[7])
                let cur = UInt16(reply[8]) << 8 | UInt16(reply[9])
                if mx > 0 { return (cur, mx) }
            }
        }
        return nil
    }
}

final class DisplayControl: ObservableObject {
    static let shared = DisplayControl()

    @Published private(set) var ddc: [DDCDisplay] = []
    @Published private(set) var scanning = false
    @Published var dim: [String: Double] = [:] { didSet { UserDefaults.standard.set(dim, forKey: "dimLevels"); applyDim() } }

    private let queue = DispatchQueue(label: "pysys.ddc")
    private var overlays: [String: NSWindow] = [:]
    private var pending: [Int: DispatchWorkItem] = [:]

    init() {
        dim = UserDefaults.standard.dictionary(forKey: "dimLevels") as? [String: Double] ?? [:]
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            DisplayControl.shared.applyDim()
        }
    }

    func start() { applyDim() }

    func scan() {
        guard !scanning else { return }
        scanning = true
        queue.async {
            let found = DDC.externalServices().enumerated().map { DDCDisplay(id: $0.offset, service: $0.element) }
            for d in found {
                if let r = DDC.read(d.service, vcp: 0x10) {
                    d.maxValue = Double(r.max)
                    d.brightness = Double(r.current) / Double(r.max) * 100
                }
            }
            DispatchQueue.main.async {
                self.ddc = found
                self.scanning = false
            }
        }
    }

    /// Dikirim dengan jeda kecil supaya slider tidak membanjiri monitor dengan perintah.
    func setBrightness(_ d: DDCDisplay, _ pct: Double) {
        d.brightness = pct
        objectWillChange.send()
        pending[d.id]?.cancel()
        let w = DispatchWorkItem {
            _ = DDC.write(d.service, vcp: 0x10, value: UInt16((pct / 100 * d.maxValue).rounded()))
        }
        pending[d.id] = w
        queue.asyncAfter(deadline: .now() + 0.15, execute: w)
    }

    // MARK: Peredup software (jendela hitam transparan di atas layar; klik tetap tembus)

    static func key(_ s: NSScreen) -> String {
        let n = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        return "\(n)"
    }

    func applyDim() {
        let screens = NSScreen.screens
        let live = Set(screens.map(Self.key))
        for (k, w) in overlays where !live.contains(k) { w.orderOut(nil); overlays[k] = nil }
        for s in screens {
            let k = Self.key(s)
            let level = dim[k] ?? 0
            if level <= 0.001 {
                overlays[k]?.orderOut(nil)
                overlays[k] = nil
                continue
            }
            let w: NSWindow
            if let existing = overlays[k] {
                w = existing
            } else {
                w = NSWindow(contentRect: s.frame, styleMask: .borderless, backing: .buffered, defer: false)
                w.isOpaque = false
                w.hasShadow = false
                w.ignoresMouseEvents = true
                w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
                w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
                w.isReleasedWhenClosed = false
                overlays[k] = w
            }
            w.setFrame(s.frame, display: true)
            w.backgroundColor = NSColor.black.withAlphaComponent(CGFloat(min(level, 0.9)))
            w.orderFrontRegardless()
        }
    }
}

struct DisplaysTab: View {
    @ObservedObject private var dc = DisplayControl.shared

    private func isBuiltin(_ s: NSScreen) -> Bool {
        let n = (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        return CGDisplayIsBuiltin(n) != 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox(tr("Kecerahan hardware (DDC)", "Hardware brightness (DDC)")) {
                VStack(alignment: .leading, spacing: 8) {
                    if !DDC.supported {
                        Text(tr("DDC di versi ini hanya untuk Mac Apple Silicon.", "DDC in this version is for Apple Silicon Macs only."))
                            .font(.caption).foregroundStyle(.secondary)
                    } else if dc.scanning {
                        ProgressView().controlSize(.small)
                    } else if dc.ddc.isEmpty {
                        Text(tr("Tidak ada monitor eksternal yang menjawab DDC. Monitor lewat DisplayLink, adaptor tertentu, dan TV biasanya tidak mendukung; pakai peredup software di bawah.",
                                "No external monitor answered DDC. Monitors on DisplayLink, some adapters and TVs usually don't support it; use the software dimmer below."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(dc.ddc) { d in
                        HStack {
                            Image(systemName: "sun.max").frame(width: 18)
                            Text(tr("Monitor DDC \(d.id + 1)", "DDC monitor \(d.id + 1)")).font(.caption).frame(width: 100, alignment: .leading)
                            Slider(value: Binding(get: { d.brightness ?? 50 }, set: { dc.setBrightness(d, $0) }), in: 0...100)
                            Text(d.brightness.map { "\(Int($0))%" } ?? "?").font(.caption.monospacedDigit()).frame(width: 36)
                        }
                    }
                    Button(tr("Cari monitor", "Find monitors")) { dc.scan() }.controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(tr("Peredup software (semua layar, termasuk DisplayLink)", "Software dimmer (every display, DisplayLink included)")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(NSScreen.screens, id: \.self) { s in
                        let k = DisplayControl.key(s)
                        HStack {
                            Image(systemName: isBuiltin(s) ? "laptopcomputer" : "display").frame(width: 18)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(s.localizedName).font(.caption).lineLimit(1)
                                Text("\(Int(s.frame.width))×\(Int(s.frame.height))").font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(width: 110, alignment: .leading)
                            Slider(value: Binding(get: { dc.dim[k] ?? 0 }, set: { dc.dim[k] = $0 }), in: 0...0.9)
                            Text("\(Int((dc.dim[k] ?? 0) * 100))%").font(.caption.monospacedDigit()).frame(width: 36)
                        }
                    }
                    Text(tr("Menggelapkan gambar di atas layar tanpa mengubah lampu latar. Berguna bila monitor tidak mendukung DDC atau sudah di kecerahan minimum. Lapisan ini ikut terlihat di tangkapan layar.",
                            "Darkens the picture without changing the backlight. Handy when a monitor doesn't support DDC or is already at minimum brightness. The layer also shows up in screenshots."))
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button(tr("Kembalikan semua ke normal", "Reset all to normal")) { dc.dim = [:] }.controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { if dc.ddc.isEmpty { dc.scan() } }
    }
}
