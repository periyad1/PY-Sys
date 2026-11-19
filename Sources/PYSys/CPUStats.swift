import Foundation
import Darwin
import IOKit

struct CPUTicks {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

struct CPUSnapshot {
    var user = 0.0          // 0...1, rata-rata semua inti
    var system = 0.0
    var idle = 1.0
    var cores: [Double] = []
    var load: [Double] = [0, 0, 0]
    var gpu: Double?
    var gpuRenderer: Double?
    var gpuTiler: Double?
    var gpuCores: Int?
    var thermal: ProcessInfo.ThermalState = .nominal
    var cpuTemp: Double?
    var cpuTempMax: Double?
    var bootDate: Date?
    var awake: TimeInterval = 0
    var sleeping: TimeInterval = 0
}

struct GPUPoint {
    let date: Date
    let device: Double
}

struct CPUPoint {
    let date: Date
    let user: Double
    let system: Double
}

struct LoadPoint {
    let date: Date
    let l1: Double
    let l5: Double
    let l15: Double
}

struct TopProc: Identifiable {
    let id: Int
    let name: String
    let cpu: Double
}

enum CPUStats {
    private static let host = mach_host_self()

    private static let timebase: (numer: Double, denom: Double) = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return (Double(tb.numer), Double(max(tb.denom, 1)))
    }()

    /// Label inti: di Apple Silicon inti efisiensi (E) bernomor lebih dulu, lalu inti performa (P).
    static let coreLabels: [String] = {
        let total = Int(SystemStats.sysctl("hw.logicalcpu", Int32(0)) ?? 0)
        let eCores = Int(SystemStats.sysctl("hw.perflevel1.logicalcpu", Int32(0)) ?? 0)
        guard total > 0 else { return [] }
        guard eCores > 0 else { return (0..<total).map { "\($0 + 1)" } }   // Intel: tanpa inti E/P
        return (0..<total).map { i in i < eCores ? "E\(i + 1)" : "P\(i - eCores + 1)" }
    }()

    static func perCoreTicks() -> [CPUTicks] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard kr == KERN_SUCCESS, let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var result: [CPUTicks] = []
        let stride = Int(CPU_STATE_MAX)
        for i in 0..<Int(cpuCount) {
            let b = stride * i
            result.append(CPUTicks(
                user: UInt32(bitPattern: info[b + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[b + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[b + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[b + Int(CPU_STATE_NICE)])))
        }
        return result
    }

    static func loadAverage() -> [Double] {
        var l = [Double](repeating: 0, count: 3)
        return getloadavg(&l, 3) == 3 ? l : [0, 0, 0]
    }

    static func bootDate() -> Date? {
        guard let tv = SystemStats.sysctl("kern.boottime", timeval()), tv.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }

    /// mach_absolute_time berhenti saat Mac tidur; mach_continuous_time tidak.
    static func awakeAndSleeping() -> (awake: TimeInterval, sleeping: TimeInterval) {
        let awake = Double(mach_absolute_time()) * timebase.numer / timebase.denom / 1e9
        let total = Double(mach_continuous_time()) * timebase.numer / timebase.denom / 1e9
        return (awake, max(0, total - awake))
    }

    /// Pemakaian GPU dari IOKit (tanpa root).
    /// Device / Renderer / Tiler (%) dan jumlah core GPU dari IOKit.
    static func gpuStats() -> (device: Double?, renderer: Double?, tiler: Double?, cores: Int?) {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"),
                                           &iter) == KERN_SUCCESS else { return (nil, nil, nil, nil) }
        defer { IOObjectRelease(iter) }
        var dev: Double?, ren: Double?, til: Double?, cores: Int?
        var s = IOIteratorNext(iter)
        while s != 0 {
            if let stats = IORegistryEntryCreateCFProperty(s, "PerformanceStatistics" as CFString,
                                                           kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                if let v = ((stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber)?.doubleValue { dev = max(dev ?? 0, v) }
                if let v = (stats["Renderer Utilization %"] as? NSNumber)?.doubleValue { ren = max(ren ?? 0, v) }
                if let v = (stats["Tiler Utilization %"] as? NSNumber)?.doubleValue { til = max(til ?? 0, v) }
            }
            if let c = IORegistryEntryCreateCFProperty(s, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber {
                cores = c.intValue
            }
            IOObjectRelease(s)
            s = IOIteratorNext(iter)
        }
        return (dev, ren, til, cores)
    }

    static func gpuUtilization() -> Double? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"),
                                           &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var result: Double?
        var s = IOIteratorNext(iter)
        while s != 0 {
            if let stats = IORegistryEntryCreateCFProperty(s, "PerformanceStatistics" as CFString,
                                                           kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
               let u = stats["Device Utilization %"] as? NSNumber {
                result = max(result ?? 0, u.doubleValue)
            }
            IOObjectRelease(s)
            s = IOIteratorNext(iter)
        }
        return result
    }

    /// Proses teratas berdasarkan CPU, termasuk proses sistem (WindowServer, kernel_task).
    /// Memakai /bin/ps karena data CPU proses milik root tidak bisa dibaca app biasa.
    static func topProcesses(limit: Int = 6) -> [TopProc] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Aceo", "pid=,pcpu=,comm=", "-r"]
        p.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        var result: [TopProc] = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int(parts[0]), let cpu = Double(parts[1]) else { continue }
            let name = parts[2].trimmingCharacters(in: .whitespaces)
            if name == "ps" { continue }
            result.append(TopProc(id: pid, name: name, cpu: cpu))
            if result.count >= limit { break }
        }
        return result
    }
}
