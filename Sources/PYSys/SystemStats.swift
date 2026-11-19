import Foundation
import Darwin
import IOKit

enum PressureLevel: Int {
    case normal = 1, warning = 2, critical = 4
}

struct MemorySnapshot {
    var date = Date()
    var total: UInt64 = 0
    var app: UInt64 = 0          // "App Memory" ala Activity Monitor
    var wired: UInt64 = 0
    var compressed: UInt64 = 0   // RAM fisik yang dipakai compressor
    var cachedFiles: UInt64 = 0
    var free: UInt64 = 0
    var compressionRatio: Double = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var swapins: UInt64 = 0
    var active: UInt64 = 0
    var pageins: UInt64 = 0
    var pageouts: UInt64 = 0
    var swapouts: UInt64 = 0
    var pressure: PressureLevel = .normal

    var used: UInt64 { app + wired + compressed }
    var usedFraction: Double { total == 0 ? 0 : min(1, Double(used) / Double(total)) }
    /// Persentase tekanan ala Activity Monitor: (wired + compressed) / total RAM.
    var pressureFraction: Double { total == 0 ? 0 : min(1, Double(wired + compressed) / Double(total)) }
}

enum SystemStats {
    private static let host = mach_host_self()

    static let pageSize: UInt64 = {
        var ps: vm_size_t = 0
        host_page_size(mach_host_self(), &ps)
        return UInt64(ps)
    }()

    static func sysctl<T>(_ name: String, _ initial: T) -> T? {
        var value = initial
        var size = MemoryLayout<T>.size
        let r = withUnsafeMutableBytes(of: &value) { sysctlbyname(name, $0.baseAddress, &size, nil, 0) }
        return r == 0 ? value : nil
    }

    static func snapshot() -> MemorySnapshot {
        var s = MemorySnapshot()
        s.total = sysctl("hw.memsize", UInt64(0)) ?? 0

        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let p = pageSize
            let internalPages = UInt64(vm.internal_page_count)
            let purgeable = UInt64(vm.purgeable_count)
            s.app = (internalPages > purgeable ? internalPages - purgeable : 0) * p
            s.wired = UInt64(vm.wire_count) * p
            s.compressed = UInt64(vm.compressor_page_count) * p
            s.cachedFiles = (UInt64(vm.external_page_count) + purgeable) * p
            s.free = UInt64(vm.free_count) * p
            if vm.compressor_page_count > 0 {
                s.compressionRatio = Double(vm.total_uncompressed_pages_in_compressor)
                    / Double(vm.compressor_page_count)
            }
            s.swapins = UInt64(vm.swapins)
            s.active = UInt64(vm.active_count) * p
            s.pageins = UInt64(vm.pageins)
            s.pageouts = UInt64(vm.pageouts)
            s.swapouts = UInt64(vm.swapouts)
        }

        if let sw = sysctl("vm.swapusage", xsw_usage()) {
            s.swapUsed = sw.xsu_used
            s.swapTotal = sw.xsu_total
        }
        if let lvl = sysctl("kern.memorystatus_vm_pressure_level", Int32(0)) {
            s.pressure = PressureLevel(rawValue: Int(lvl)) ?? .normal
        }
        return s
    }

    /// Total byte dibaca & ditulis SSD internal (disk0) sejak boot, dari IOKit.
    static func internalDiskIO() -> (read: UInt64, written: UInt64) {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iter) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iter) }

        var total: UInt64 = 0
        var totalRead: UInt64 = 0
        var service = IOIteratorNext(iter)
        while service != 0 {
            let bsdName = IORegistryEntrySearchCFProperty(
                service, kIOServicePlane, "BSD Name" as CFString, kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateRecursively)) as? String
            if bsdName == "disk0",
               let stats = IORegistryEntryCreateCFProperty(
                    service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any],
               let written = stats["Bytes (Write)"] as? NSNumber {
                total += written.uint64Value
                totalRead += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iter)
        }
        return (totalRead, total)
    }

    /// Kapasitas volume sistem (/): nama, total, bebas.
    static func volumeSpace() -> (name: String, total: Int64, free: Int64)? {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity else { return nil }
        let free = v.volumeAvailableCapacityForImportantUsage ?? 0
        return (v.volumeName ?? "Macintosh HD", Int64(total), free)
    }
}
