import Foundation
import IOKit

// MARK: - SMC (System Management Controller) — kipas & daya

private struct SMCVersion {
    var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
    var release: UInt16 = 0
}
private struct SMCPLimit {
    var version: UInt16 = 0, length: UInt16 = 0
    var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0
}
private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}
/// Tata letak harus sama dengan SMCKeyData_t di C (80 byte).
private struct SMCParam {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimit = SMCPLimit()
    var keyInfo = SMCKeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

final class SMC {
    static let shared: SMC? = SMC()
    private var conn: io_connect_t = 0

    private init?() {
        guard MemoryLayout<SMCParam>.stride == 80 else { return nil }   // pengaman tata letak
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        guard IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
    }

    private func call(_ input: inout SMCParam) -> SMCParam? {
        var output = SMCParam()
        var outSize = MemoryLayout<SMCParam>.stride
        let r = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<SMCParam>.stride, &output, &outSize)
        guard r == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    private static func fourCC(_ s: String) -> UInt32 {
        s.utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
    private static func typeString(_ v: UInt32) -> String {
        String(bytes: [UInt8(v >> 24 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 8 & 0xff), UInt8(v & 0xff)],
               encoding: .ascii) ?? ""
    }

    func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        var input = SMCParam()
        input.key = Self.fourCC(key)
        input.data8 = 9   // kSMCGetKeyInfo
        guard let info = call(&input) else { return nil }
        var input2 = SMCParam()
        input2.key = input.key
        input2.keyInfo.dataSize = info.keyInfo.dataSize
        input2.data8 = 5  // kSMCReadKey
        guard let out = call(&input2) else { return nil }
        let size = min(Int(info.keyInfo.dataSize), 32)
        let bytes = withUnsafeBytes(of: out.bytes) { Array($0.prefix(size)) }
        return (Self.typeString(info.keyInfo.dataType), bytes)
    }

    func number(_ key: String) -> Double? {
        guard let r = read(key), !r.bytes.isEmpty else { return nil }
        let b = r.bytes
        switch r.type {
        case "flt ":
            guard b.count >= 4 else { return nil }
            let bits = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
            return Double(Float(bitPattern: bits))
        case "ui8 ": return Double(b[0])
        case "ui16": return b.count >= 2 ? Double(UInt16(b[0]) << 8 | UInt16(b[1])) : nil
        case "ui32":
            return b.count >= 4 ? Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])) : nil
        case "fpe2": return b.count >= 2 ? Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4 : nil
        case "sp78": return b.count >= 2 ? Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256 : nil
        default: return nil
        }
    }
}

// MARK: - Data sensor

struct FanInfo: Identifiable {
    let id: Int
    let rpm: Double
    let min: Double
    let max: Double
}

struct BatteryInfo {
    var percent: Int?
    var temperature: Double?
    var voltage: Double?        // V
    var amperage: Double?       // A (negatif = sedang dipakai)
    var cycles: Int?
    var health: Double?         // 0...1
    var designCapacity: Int?    // mAh
    var rawMaxCapacity: Int?    // mAh
    var charging = false
    var external = false
    var systemLoadW: Double?
}

struct SensorReading: Identifiable {
    var id: String { raw }
    let raw: String
    let name: String
    let celsius: Double
}

struct SensorSnapshot {
    var temps: [SensorReading] = []
    var fans: [FanInfo] = []
    var totalPowerW: Double?
    var battery: BatteryInfo?
}

enum SensorReader {
    static func snapshot() -> SensorSnapshot {
        var s = SensorSnapshot()
        s.temps = TempSensors.readAll()
            .map { SensorReading(raw: $0.key, name: friendly($0.key), celsius: $0.value) }
            .sorted { (order($0.raw), $0.name) < (order($1.raw), $1.name) }
        if s.temps.isEmpty { s.temps = SMCTemps.readAll() }   // Mac Intel: sensor lewat SMC

        if let smc = SMC.shared {
            let n = Int(smc.number("FNum") ?? 0)
            for i in 0..<min(n, 4) {
                if let rpm = smc.number("F\(i)Ac") {
                    s.fans.append(FanInfo(id: i, rpm: rpm,
                                          min: smc.number("F\(i)Mn") ?? 0,
                                          max: smc.number("F\(i)Mx") ?? 0))
                }
            }
            if let p = smc.number("PSTR"), p > 0, p < 500 { s.totalPowerW = p }
        }
        s.battery = battery()
        if s.totalPowerW == nil { s.totalPowerW = s.battery?.systemLoadW }
        return s
    }

    private static func order(_ raw: String) -> Int {
        let l = raw.lowercased()
        if l.contains("tdie") { return 0 }
        if l.contains("tdev") { return 1 }
        if l.contains("nand") { return 2 }
        if l.contains("battery") { return 3 }
        return 4
    }

    static func friendly(_ raw: String) -> String {
        let l = raw.lowercased()
        let digits = raw.filter { $0.isNumber }
        if l.contains("tdie") { return "CPU die \(digits)" }
        if l.contains("tdev") { return tr("Perangkat \(digits)", "Device \(digits)") }
        if l.contains("nand") { return "SSD" }
        if l.contains("battery") { return tr("Baterai", "Battery") }
        return raw
    }

    static func battery() -> BatteryInfo? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return nil }
        func num(_ k: String) -> NSNumber? { d[k] as? NSNumber }
        var b = BatteryInfo()
        b.percent = num("CurrentCapacity")?.intValue
        if let t = num("Temperature")?.doubleValue { b.temperature = t / 100 }
        if let v = num("Voltage")?.doubleValue { b.voltage = v / 1000 }
        if let a = num("Amperage")?.int64Value { b.amperage = Double(Int16(truncatingIfNeeded: a)) / 1000 }
        b.cycles = num("CycleCount")?.intValue
        // Nama kunci berbeda antar versi macOS: cari di level atas dan di "BatteryData".
        let bd = d["BatteryData"] as? [String: Any] ?? [:]
        func any(_ keys: [String]) -> Int? {
            for k in keys {
                if let v = (d[k] as? NSNumber)?.intValue, v > 0 { return v }
                if let v = (bd[k] as? NSNumber)?.intValue, v > 0 { return v }
            }
            return nil
        }
        b.designCapacity = any(["DesignCapacity"])
        b.rawMaxCapacity = any(["AppleRawMaxCapacity", "NominalChargeCapacity"])
        if b.cycles == nil { b.cycles = any(["CycleCount"]) }
        if b.health == nil {
            if let raw = b.rawMaxCapacity, let design = b.designCapacity, design > 0 {
                b.health = Double(raw) / Double(design)
            } else if let pct = (d["MaxCapacity"] as? NSNumber)?.doubleValue, pct > 0, pct <= 100 {
                b.health = pct / 100     // Apple Silicon: MaxCapacity sudah dalam persen
            }
        }
        if let raw = num("AppleRawMaxCapacity")?.doubleValue, let design = num("DesignCapacity")?.doubleValue, design > 0 {
            b.health = raw / design
        }
        b.charging = (d["IsCharging"] as? Bool) ?? false
        b.external = (d["ExternalConnected"] as? Bool) ?? false
        if let tel = d["PowerTelemetryData"] as? [String: Any], let load = (tel["SystemLoad"] as? NSNumber)?.doubleValue {
            b.systemLoadW = load / 1000
        }
        return b
    }
}

// MARK: - Suhu lewat SMC (Mac Intel)

/// Mac Intel tidak punya sensor suhu HID seperti Apple Silicon; suhunya dibaca dari kunci SMC.
/// Kunci yang tidak ada di Mac tertentu dilewati begitu saja.
enum SMCTemps {
    private static let cpuKeys = ["TC0D", "TC0E", "TC0F", "TC0P", "TCXC", "TC1C", "TC2C", "TC3C", "TC4C",
                                  "TC5C", "TC6C", "TC7C", "TC8C"]

    private static let named: [(key: String, id: String, en: String)] = [
        ("TC0D", "CPU die", "CPU die"), ("TC0E", "CPU die (rata-rata)", "CPU die (average)"),
        ("TC0P", "Dekat CPU", "CPU proximity"), ("TCXC", "CPU PECI", "CPU PECI"),
        ("TC1C", "Inti CPU 1", "CPU core 1"), ("TC2C", "Inti CPU 2", "CPU core 2"),
        ("TC3C", "Inti CPU 3", "CPU core 3"), ("TC4C", "Inti CPU 4", "CPU core 4"),
        ("TG0D", "GPU die", "GPU die"), ("TG0P", "Dekat GPU", "GPU proximity"),
        ("TM0P", "Memori", "Memory"), ("TH0P", "SSD", "SSD"), ("TH0a", "SSD", "SSD"),
        ("TB0T", "Baterai", "Battery"), ("TB1T", "Baterai 2", "Battery 2"),
        ("Th0H", "Heatsink", "Heatsink"), ("Ts0P", "Sandaran tangan", "Palm rest"),
        ("TW0P", "Wi-Fi", "Wi-Fi"), ("TA0P", "Udara sekitar", "Ambient"),
    ]

    private static func valid(_ v: Double?) -> Double? {
        guard let v, v > 5, v < 130 else { return nil }
        return v
    }

    static func cpu() -> (avg: Double, max: Double)? {
        guard let smc = SMC.shared else { return nil }
        let values = cpuKeys.compactMap { valid(smc.number($0)) }
        guard !values.isEmpty else { return nil }
        return (values.reduce(0, +) / Double(values.count), values.max() ?? 0)
    }

    static func readAll() -> [SensorReading] {
        guard let smc = SMC.shared else { return [] }
        var seen = Set<String>()
        var out: [SensorReading] = []
        for n in named {
            guard let v = valid(smc.number(n.key)) else { continue }
            let name = tr(n.id, n.en)
            if seen.contains(name) { continue }
            seen.insert(name)
            out.append(SensorReading(raw: n.key, name: name, celsius: v))
        }
        return out
    }
}
