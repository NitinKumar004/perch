import Foundation
import Darwin

/// Checks whether something is listening on a local TCP port, by attempting a
/// short non-blocking connect to 127.0.0.1. Used by the dev-server monitor so
/// "is :3000 up?" is answerable without touching GitHub or a browser.
enum PortProbe {
    /// True if a TCP connection to `127.0.0.1:port` succeeds within `timeout`.
    static func isOpen(port: UInt16, timeout: TimeInterval = 0.4) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        // Non-blocking so a dead port doesn't hang the poll.
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult == 0 { return true }         // connected immediately
        guard errno == EINPROGRESS else { return false }

        // Wait for the socket to become writable (connection completed).
        var writeSet = fd_set()
        fdZero(&writeSet)
        fdSet(fd, &writeSet)
        var tv = timeval(tv_sec: Int(timeout), tv_usec: __darwin_suseconds_t((timeout - floor(timeout)) * 1_000_000))
        let ready = select(fd + 1, nil, &writeSet, nil, &tv)
        guard ready > 0 else { return false }          // timed out or error

        // Confirm there's no pending socket error.
        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len)
        return soError == 0
    }
}

// fd_set isn't ergonomic from Swift; these mirror the C FD_ZERO / FD_SET macros.
private func fdZero(_ set: inout fd_set) {
    set = fd_set()
}

private func fdSet(_ fd: Int32, _ set: inout fd_set) {
    let offset = Int(fd) / 32
    let mask = Int32(1 << (Int(fd) % 32))
    withUnsafeMutablePointer(to: &set.fds_bits) { p in
        p.withMemoryRebound(to: Int32.self, capacity: 32) { bits in
            bits[offset] |= mask
        }
    }
}
