//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Wraps a `UInt64` value such that it is safe to persist using GRDB.
///
/// SQLite's underlying storage uses signed integers, and relatedly GRDB (at
/// least as of version 5.26.0) converts `UInt64` values to `Int64` internally
/// using crashing conversions. Consequently, using GRDB's Codable integration
/// to store records with `UInt64` properties will crash if the value of those
/// properties exceeds `Int64.max`.
///
/// This type works around this by reading and writing `UInt64` as `Int64` for
/// Codable purposes using bit patterns. (I.e., `UInt64` values greater than
/// `Int64.max` will be stored as negative `Int64` values.)
@propertyWrapper
public struct DBUInt64: Codable, Equatable {
    public var wrappedValue: UInt64

    public init(wrappedValue: UInt64) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        let intValue = try decoder.singleValueContainer().decode(Int64.self)
        self.wrappedValue = UInt64(bitPattern: intValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let intValue = Int64(bitPattern: wrappedValue)
        try container.encode(intValue)
    }
}

/// Like `DBUInt64`, but for optional values.
///
/// - SeeAlso ``DBUInt64``
@propertyWrapper
public struct DBUInt64Optional: Codable, Equatable {
    public var wrappedValue: UInt64?

    public init(wrappedValue: UInt64?) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        let intValue = try decoder.singleValueContainer().decode(Int64?.self)
        self.wrappedValue = intValue.map { UInt64(bitPattern: $0) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let intValue = wrappedValue.map { Int64(bitPattern: $0) }
        try container.encode(intValue)
    }
}
