//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A type for a database row that corresponds to multiple concrete types.
///
/// This type decodes the recordType and then delegates the initialization
/// flow to the appropriate concrete type. That type must a subclass of the
/// type conforming to this protocol.
///
/// Why? Consider a class with many subclasses, which we may want to initialize
/// from a context in which we do not know the correct subclass for the data we
/// will pass to the initializer. For example, a `fetchAll()` method as follows:
///
/// ```swift
/// func fetchAll() -> [MyBaseClass] {
///     let decoders: [Data] = fetchDataBlobs()
///     return dataBlobs.map { .init($0) }
/// }
/// ```
///
/// Imagine that the various `Data` instances above should each be deserialized
/// as a different subclass of `MyBaseClass`. How do we know which subclass to
/// deserialize as, and how do we declare that in code?
///
/// ``InheritableRecord``  works around this issue for scenarios where our
/// data is in a ``Decoder`` by requiring a `recordType` that can be used to
/// pick which subclass to initialize.
protocol InheritableRecord: Decodable {
    /// A inheritance-supporting replacement for init(from decoder:).
    ///
    /// Conforming types and subclasses should implement this method as they
    /// would any other implementation of init(from decoder:).
    init(inheritableDecoder decoder: Decoder) throws

    /// Determine the subclass of ourself to which we should delegate
    /// initialization for a given `recordType`.
    ///
    /// - Returns
    /// The subclass type to initialize ourselves as. A `nil` result represents
    /// an error state, such as no subclass matching `recordType`.
    static func concreteType(forRecordType recordType: UInt) -> (any InheritableRecord.Type)?
}

private enum CodingKeys: String, CodingKey {
    case recordType
}

/// Note that this pattern (an initializer in a protocol extension) is required
/// to work around the fact that Swift does not support assignment to `self` in
/// class initializers.
///
/// See https://github.com/apple/swift/issues/47830 for more.
extension InheritableRecord {
    /// "Peek" the type of the record; invoke init(inheritableDecoder:).
    ///
    /// This extension method provides a default implementation for init(from
    /// decoder:) that extracts a `UInt` record type and uses its value to
    /// delegate initialization to a subclass.
    ///
    /// Types conforming to InheritableRecord MUST NOT override this method.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let recordType = try container.decode(UInt.self, forKey: .recordType)

        guard let classToInitialize = Self.concreteType(forRecordType: recordType) else {
            let errorMessage = "No class found to initialize for recordType: \(recordType)"
            throw DecodingError.dataCorruptedError(forKey: .recordType, in: container, debugDescription: errorMessage)
        }

        let classInstance = try classToInitialize.init(inheritableDecoder: decoder)
        guard let selfInstance = classInstance as? Self else {
            let errorMessage = "Runtime type of \(recordType) isn't a \(Self.self)"
            throw DecodingError.dataCorruptedError(forKey: .recordType, in: container, debugDescription: errorMessage)
        }
        self = selfInstance
    }
}
