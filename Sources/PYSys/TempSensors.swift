import Foundation
import Darwin

/// EKSPERIMENTAL: membaca sensor suhu Apple Silicon lewat IOHIDEventSystem (API privat IOKit).
/// Fungsi dimuat saat runtime dengan dlsym, jadi kalau Apple mengubahnya di macOS mendatang,
/// aplikasi tidak crash — suhu hanya tampil "tidak tersedia".
enum TempSensors {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> OpaquePointer?
    private typealias SetMatchingFn = @convention(c) (OpaquePointer, CFDictionary) -> Int32
    private typealias CopyServicesFn = @convention(c) (OpaquePointer) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (OpaquePointer, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (OpaquePointer, Int64, Int32, Int64) -> OpaquePointer?
    private typealias GetFloatFn = @convention(c) (OpaquePointer, Int32) -> Double

    private static let kTypeTemperature: Int64 = 15
    private static let kFieldTemperature: Int32 = 15 << 16

    private struct API {
        let copyServices: CopyServicesFn
        let copyProperty: CopyPropertyFn
        let copyEvent: CopyEventFn
        let getFloat: GetFloatFn
        let client: OpaquePointer
    }

    private static let api: API? = {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) else { return nil }
        func sym<T>(_ name: String, _ type: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: type)
        }
        guard let create = sym("IOHIDEventSystemClientCreate", CreateFn.self),
              let setMatching = sym("IOHIDEventSystemClientSetMatching", SetMatchingFn.self),
              let copyServices = sym("IOHIDEventSystemClientCopyServices", CopyServicesFn.self),
              let copyProperty = sym("IOHIDServiceClientCopyProperty", CopyPropertyFn.self),
              let copyEvent = sym("IOHIDServiceClientCopyEvent", CopyEventFn.self),
              let getFloat = sym("IOHIDEventGetFloatValue", GetFloatFn.self),
              let client = create(kCFAllocatorDefault) else { return nil }
        // Sensor suhu: PrimaryUsagePage 0xff00, PrimaryUsage 5
        let match = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        _ = setMatching(client, match)
        return API(copyServices: copyServices, copyProperty: copyProperty,
                   copyEvent: copyEvent, getFloat: getFloat, client: client)
    }()

    /// Semua sensor: nama → °C
    static func readAll() -> [String: Double] {
        guard let api, let services = api.copyServices(api.client)?.takeRetainedValue() else { return [:] }
        var result: [String: Double] = [:]
        for i in 0..<CFArrayGetCount(services) {
            guard let raw = CFArrayGetValueAtIndex(services, i) else { continue }
            let service = OpaquePointer(raw)
            guard let name = api.copyProperty(service, "Product" as CFString)?
                    .takeRetainedValue() as? String,
                  let event = api.copyEvent(service, kTypeTemperature, 0, 0) else { continue }
            let value = api.getFloat(event, kFieldTemperature)
            Unmanaged<CFTypeRef>.fromOpaque(UnsafeRawPointer(event)).release()
            if value > 0 && value < 130 { result[name] = value }
        }
        return result
    }

    /// Suhu CPU: rata-rata dan maksimum sensor die ("PMU tdie…") pada Apple Silicon.
    static func cpu() -> (avg: Double, max: Double)? {
        let all = readAll()
        var values = all.filter { $0.key.lowercased().contains("tdie") }.map { $0.value }
        if values.isEmpty {
            values = all.filter { $0.key.lowercased().contains("soc") || $0.key.lowercased().contains("cpu") }
                .map { $0.value }
        }
        guard !values.isEmpty else { return nil }
        return (values.reduce(0, +) / Double(values.count), values.max() ?? 0)
    }
}
