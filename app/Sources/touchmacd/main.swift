// touchmacd — root helper. Wakes the Apple SPU sensor drivers, opens the hidden
// accelerometer + gyroscope HID devices, and streams samples in small UDP
// batches to the TouchMac app on 127.0.0.1:48291.
//
// Runs as a LaunchDaemon (installed by the app). launchd keeps one instance
// alive; this process exits on purpose when the stream stalls (after sleep,
// a driver reset) so launchd restarts it and the SPU is woken again.
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
import TouchMacCore

let vendorPage = 0xFF00
let usageAccel = 3
let usageGyro = 9
let reportLen = 22
let dataOffset = 6
let scale = 65536.0
let dataPort: UInt16 = 48291
let pingPort: UInt16 = 48292     // the app pings once a second while it listens
let stallSec = 5.0               // no reports this long: exit, launchd restarts us
let listenerTimeoutSec = 3.0     // no ping this long: stop sending

func log(_ s: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write("\(stamp) touchmacd: \(s)\n".data(using: .utf8)!)
}

guard geteuid() == 0 else {
    log("needs root (SPU HID device is privileged)")
    exit(1)
}

// ---- sockets ----
func loopback(_ port: UInt16) -> sockaddr_in {
    var a = sockaddr_in()
    a.sin_family = sa_family_t(AF_INET)
    a.sin_port = port.bigEndian
    a.sin_addr.s_addr = inet_addr("127.0.0.1")
    return a
}

let sock = socket(AF_INET, SOCK_DGRAM, 0)
var dest = loopback(dataPort)

let pingSock = socket(AF_INET, SOCK_DGRAM, 0)
var pingAddr = loopback(pingPort)
_ = withUnsafePointer(to: &pingAddr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(pingSock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
}
_ = fcntl(pingSock, F_SETFL, O_NONBLOCK)

var listening = false
var lastPing = 0.0
var lastReport = CFAbsoluteTimeGetCurrent()

// Samples go out in batches (one datagram per ≤16 records or 8 ms) so neither process
// wakes ~1600 times a second. Format: TouchMacCore/SensorWire.swift.
let recordLen = SensorWire.recordLen
let batchMax = 16
let batchAgeSec = 0.008
var batch = [UInt8](repeating: 0, count: recordLen * batchMax)
var batchTimes = [Double](repeating: 0, count: batchMax)
var batchCount = 0

func send(kind: UInt8, x: Double, y: Double, z: Double) {
    let now = CFAbsoluteTimeGetCurrent()
    lastReport = now
    guard listening else { batchCount = 0; return }
    batchTimes[batchCount] = now
    let o = batchCount * recordLen
    batch.withUnsafeMutableBytes { SensorWire.write(kind: kind, x: x, y: y, z: z, into: $0, at: o) }
    batchCount += 1
    if batchCount == batchMax || now - batchTimes[0] >= batchAgeSec { flush(now) }
}

func flush(_ now: Double) {
    batch.withUnsafeMutableBytes { raw in
        for i in 0..<batchCount { SensorWire.stampAge(now - batchTimes[i], into: raw, at: i * recordLen) }
    }
    _ = withUnsafePointer(to: &dest) { p in
        p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            sendto(sock, batch, batchCount * recordLen, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    batchCount = 0
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
    return (ref.takeRetainedValue() as? Int) ?? 0
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

/// Returns (devices found, devices opened).
func openSensors() -> (found: Int, opened: Int) {
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                       IOServiceMatching("AppleSPUHIDDevice"), &it) == KERN_SUCCESS else { return (0, 0) }
    var found = 0, opened = 0
    while case let svc = IOIteratorNext(it), svc != 0 {
        defer { IOObjectRelease(svc) }
        let page = propInt(svc, "PrimaryUsagePage")
        let usage = propInt(svc, "PrimaryUsage")
        var callback: IOHIDReportCallback?
        if page == vendorPage && usage == usageAccel { callback = accelCallback }
        if page == vendorPage && usage == usageGyro { callback = gyroCallback }
        guard let cb = callback else { continue }
        found += 1
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, svc),
              IOHIDDeviceOpen(device, 0) == kIOReturnSuccess else {
            log("open failed for usage \(usage)")
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
    return (found, opened)
}

// ---- start ----
// At early boot the SPU driver may not be matched yet: retry before giving up.
var result = (found: 0, opened: 0)
for attempt in 1...6 {
    wakeSPU()
    result = openSensors()
    if result.opened > 0 { break }
    log("no sensor yet (attempt \(attempt)/6, found \(result.found))")
    sleep(5)
}
if result.found == 0 {
    log("no SPU accel/gyro devices on this Mac; exiting for good")
    exit(0)  // KeepAlive.SuccessfulExit=false: launchd will not restart a clean exit
}
if result.opened == 0 {
    exit(3)  // devices exist but would not open: let launchd retry
}
log("streaming \(result.opened) sensors to 127.0.0.1:\(dataPort) while the app listens")

// ---- once a second: listener check, stall watchdog ----
let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 1, 1, 0, 0) { _ in
    let now = CFAbsoluteTimeGetCurrent()
    var byte: UInt8 = 0
    while recv(pingSock, &byte, 1, 0) >= 0 { lastPing = now }
    let wasListening = listening
    listening = now - lastPing < listenerTimeoutSec
    if listening && !wasListening { wakeSPU() }
    // ponytail: exit-and-restart is the whole sleep/stall recovery; add IOPM wake hooks if restarts prove slow
    if now - lastReport > stallSec {
        log("no reports for \(Int(now - lastReport)) s (sleep or driver reset); exiting so launchd restarts us")
        exit(2)
    }
}
CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
CFRunLoopRun()
