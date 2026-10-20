import Foundation
import IOKit
import TouchMacCore

/// Listens on UDP 127.0.0.1:48291 for touchmacd sample batches (format: SensorWire)
/// and pings the helper on :48292 so it only streams while the app listens.
/// Callbacks run on `queue`; touch the engine only from there.
final class SensorClient {
    static let dataPort: UInt16 = 48291
    static let pingPort: UInt16 = 48292

    var onAccel: ((Double, Double, Double, Double) -> Void)?  // t, x, y, z
    var onGyro: ((Double, Double, Double, Double) -> Void)?
    let queue = DispatchQueue(label: "touchmac.sensor", qos: .userInteractive)
    private(set) var startError: String?

    private var sock: Int32 = -1
    private var source: DispatchSourceRead?
    private var lastPacket = 0.0  // systemUptime; read and written on `queue`

    func start() {
        sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else {
            startError = "Could not open a network socket (\(String(cString: strerror(errno))))."
            return
        }
        var addr = Self.loopback(Self.dataPort)
        let bound = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else {
            startError = "Port \(Self.dataPort) is in use. Quit any other copy of TouchMac and reopen it."
            close(sock)
            sock = -1
            return
        }
        let src = DispatchSource.makeReadSource(fileDescriptor: sock, queue: queue)
        src.setEventHandler { [weak self] in self?.drain() }
        src.resume()
        source = src
    }

    private func drain() {
        var buf = [UInt8](repeating: 0, count: 2048)
        while true {
            let n = recv(sock, &buf, buf.count, MSG_DONTWAIT)
            guard n >= 13 else { break }
            let now = ProcessInfo.processInfo.systemUptime
            lastPacket = now
            buf.withUnsafeBytes { raw in
                SensorWire.decode(raw, count: n, now: now) { kind, t, x, y, z in
                    if kind == 0 { onAccel?(t, x, y, z) } else { onGyro?(t, x, y, z) }
                }
            }
        }
    }

    /// Tell the helper someone is listening. Call about once a second.
    func ping() {
        guard sock >= 0 else { return }
        var addr = Self.loopback(Self.pingPort)
        var byte: UInt8 = 1
        _ = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(sock, &byte, 1, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    var isAlive: Bool {
        queue.sync { lastPacket > 0 && ProcessInfo.processInfo.systemUptime - lastPacket < 1.5 }
    }

    private static func loopback(_ port: UInt16) -> sockaddr_in {
        var a = sockaddr_in()
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        a.sin_addr.s_addr = inet_addr("127.0.0.1")
        return a
    }

    /// True when this Mac exposes the SPU accelerometer. Reading the registry needs no root.
    static let hardwarePresent: Bool = {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSPUHIDDevice"), &it) == KERN_SUCCESS
        else { return false }
        defer { IOObjectRelease(it) }
        var found = false
        while case let svc = IOIteratorNext(it), svc != 0 {
            let page = IORegistryEntryCreateCFProperty(svc, "PrimaryUsagePage" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
            let usage = IORegistryEntryCreateCFProperty(svc, "PrimaryUsage" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
            if page == 0xFF00 && usage == 3 { found = true }
            IOObjectRelease(svc)
        }
        return found
    }()
}
