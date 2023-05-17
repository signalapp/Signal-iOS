//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Data {

    // MARK: -

    // base64url is _not_ the same as base64.  It is a
    // URL- and filename-safe variant of base64.
    //
    // See: https://tools.ietf.org/html/rfc4648#section-5
    static func data(fromBase64Url base64Url: String) throws -> Data {
        let base64 = Self.base64UrlToBase64(base64Url: base64Url)
        guard let data = Data(base64Encoded: base64) else {
            let message = "Couldn't parse base64Url."
            Logger.error(message)
            throw OWSGenericError(message)
        }
        return data
    }

    var asBase64Url: String {
        let base64 = base64EncodedString()
        return Self.base64ToBase64Url(base64: base64)
    }

    private static func base64UrlToBase64(base64Url: String) -> String {
        var base64 = base64Url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if base64.count % 4 != 0 {
            base64.append(String(repeating: "=", count: 4 - base64.count % 4))
        }
        return base64
    }

    private static func base64ToBase64Url(base64: String) -> String {
        let base64Url = base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return base64Url
    }

    func base64EncodedStringWithoutPadding() -> String {
        let resultWithPadding = base64EncodedString()
        let paddingCount = (3 - (self.count % 3)) % 3
        return String(resultWithPadding.dropLast(paddingCount))
    }
}

// MARK: -

public extension Array where Element == UInt8 {
    var asData: Data {
        return Data(self)
    }
}

// MARK: - UUID

public extension UUID {
    var data: Data {
        return withUnsafeBytes(of: self.uuid) { Data($0) }
    }
}

public extension UUID {
    init?(data: Data) {
        guard let (selfValue, _) = Self.from(data: data) else {
            owsFailDebug("Invalid UUID data")
            return nil
        }
        self = selfValue
    }

    /// Parses a `Data` value into a UUID.
    ///
    /// If `data.count` is larger than the size of a UUID, extra bytes are
    /// ignored.
    ///
    /// - Parameter data: The data for a UUID.
    /// - Returns: A tuple consisting of the UUID itself and the number of bytes
    ///   consumed from `data`.
    static func from(data: Data) -> (Self, byteCount: Int)? {
        // The `data` parameter refers to a byte-aligned memory address. The load()
        // call requires proper alignment, which therefore assumes uuid_t is
        // byte-aligned. Verify this in debug builds in case it ever changes.
        assert(MemoryLayout<uuid_t>.alignment == 1)
        let count = MemoryLayout<uuid_t>.size
        let uuidT: uuid_t? = data.withUnsafeBytes { bytes in
            guard bytes.count >= count else { return nil }
            return bytes.load(as: uuid_t.self)
        }
        guard let uuidT = uuidT else {
            return nil
        }
        return (Self(uuid: uuidT), count)
    }
}

// MARK: - FixedWidthInteger

extension FixedWidthInteger {
    init?(bigEndianData: Data) {
        guard let (selfValue, _) = Self.from(bigEndianData: bigEndianData) else {
            return nil
        }
        self = selfValue
    }

    /// Parses a big endian `Data` value into an integer.
    ///
    /// If `bigEndianData.count` is larger than the size of the underlying
    /// integer, extra bytes are ignored.
    ///
    /// - Parameter bigEndianData: The data for a big endian integer.
    /// - Returns: A tuple consisting of the integer itself and the number of
    ///   bytes consumed from `bigEndianData`.
    static func from(bigEndianData: Data) -> (Self, byteCount: Int)? {
        var bigEndianValue = Self()
        let count = withUnsafeMutableBytes(of: &bigEndianValue) { bigEndianData.copyBytes(to: $0) }
        guard count == MemoryLayout<Self>.size else {
            return nil
        }
        return (Self(bigEndian: bigEndianValue), count)
    }

    var bigEndianData: Data {
        return withUnsafeBytes(of: bigEndian) { Data($0) }
    }
}
