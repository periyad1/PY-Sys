import Foundation
import Darwin
import SystemConfiguration

struct NetInterface: Identifiable {
    var id: String { bsd }
    let bsd: String
    let name: String
    let isWiFi: Bool
    let connected: Bool
    let ipv4: [String]
    let ipv6: [String]
}

struct NetPoint {
    let date: Date
    let upKBps: Double
    let downKBps: Double
}

struct NetProc: Identifiable {
    var id: String { name + "\(pid)" }
    let name: String
    let pid: Int
    let up: Double     // byte/detik
    let down: Double
}

struct PublicIP {
    let ip: String
    let country: String?
    var flag: String {
        guard let c = country?.uppercased(), c.count == 2 else { return "" }
        return c.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map { String($0) }.joined()
    }
}

enum NetworkStats {
    /// Semua port jaringan perangkat keras (Wi-Fi, Ethernet, Thunderbolt Bridge, adaptor USB, …)
    static func interfaces() -> [NetInterface] {
        let addrs = addresses()
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [] }
        var result: [NetInterface] = []
        var seen = Set<String>()
        for i in all {
            guard let bsd = SCNetworkInterfaceGetBSDName(i) as String?, !seen.contains(bsd) else { continue }
            seen.insert(bsd)
            let name = (SCNetworkInterfaceGetLocalizedDisplayName(i) as String?) ?? bsd
            let type = SCNetworkInterfaceGetInterfaceType(i) as String?
            let a = addrs[bsd]
            let v4 = a?.v4 ?? []
            let v6 = a?.v6 ?? []
            let connected = (a?.running ?? false) && (!v4.isEmpty || !v6.isEmpty)
            result.append(NetInterface(bsd: bsd, name: name,
                                       isWiFi: type == (kSCNetworkInterfaceTypeIEEE80211 as String),
                                       connected: connected, ipv4: v4, ipv6: v6))
        }
        return result.sorted { ($0.connected ? 0 : 1, $0.bsd) < ($1.connected ? 0 : 1, $1.bsd) }
    }

    private static func addresses() -> [String: (v4: [String], v6: [String], running: Bool)] {
        var result: [String: (v4: [String], v6: [String], running: Bool)] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [:] }
        defer { freeifaddrs(head) }
        var cur: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cur {
            defer { cur = p.pointee.ifa_next }
            let name = String(cString: p.pointee.ifa_name)
            let flags = Int32(truncatingIfNeeded: p.pointee.ifa_flags)
            var entry = result[name] ?? ([], [], false)
            if flags & IFF_UP != 0 && flags & IFF_RUNNING != 0 { entry.running = true }
            if let sa = p.pointee.ifa_addr {
                let family = Int32(sa.pointee.sa_family)
                if family == AF_INET || family == AF_INET6 {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        var s = String(cString: host)
                        if let pct = s.firstIndex(of: "%") { s = String(s[..<pct]) }
                        if family == AF_INET, !s.hasPrefix("169.254.") { entry.v4.append(s) }
                        if family == AF_INET6, !s.lowercased().hasPrefix("fe80") { entry.v6.append(s) }
                    }
                }
            }
            result[name] = entry
        }
        return result
    }

    /// Penghitung byte masuk/keluar per interface (32-bit, jadi selisihnya dihitung dengan wrapping).
    static func counters() -> [String: (rx: UInt32, tx: UInt32)] {
        var result: [String: (rx: UInt32, tx: UInt32)] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [:] }
        defer { freeifaddrs(head) }
        var cur: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cur {
            defer { cur = p.pointee.ifa_next }
            guard let sa = p.pointee.ifa_addr, Int32(sa.pointee.sa_family) == AF_LINK,
                  let data = p.pointee.ifa_data else { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            result[String(cString: p.pointee.ifa_name)] = (d.ifi_ibytes, d.ifi_obytes)
        }
        return result
    }

    /// Lalu lintas per proses lewat `nettop` (bawaan macOS), sampel 1 detik.
    static func topProcesses(limit: Int = 6) -> [NetProc] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        p.arguments = ["-P", "-d", "-L", "2", "-s", "1", "-x", "-J", "bytes_in,bytes_out"]
        p.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        // Ambil blok sampel terakhir (setelah baris header terakhir)
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        guard let lastHeader = lines.lastIndex(where: { $0.contains("bytes_in") }) else { return [] }
        var procs: [NetProc] = []
        for line in lines[(lastHeader + 1)...] {
            let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard let idx = f.firstIndex(where: { !$0.contains(":") && $0.range(of: #"\.\d+$"#, options: .regularExpression) != nil }),
                  idx + 2 < f.count,
                  let rx = Double(f[idx + 1]), let tx = Double(f[idx + 2]) else { continue }
            let full = f[idx]
            let dot = full.lastIndex(of: ".")!
            let name = String(full[..<dot])
            let pid = Int(full[full.index(after: dot)...]) ?? 0
            if rx > 0 || tx > 0 { procs.append(NetProc(name: name, pid: pid, up: tx, down: rx)) }
        }
        return Array(procs.sorted { ($0.up + $0.down) > ($1.up + $1.down) }.prefix(limit))
    }

    /// IP publik + negara (layanan pihak ketiga: ipapi.co, cadangan: ipify.org).
    static func fetchPublicIP(completion: @escaping (PublicIP?) -> Void) {
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: URL(string: "https://ipapi.co/json/")!) { data, _, _ in
            if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ip = obj["ip"] as? String {
                completion(PublicIP(ip: ip, country: obj["country_code"] as? String))
                return
            }
            session.dataTask(with: URL(string: "https://api.ipify.org?format=json")!) { data, _, _ in
                if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let ip = obj["ip"] as? String {
                    completion(PublicIP(ip: ip, country: nil))
                } else {
                    completion(nil)
                }
            }.resume()
        }.resume()
    }
}
