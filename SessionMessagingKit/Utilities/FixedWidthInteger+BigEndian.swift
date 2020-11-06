
internal extension FixedWidthInteger {

    init?(fromBigEndianBytes bytes: [UInt8]) {
        guard bytes.count == MemoryLayout<Self>.size else { return nil }
        self = bytes.reduce(0) { ($0 << 8) | Self($1) }
    }

    var bigEndianBytes: [UInt8] {
        return withUnsafeBytes(of: bigEndian) { [UInt8]($0) }
    }
}
