import Foundation
import Darwin

/// Reads cumulative network byte counters from the kernel via `getifaddrs`.
///
/// Like CPU ticks, a single reading is meaningless — throughput is the *change*
/// between two readings. This returns the running totals across all active,
/// non-loopback interfaces; the module diffs successive samples into a rate.
enum NetworkReader {
    /// Cumulative (bytesIn, bytesOut) since boot across physical interfaces, or
    /// nil on error. Loopback (`lo*`) is excluded so local traffic isn't counted.
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
            guard !name.hasPrefix("lo") else { continue }
            guard let raw = ifa.ifa_data else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self).pointee
            inBytes += UInt64(data.ifi_ibytes)
            outBytes += UInt64(data.ifi_obytes)
        }
        return (inBytes, outBytes)
    }
}
