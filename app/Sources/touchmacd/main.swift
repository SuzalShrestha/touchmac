// touchmacd — root helper. Wakes the Apple SPU sensor drivers, opens the hidden
// accelerometer + gyroscope HID devices, and streams samples in small batches
// to the TouchMac app over a Unix socket in /var/run.
//
// Runs as a LaunchDaemon (installed by the app). launchd keeps one instance
// alive; this process exits on purpose when the stream stalls (after sleep,
// a driver reset) so launchd restarts it and the SPU is woken again.
//
// Report format (reverse-engineered, same as macimu): 22-byte input reports,
// x/y/z int32 little-endian at offsets 6/10/14, Q16 fixed point (divide by
// 65536) giving g for accel, deg/s for gyro.
//
// Security: the socket lives in /var/run, where only root can create it, so the
// app knows it talks to this helper (it also checks our uid is 0). We stream only
// to the console user (or root), checked with getpeereid: other accounts and
// processes cannot read the motion data, which can leak keystrokes. The check runs
// again every second, so a fast user switch cuts off the previous user's client.

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
let stallSec = 5.0               // no reports this long: exit, launchd restarts us

func log(_ s: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write("\(stamp) touchmacd: \(s)\n".data(using: .utf8)!)
}

guard geteuid() == 0 else {
    log("needs root (SPU HID device is privileged)")
    exit(1)
}

// ---- socket: only the console user may connect ----
signal(SIGPIPE, SIG_IGN)
unlink(SensorWire.socketPath)
let listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &addr.sun_path) { dst in
    SensorWire.socketPath.utf8CString.withUnsafeBytes { dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(dst.count - 1))) }
}
let bound = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
}
guard listenFD >= 0, bound == 0, listen(listenFD, 4) == 0 else {
    log("cannot open \(SensorWire.socketPath): \(String(cString: strerror(errno)))")
    exit(4)
}
chmod(SensorWire.socketPath, 0o666)  // anyone may knock; the uid check below decides

var clients: [(fd: Int32, uid: uid_t)] = []
var lastRefusedUID: uid_t?  // log each refused uid once, not every reconnect
var lastReport = CFAbsoluteTimeGetCurrent()

func consoleUID() -> uid_t? {
    var st = stat()
    return stat("/dev/console", &st) == 0 ? st.st_uid : nil
}

func mayRead(_ uid: uid_t) -> Bool { uid == 0 || uid == consoleUID() }

/// Fast user switching changes the console owner; a client accepted for the old user must not keep reading.
func dropStaleClients() {
    clients.removeAll { c in
        guard !mayRead(c.uid) else { return false }
        log("dropped client uid \(c.uid): no longer the console user")
        close(c.fd)
        return true
    }
}

let acceptSource = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: .main)
acceptSource.setEventHandler {
    let fd = accept(listenFD, nil, nil)
    guard fd >= 0 else { return }
    var uid: uid_t = 0, gid: gid_t = 0
    guard getpeereid(fd, &uid, &gid) == 0, mayRead(uid) else {
        if lastRefusedUID != uid { log("refused a client with uid \(uid) (not the console user)") }
        lastRefusedUID = uid
        close(fd)
        return
    }
    var big: Int32 = 256 * 1024
    setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &big, socklen_t(MemoryLayout<Int32>.size))
    _ = fcntl(fd, F_SETFL, O_NONBLOCK)
    if clients.isEmpty { wakeSPU() }
    clients.append((fd, uid))
}
acceptSource.resume()

// Samples go out in batches (≤16 records or 8 ms) so neither process wakes
// ~1600 times a second. Format: TouchMacCore/SensorWire.swift.
let recordLen = SensorWire.recordLen
let batchMax = 16
let batchAgeSec = 0.008
var batch = [UInt8](repeating: 0, count: recordLen * batchMax)
var batchTimes = [Double](repeating: 0, count: batchMax)
var batchCount = 0

func send(kind: UInt8, x: Double, y: Double, z: Double) {
    let now = CFAbsoluteTimeGetCurrent()
    lastReport = now
    guard !clients.isEmpty else { batchCount = 0; return }
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
    let len = batchCount * recordLen
    clients.removeAll { c in
        let n = batch.withUnsafeBytes { Darwin.send(c.fd, $0.baseAddress, len, 0) }
        if n == len || (n < 0 && errno == EAGAIN) { return false }  // sent, or dropped whole: stream stays aligned
        close(c.fd)  // gone, or a partial write that would misalign records: the app reconnects
        return true
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
log("streaming \(result.opened) sensors to \(SensorWire.socketPath) while the app is connected")

// ---- once a second: console-user check, stall watchdog ----
let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 1, 1, 0, 0) { _ in
    // ponytail: up to 1 s of samples can reach the old user after a switch; watch SCDynamicStore ConsoleUser if that matters
    dropStaleClients()
    let now = CFAbsoluteTimeGetCurrent()
    // ponytail: exit-and-restart is the whole sleep/stall recovery; add IOPM wake hooks if restarts prove slow
    if now - lastReport > stallSec {
        log("no reports for \(Int(now - lastReport)) s (sleep or driver reset); exiting so launchd restarts us")
        exit(2)
    }
}
CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .defaultMode)
CFRunLoopRun()
