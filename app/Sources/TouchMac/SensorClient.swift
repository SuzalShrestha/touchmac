import Foundation
import IOKit
import TouchMacCore

/// Connects to touchmacd's Unix socket (format: SensorWire) and feeds samples to the callbacks.
/// The connection is accepted only if the peer is root: the socket sits in /var/run, which
/// only root can write, so nobody else can pose as the helper and inject fake taps.
/// Callbacks run on `queue`; touch the engine only from there.
final class SensorClient {
    var onAccel: ((Double, Double, Double, Double) -> Void)?  // t, x, y, z
    var onGyro: ((Double, Double, Double, Double) -> Void)?
    let queue = DispatchQueue(label: "touchmac.sensor", qos: .userInteractive)

    // all below: `queue` only
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var carry: [UInt8] = []  // bytes of a record split across reads
    private var lastPacket = 0.0  // systemUptime

    /// Connects if not connected. Cheap; call about once a second.
    func connectIfNeeded() {
        queue.async { [self] in
            guard fd < 0 else { return }
            let s = socket(AF_UNIX, SOCK_STREAM, 0)
            guard s >= 0 else { return }
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutableBytes(of: &addr.sun_path) { dst in
                SensorWire.socketPath.utf8CString.withUnsafeBytes {
                    dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(dst.count - 1)))
                }
            }
            let ok =
                withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
                } == 0
            var uid: uid_t = 1, gid: gid_t = 0
            guard ok, getpeereid(s, &uid, &gid) == 0, uid == 0 else {
                close(s)
                return
            }
            var one: Int32 = 1
            setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(s, F_SETFL, O_NONBLOCK)
            fd = s
            carry = []
            let src = DispatchSource.makeReadSource(fileDescriptor: s, queue: queue)
            src.setEventHandler { [weak self] in self?.drain() }
            src.setCancelHandler { close(s) }
            src.resume()
            source = src
        }
    }

    private func drain() {
        var buf = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR) { return disconnect() }
            guard n > 0 else { return }
            let now = ProcessInfo.processInfo.systemUptime
            lastPacket = now
            let bytes = carry + buf[0..<n]
            let whole = bytes.count - bytes.count % SensorWire.recordLen
            bytes.withUnsafeBytes { raw in
                SensorWire.decode(raw, count: whole, now: now) { kind, t, x, y, z in
                    if kind == 0 { onAccel?(t, x, y, z) } else { onGyro?(t, x, y, z) }
                }
            }
            carry = Array(bytes[whole...])
        }
    }

    private func disconnect() {
        source?.cancel()  // cancel handler closes the fd
        source = nil
        fd = -1
    }

    var isAlive: Bool {
        queue.sync { lastPacket > 0 && ProcessInfo.processInfo.systemUptime - lastPacket < 1.5 }
    }

    /// True when this Mac exposes the SPU accelerometer. Reading the registry needs no root.
    static let hardwarePresent: Bool = {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDevice"), &it) == KERN_SUCCESS
        else { return false }
        defer { IOObjectRelease(it) }
        var found = false
        while case let svc = IOIteratorNext(it), svc != 0 {
            let page =
                IORegistryEntryCreateCFProperty(svc, "PrimaryUsagePage" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
            let usage =
                IORegistryEntryCreateCFProperty(svc, "PrimaryUsage" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
            if page == 0xFF00 && usage == 3 { found = true }
            IOObjectRelease(svc)
        }
        return found
    }()
}
