import Foundation
import Darwin
import AppKit

struct ProcSample {
    let pid: pid_t
    let ppid: pid_t
    let name: String
    let path: String
    let footprint: UInt64   // phys_footprint = angka "Memory" di Activity Monitor
    let cpuNanos: UInt64
}

struct AppGroup: Identifiable {
    let id: String
    let name: String
    let bundleID: String?
    let mainPID: pid_t
    var pids: [pid_t]
    var footprint: UInt64
    var cpu: Double         // persen, dijumlah semua proses dalam grup
    let isApp: Bool
    let icon: NSImage?
}

enum ProcessScanner {
    private static let uid = getuid()
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return (UInt64(tb.numer), UInt64(max(tb.denom, 1)))
    }()

    static func allPIDs() -> [pid_t] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count))).filter { $0 > 0 }
    }

    /// Hanya proses milik user saat ini (yang memang boleh kita SIGSTOP/SIGCONT tanpa root).
    static func scan() -> [pid_t: ProcSample] {
        var result: [pid_t: ProcSample] = [:]
        for pid in allPIDs() {
            var bsd = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size,
                  bsd.pbi_uid == uid else { continue }

            var info = rusage_info_v4()
            let rc = withUnsafeMutablePointer(to: &info) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard rc == 0 else { continue }

            let ticks = info.ri_user_time &+ info.ri_system_time
            let nanos = ticks / timebase.denom * timebase.numer
            var name = cString(bsd.pbi_name)
            if name.isEmpty { name = cString(bsd.pbi_comm) }

            result[pid] = ProcSample(pid: pid, ppid: pid_t(bsd.pbi_ppid), name: name,
                                     path: path(of: pid), footprint: info.ri_phys_footprint,
                                     cpuNanos: nanos)
        }
        return result
    }

    private static func cString<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    private static func path(of pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 4096)
        let r = proc_pidpath(pid, &buf, UInt32(buf.count))
        return r > 0 ? String(cString: buf) : ""
    }
}

enum AppGrouper {
    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    /// API privat yang juga dipakai Activity Monitor; dimuat lewat dlsym supaya aman kalau tidak ada.
    private static let responsible: ResponsibleFn? = {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(p, to: ResponsibleFn.self)
    }()

    /// Proses helper (mis. "Google Chrome Helper (Renderer)") digabung ke aplikasi induknya
    /// bila executable-nya berada di dalam bundle .app tersebut. Proses CLI (python, node,
    /// ollama) yang dijalankan dari Terminal tetap tampil sendiri.
    static func group(samples: [pid_t: ProcSample], cpu: [pid_t: Double]) -> [AppGroup] {
        var apps: [pid_t: NSRunningApplication] = [:]
        for a in NSWorkspace.shared.runningApplications where a.activationPolicy == .regular {
            apps[a.processIdentifier] = a
        }

        var groups: [String: AppGroup] = [:]
        for (pid, s) in samples {
            var owner: NSRunningApplication?
            if let r = responsible?(pid), r > 0, r != pid, let a = apps[r] {
                owner = a
            }
            var p = pid
            var hops = 0
            while owner == nil && hops < 32 {
                if let a = apps[p] { owner = a; break }
                guard let ps = samples[p], ps.ppid > 1, ps.ppid != p else { break }
                p = ps.ppid
                hops += 1
            }
            if let o = owner, o.processIdentifier != pid, responsible?(pid) != o.processIdentifier,
               let bundlePath = o.bundleURL?.path, !s.path.hasPrefix(bundlePath) {
                owner = nil   // anak proses, tapi bukan bagian dari bundle app
            }

            let key: String
            if let o = owner {
                key = "app:\(o.processIdentifier)"
                if groups[key] == nil {
                    groups[key] = AppGroup(id: key, name: o.localizedName ?? s.name,
                                           bundleID: o.bundleIdentifier,
                                           mainPID: o.processIdentifier, pids: [],
                                           footprint: 0, cpu: 0, isApp: true, icon: o.icon)
                }
            } else {
                key = "proc:\(s.name)"
                if groups[key] == nil {
                    groups[key] = AppGroup(id: key, name: s.name, bundleID: nil, mainPID: pid,
                                           pids: [], footprint: 0, cpu: 0, isApp: false, icon: nil)
                }
            }
            groups[key]!.pids.append(pid)
            groups[key]!.footprint += s.footprint
            groups[key]!.cpu += cpu[pid] ?? 0
        }
        return groups.values.sorted { $0.footprint > $1.footprint }
    }
}

enum WindowInfo {
    /// Nomor monitor (1, 2, …) tempat jendela terbesar milik salah satu PID terlihat; nil bila tidak terlihat.
    static func screenNumber(of pids: [pid_t]) -> Int? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return nil }
        let set = Set(pids)
        var best: (area: CGFloat, rect: CGRect)?
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0, let pid = w[kCGWindowOwnerPID as String] as? Int,
                  set.contains(pid_t(pid)), let bd = w[kCGWindowBounds as String],
                  let r = CGRect(dictionaryRepresentation: bd as! CFDictionary), r.width >= 60, r.height >= 60 else { continue }
            if best == nil || r.width * r.height > best!.area { best = (r.width * r.height, r) }
        }
        guard let r = best?.rect else { return nil }
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let p = CGPoint(x: r.midX, y: primaryH - r.midY)          // koordinat CG (kiri-atas) → AppKit (kiri-bawah)
        return (NSScreen.screens.firstIndex { $0.frame.contains(p) } ?? 0) + 1
    }

    /// PID yang punya jendela normal yang sedang terlihat di layar mana pun (termasuk monitor eksternal).
    static func visiblePIDs() -> Set<pid_t> {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        var result = Set<pid_t>()
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? Int else { continue }
            if let alpha = w[kCGWindowAlpha as String] as? Double, alpha < 0.05 { continue }
            if let b = w[kCGWindowBounds as String] as? [String: Double],
               (b["Width"] ?? 0) < 60 || (b["Height"] ?? 0) < 60 { continue }
            result.insert(pid_t(pid))
        }
        return result
    }
}

struct DiskProc: Identifiable {
    let id: pid_t
    let name: String
    let read: Double    // byte/detik
    let write: Double
}

enum DiskIOScanner {
    /// Byte baca/tulis disk kumulatif per proses (hanya proses milik user ini).
    static func sample() -> [pid_t: (name: String, read: UInt64, written: UInt64)] {
        var result: [pid_t: (name: String, read: UInt64, written: UInt64)] = [:]
        for pid in ProcessScanner.allPIDs() {
            var info = rusage_info_v4()
            let rc = withUnsafeMutablePointer(to: &info) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard rc == 0 else { continue }
            var buf = [CChar](repeating: 0, count: 256)
            proc_name(pid, &buf, UInt32(buf.count))
            let name = String(cString: buf)
            result[pid] = (name.isEmpty ? "pid \(pid)" : name, info.ri_diskio_bytesread, info.ri_diskio_byteswritten)
        }
        return result
    }
}
