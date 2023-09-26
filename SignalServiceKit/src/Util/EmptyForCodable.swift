//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Always encodes and decodes as an empty instance. Useful for legacy values
/// for which we'd like to discard any existing persisted data.
@propertyWrapper
public struct EmptyForCodable<WrappedValue: EmptyInitializable & Codable>: Codable {
    public var wrappedValue: WrappedValue

    public init(wrappedValue: WrappedValue) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        wrappedValue = WrappedValue()
    }

    public func encode(to encoder: Encoder) throws {
        try WrappedValue().encode(to: encoder)
    }
}

// MARK: - Empty initializable

/// Represents a type that can be empty-initialized.
public protocol EmptyInitializable {
    init()
}
