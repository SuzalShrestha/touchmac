import Foundation

/// Listens on UDP 127.0.0.1:48291 for touchmacd sample datagrams:
/// [1 byte kind: 0=accel 1=gyro][3 x Float32 LE x/y/z]
final class SensorClient {
    var onAccel: ((Double, Double, Double, Double) -> Void)?  // t, x, y, z
    var onGyro: ((Double, Double, Double, Double) -> Void)?
    private(set) var lastPacketAt: Date?

    private let queue = DispatchQueue(label: "touchmac.sensor")
    private var sock: Int32 = -1
    private var source: DispatchSourceRead?

    func start() {
        sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else { return }
        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(48291).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
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
        var buf = [UInt8](repeating: 0, count: 64)
        while true {
            let n = recv(sock, &buf, buf.count, MSG_DONTWAIT)
            guard n >= 13 else { break }
            let t = ProcessInfo.processInfo.systemUptime
            lastPacketAt = Date()
            func f(_ off: Int) -> Double {
                var bits: UInt32 = 0
                memcpy(&bits, Array(buf[off..<off + 4]), 4)
                return Double(Float32(bitPattern: UInt32(littleEndian: bits)))
            }
            let x = f(1), y = f(5), z = f(9)
            if buf[0] == 0 { onAccel?(t, x, y, z) } else { onGyro?(t, x, y, z) }
        }
    }

    var isAlive: Bool {
        guard let last = lastPacketAt else { return false }
        return Date().timeIntervalSince(last) < 1.5
    }
}
