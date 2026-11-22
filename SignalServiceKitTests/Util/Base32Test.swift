//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing
@testable import SignalServiceKit

struct Base32Test {
    private static let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// Test vectors from RFC 4648 section 10, with the trailing "=" padding removed.
    @Test(arguments: [
        ("", ""),
        ("f", "MY"),
        ("fo", "MZXQ"),
        ("foo", "MZXW6"),
        ("foob", "MZXW6YQ"),
        ("fooba", "MZXW6YTB"),
        ("foobar", "MZXW6YTBOI"),
    ])
    func testRFC4648Vectors(input: String, expected: String) {
        #expect(Base32.encode(Data(input.utf8)) == expected)
        #expect(Base32.decode(expected) == Data(input.utf8))
    }

    @Test(arguments: [
        "M", // 5 bits: not a whole byte, and too many leftover bits
        "MZX", // 15 bits: 7 leftover bits
        "MZXW6Y", // 30 bits: 6 leftover bits
        "MZ", // valid length, but the 2 trailing padding bits are non-zero
        "mzxw6", // lowercase is outside the alphabet
        "MZXW6===", // padding characters are not accepted
        "MZXW1", // '1' is outside the alphabet
    ])
    func testDecodeRejectsInvalidInput(input: String) {
        #expect(Base32.decode(input) == nil)
    }

    /// The SHA1 shared secret from the RFC 6238 (TOTP) test vectors, as an
    /// authenticator app would receive it.
    @Test
    func testRFC6238Secret() {
        let secret = Data("12345678901234567890".utf8)
        #expect(Base32.encode(secret) == "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ")
    }

    @Test
    func testBoundaryBytes() {
        #expect(Base32.encode(Data(repeating: 0x00, count: 5)) == "AAAAAAAA")
        #expect(Base32.encode(Data(repeating: 0xFF, count: 5)) == "77777777")
        #expect(Base32.encode(Data([0x00])) == "AA")
        #expect(Base32.encode(Data([0xFF])) == "74")
        // Each 5-bit group selects a distinct character, in order.
        #expect(Base32.encode(Data([0x00, 0x44, 0x32, 0x14, 0xC7])) == "ABCDEFGH")
    }

    /// Output must be unpadded, ceil(8n / 5) characters long, and drawn only
    /// from the RFC 4648 alphabet.
    @Test(arguments: 0...64)
    func testOutputLengthAndAlphabet(byteCount: Int) {
        let data = Data((0..<byteCount).map { _ in UInt8.random(in: .min ... .max) })
        let encoded = Base32.encode(data)
        #expect(encoded.count == (byteCount * 8 + 4) / 5)
        #expect(encoded.allSatisfy { Self.alphabet.contains($0) })
    }

    /// Encoding long random inputs and decoding them must return the
    /// original bytes.
    @Test(arguments: [1, 7, 10, 20, 32, 64, 1000])
    func testRoundTrip(byteCount: Int) throws {
        let data = Data((0..<byteCount).map { _ in UInt8.random(in: .min ... .max) })
        let decoded = try #require(Base32.decode(Base32.encode(data)))
        #expect(decoded == data)
    }
}

private extension Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// RFC 4648 base32 decoding, without padding.
    /// Returns nil if the string contains characters outside the alphabet, has a length
    /// no encoder could produce, or has non-zero trailing padding bits.
    static func decode(_ string: String) -> Data? {
        var result = Data()
        var buffer: UInt32 = 0
        var bitCount = 0
        for character in string {
            guard let value = alphabet.firstIndex(of: character) else {
                return nil
            }
            buffer = (buffer << 5) | UInt32(value)
            bitCount += 5
            // If there are 8 or more bits, add another byte to the result
            if bitCount >= 8 {
                result.append(UInt8((buffer >> UInt32(bitCount - 8)) & 0xff))
                bitCount -= 8
            }
        }
        // A valid encoding leaves at most 4 leftover bits, all of them zero.
        // (e.g. 1 or 3 characters would leave 5 or 7 bits: not a valid length.)
        guard bitCount < 5, buffer & ((1 << UInt32(bitCount)) - 1) == 0 else {
            return nil
        }
        return result
    }
}
