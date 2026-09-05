import Foundation
import Darwin

/// Reads system memory pressure — the share of physical RAM actually in use
/// (active + wired + compressed pages), the same notion Activity Monitor's
/// "Memory Used" reflects. Unlike CPU this is an instantaneous gauge, so no
/// previous sample is needed.
enum MemoryReader {
    /// Used memory as a percentage of physical RAM (0–100), or `nil` on error.
    static func usedPercent() -> Double? {
        let pageSize = Double(sysconf(_SC_PAGESIZE))
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return nil }

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let used = (Double(stats.active_count)
                    + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * pageSize
        return min(100, max(0, (used / total) * 100))
    }
}
