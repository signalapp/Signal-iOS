//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

// MARK: - Base32

enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// RFC 4648 base32 encoding, without padding.
    /// See: https://www.rfc-editor.org/info/rfc4648/#section-6
    static func encode(_ data: Data) -> String {
        var result = ""
        var buffer: UInt32 = 0
        var bitCount = 0
        for byte in data {
            buffer = (buffer << 8) | UInt32(byte)
            bitCount += 8
            while bitCount >= 5 {
                // Shift the buffer left the number of unprocessed bits
                // e.g. - buffer: 1100110011 (bitCount = 10)
                // 1100110011 >> (10 - 5) ==> '11001'
                // Int('11001' & 01f) ==> 25
                // alphabet[25] ==> 'Z'
                //
                // The next round would have bitCount = 5, shift 0 bits right,
                // and end up with the value '10011' ==> 'T'
                result.append(alphabet[Int((buffer >> UInt32(bitCount - 5)) & 0x1f)])
                bitCount -= 5
            }
        }
        if bitCount > 0 {
            result.append(alphabet[Int((buffer << UInt32(5 - bitCount)) & 0x1f)])
        }
        return result
    }
}
