//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension UUID {
    /// Returns a UUIDv7, as defined in [the RFC][RFC]. Notably, v7 UUIDs embed
    /// a timestamp in the first 6 most-significant bytes, thereby allowing
    /// callers who pass sequential timestamps to construct UUIDs that are
    /// lexicographically sequential.
    ///
    /// This sequential property can be a useful optimization when the UUIDs are
    /// part of a database row and that row is indexed by the UUID. When the
    /// UUIDs are ordered in the same sequence as the row insertions the
    /// corresponding insertion into the index is always at the end of the
    /// index (`O(1)`), whereas a random UUID might be inserted anywhere in the
    /// index (`O(log n)`).
    ///
    /// [RFC]: https://www.rfc-editor.org/rfc/rfc9562.html#name-uuid-version-7
    static func v7(timestamp: UInt64) -> UUID {
        return UUID(uuid: (
            // Assign the lower six bytes of the timestamp (the bytes that change
            // the most) to the first six bytes of the UUID, in big-endian order
            // (most-significant byte first).

            // Assign timestamp to the first 6 bytes (big-endian)
            // For each of the first six bytes of the
            UInt8((timestamp >> 40) & 0xFF),
            UInt8((timestamp >> 32) & 0xFF),
            UInt8((timestamp >> 24) & 0xFF),
            UInt8((timestamp >> 16) & 0xFF),
            UInt8((timestamp >> 8) & 0xFF),
            UInt8(timestamp & 0xFF),

            // Set the next four bits to 0b0111, the required "version" for UUIDv7.
            // Set the rest of that byte to random.
            ((0b0111 as UInt8) << 4) | UInt8.random(in: 0...((1 << 4) - 1)),
            // Add a full byte of random.
            UInt8.random(in: 0...0xFF),

            // Set the next two bits to 0b10, the required "variant" for UUIDv7. Set
            // the rest of that byte to random.
            ((0b10 as UInt8) << 6) | UInt8.random(in: 0...((1 << 6) - 1)),

            // Set the remaining bytes to random.
            UInt8.random(in: 0...0xFF),
            UInt8.random(in: 0...0xFF),
            UInt8.random(in: 0...0xFF),
            UInt8.random(in: 0...0xFF),
            UInt8.random(in: 0...0xFF),
            UInt8.random(in: 0...0xFF),
            UInt8.random(in: 0...0xFF),
        ))
    }
}

extension NSUUID {
    private static var sequentialCounter: UInt64 = Date().ows_millisecondsSince1970

    @objc
    static func sequential() -> NSUUID {
        let uuid: UUID = .v7(timestamp: sequentialCounter)
        sequentialCounter += 1

        return uuid as NSUUID
    }
}
