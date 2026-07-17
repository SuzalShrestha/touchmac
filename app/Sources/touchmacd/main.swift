// touchmacd — root helper. Wakes the Apple SPU sensor drivers, opens the hidden
// accelerometer + gyroscope HID devices, and streams samples as tiny UDP
// datagrams to the TouchMac app on 127.0.0.1:48291.
//
// Report format (reverse-engineered, same as macimu): 22-byte input reports,
// x/y/z int32 little-endian at offsets 6/10/14, Q16 fixed point (divide by
// 65536) giving g for accel, deg/s for gyro.
//
// Security note: this process only *emits* sensor data. Actions run inside the
// user-level app, so a local process spoofing datagrams gains nothing it could
// not already do by running commands as the user directly.

import Foundation
import IOKit
import IOKit.hid

let vendorPage = 0xFF00
let usageAccel = 3
let usageGyro = 9
let reportLen = 22
let dataOffset = 6
let scale = 65536.0
let port: UInt16 = 48291
let pidFile = "/var/run/touchmacd.pid"

// ---- single instance guard ----
if let existing = try? String(contentsOfFile: pidFile, encoding: .utf8),
   let pid = Int32(existing.trimmingCharacters(in: .whitespacesAndNewlines)),
   kill(pid, 0) == 0 {
    FileHandle.standardError.write("touchmacd already running (pid \(pid))\n".data(using: .utf8)!)
    exit(0)
}
try? "\(getpid())".write(toFile: pidFile, atomically: true, encoding: .utf8)

guard geteuid() == 0 else {
    FileHandle.standardError.write("touchmacd: needs root (SPU HID device is privileged)\n".data(using: .utf8)!)
    exit(1)
}

// ---- UDP sender ----
let sock = socket(AF_INET, SOCK_DGRAM, 0)
var dest = sockaddr_in()
dest.sin_family = sa_family_t(AF_INET)
dest.sin_port = port.bigEndian
dest.sin_addr.s_addr = inet_addr("127.0.0.1")

func send(kind: UInt8, x: Double, y: Double, z: Double) {
    var pkt = [UInt8](repeating: 0, count: 13)
    pkt[0] = kind
    for (i, v) in [x, y, z].enumerated() {
        var f = Float32(v).bitPattern.littleEndian
        withUnsafeBytes(of: &f) { raw in
            for (j, b) in raw.enumerated() { pkt[1 + i * 4 + j] = b }
        }
    }
    var d = dest
    _ = withUnsafePointer(to: &d) { p in
        p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            sendto(sock, pkt, pkt.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
}

// ---- wake the SPU drivers ----
func wakeSPU() {
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                       IOServiceMatching("AppleSPUHIDDriver"), &it) == KERN_SUCCESS else { return }
    while case let svc = IOIteratorNext(it), svc != 0 {
        for (k, v) in [("SensorPropertyReportingState", 1), ("SensorPropertyPowerState", 1), ("ReportInterval", 1000)] {
            IORegistryEntrySetCFProperty(svc, k as CFString, v as CFNumber)
        }
        IOObjectRelease(svc)
    }
    IOObjectRelease(it)
}

// ---- HID report callbacks ----
func propInt(_ svc: io_object_t, _ key: String) -> Int {
    guard let ref = IORegistryEntryCreateCFProperty(svc, key as CFString, kCFAllocatorDefault, 0) else { return 0 }
    let v = ref.takeRetainedValue()
    return (v as? Int) ?? 0
}

func parseAndSend(kind: UInt8, report: UnsafeMutablePointer<UInt8>, length: CFIndex) {
    guard length == reportLen else { return }
    func i32(_ off: Int) -> Int32 {
        var v: Int32 = 0
        memcpy(&v, report + off, 4)
        return Int32(littleEndian: v)
    }
    send(kind: kind,
         x: Double(i32(dataOffset)) / scale,
         y: Double(i32(dataOffset + 4)) / scale,
         z: Double(i32(dataOffset + 8)) / scale)
}

let accelCallback: IOHIDReportCallback = { _, _, _, _, _, report, length in
    parseAndSend(kind: 0, report: report, length: length)
}
let gyroCallback: IOHIDReportCallback = { _, _, _, _, _, report, length in
    parseAndSend(kind: 1, report: report, length: length)
}

var retainedBuffers: [UnsafeMutablePointer<UInt8>] = []
var openedDevices: [IOHIDDevice] = []

func openSensors() -> Int {
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                       IOServiceMatching("AppleSPUHIDDevice"), &it) == KERN_SUCCESS else { return 0 }
    var opened = 0
    while case let svc = IOIteratorNext(it), svc != 0 {
        defer { IOObjectRelease(svc) }
        let page = propInt(svc, "PrimaryUsagePage")
        let usage = propInt(svc, "PrimaryUsage")
        var callback: IOHIDReportCallback?
        if page == vendorPage && usage == usageAccel { callback = accelCallback }
        if page == vendorPage && usage == usageGyro { callback = gyroCallback }
        guard let cb = callback, let device = IOHIDDeviceCreate(kCFAllocatorDefault, svc) else { continue }
        guard IOHIDDeviceOpen(device, 0) == kIOReturnSuccess else {
            FileHandle.standardError.write("touchmacd: open failed for usage \(usage)\n".data(using: .utf8)!)
            continue
        }
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
        retainedBuffers.append(buf)
        openedDevices.append(device)
        IOHIDDeviceRegisterInputReportCallback(device, buf, 256, cb, nil)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        opened += 1
    }
    IOObjectRelease(it)
    return opened
}

wakeSPU()
let n = openSensors()
guard n > 0 else {
    FileHandle.standardError.write("touchmacd: no SPU accel/gyro devices found on this Mac\n".data(using: .utf8)!)
    exit(1)
}
print("touchmacd: streaming \(n) sensors to 127.0.0.1:\(port)")
CFRunLoopRun()
