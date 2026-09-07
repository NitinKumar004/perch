import Foundation
import Darwin

/// Reads cumulative network byte counters from the kernel via `getifaddrs`.
///
/// Like CPU ticks, a single reading is meaningless — throughput is the *change*
/// between two readings. This returns the running totals across the *physical*
/// interfaces (Ethernet/Wi-Fi/cellular); the module diffs successive samples.
enum NetworkReader {
    /// Whether an interface carries real internet traffic we should count.
    /// Excludes loopback and the virtual/link-local classes that would
    /// double-count the same payload (a VPN tunnel re-counts bytes already seen
    /// on the physical link) or add background chatter (AirDrop/Handoff/Sidecar),
    /// so the throughput matches what's actually going in and out.
    static func countsTowardThroughput(_ name: String) -> Bool {
        // lo=loopback, utun=VPN, awdl/llw=AirDrop/Handoff, bridge=sharing/Docker,
        // ap=hotspot, gif/stf=tunnels, anpi=baseband internal.
        let virtualPrefixes = ["lo", "utun", "awdl", "llw", "bridge", "ap", "gif", "stf", "anpi"]
        return !virtualPrefixes.contains { name.hasPrefix($0) }
    }

    /// Cumulative (bytesIn, bytesOut) since boot across physical interfaces, or
    /// nil on error.
    static func totalBytes() -> (inBytes: UInt64, outBytes: UInt64)? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { freeifaddrs(head) }

        var inBytes: UInt64 = 0
        var outBytes: UInt64 = 0
        var ptr = head
        while let cur = ptr {
            let ifa = cur.pointee
            ptr = ifa.ifa_next
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: ifa.ifa_name)
            guard countsTowardThroughput(name) else { continue }
            guard let raw = ifa.ifa_data else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self).pointee
            inBytes += UInt64(data.ifi_ibytes)
            outBytes += UInt64(data.ifi_obytes)
        }
        return (inBytes, outBytes)
    }
}
