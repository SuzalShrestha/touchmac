/// Datagram format between touchmacd and the app (UDP 127.0.0.1:48291).
/// A datagram is a batch of 17-byte records: [kind 0=accel 1=gyro][x][y][z][age],
/// Float32 little-endian; age = seconds from the sample to the send, so the receiver
/// rebuilds exact sample times on its own clock. A lone 13-byte record (no age) is
/// the v0.1 helper's format and is still accepted.
public enum SensorWire {
    public static let recordLen = 17
    public static let legacyLen = 13

    public static func write(kind: UInt8, x: Double, y: Double, z: Double,
                             into raw: UnsafeMutableRawBufferPointer, at o: Int) {
        raw[o] = kind
        raw.storeBytes(of: Float32(x).bitPattern.littleEndian, toByteOffset: o + 1, as: UInt32.self)
        raw.storeBytes(of: Float32(y).bitPattern.littleEndian, toByteOffset: o + 5, as: UInt32.self)
        raw.storeBytes(of: Float32(z).bitPattern.littleEndian, toByteOffset: o + 9, as: UInt32.self)
    }

    public static func stampAge(_ age: Double, into raw: UnsafeMutableRawBufferPointer, at o: Int) {
        raw.storeBytes(of: Float32(age).bitPattern.littleEndian, toByteOffset: o + 13, as: UInt32.self)
    }

    /// Calls `sample(kind, t, x, y, z)` for each record in the first `n` bytes.
    public static func decode(_ raw: UnsafeRawBufferPointer, count n: Int, now: Double,
                              _ sample: (UInt8, Double, Double, Double, Double) -> Void) {
        func f(_ off: Int) -> Double {
            Double(Float32(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: off, as: UInt32.self))))
        }
        if n == legacyLen {
            return sample(raw[0], now, f(1), f(5), f(9))
        }
        for i in 0..<(n / recordLen) {
            let o = i * recordLen
            sample(raw[o], now - f(o + 13), f(o + 1), f(o + 5), f(o + 9))
        }
    }
}
