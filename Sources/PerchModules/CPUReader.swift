import Foundation
import Darwin

/// Reads system-wide CPU busy percentage from the Mach kernel.
///
/// The kernel exposes cumulative "ticks" since boot, so a single reading is
/// meaningless — busy % is the *change* between two readings. This reader keeps
/// the previous sample and returns the delta, which is why it's a class with
/// state rather than a pure function.
final class CPUReader: @unchecked Sendable {
    private let lock = NSLock()
    private var previous: host_cpu_load_info?

    /// Busy percentage (0–100) since the last call, or `nil` on the first call
    /// (no previous sample to diff against yet) or on a read error.
    func sampleBusyPercent() -> Double? {
        guard let current = Self.readLoad() else { return nil }

        lock.lock()
        defer { previous = current; lock.unlock() }

        guard let previous else { return nil }

        let userDelta   = Double(current.cpu_ticks.0 &- previous.cpu_ticks.0) // user
        let systemDelta = Double(current.cpu_ticks.1 &- previous.cpu_ticks.1) // system
        let idleDelta   = Double(current.cpu_ticks.2 &- previous.cpu_ticks.2) // idle
        let niceDelta   = Double(current.cpu_ticks.3 &- previous.cpu_ticks.3) // nice

        let busy = userDelta + systemDelta + niceDelta
        let total = busy + idleDelta
        guard total > 0 else { return nil }
        return (busy / total) * 100
    }

    private static func readLoad() -> host_cpu_load_info? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &count)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }
}
