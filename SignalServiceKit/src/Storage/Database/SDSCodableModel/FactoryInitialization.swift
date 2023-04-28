//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Represents a type that may be initialized from a factory initializer that
/// used a "record type" to decide to initialize this type.
protocol FactoryInitializableFromRecordType {
    /// The record type indicating that this type should be initialized.
    static var recordType: UInt { get }

    /// Initialize from the given ``Decoder``, at the request of an upstream
    /// factory initializer.
    ///
    /// This method may safely assume the upstream initializer belongs to its
    /// superclass.
    ///
    /// This method should call an appropriate `super.init`, passing a
    /// superclass ``Decoder``.
    init(forRecordTypeFactoryInitializationFrom decoder: Decoder) throws
}

/// Represents a type that should delegate its ``Decodable`` initialization to
/// another class (which, in practice, must be a subclass) via factory
/// initialization, using a "record type" to determine which subclass to
/// initialize itself as.
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
/// ``NeedsFactoryInitializationFromRecordType`` works around this issue for
/// scenarios where our data is in a ``Decoder`` by requiring that each decoder
/// instance is known to contain a ``UInt`` "record type" that can be used to
/// pick which subclass to initialize.
///
/// ---
///
/// Note that this pattern (an initializer in a protocol extension) is required
/// to work around the fact that Swift does not support assignment to `self` in
/// class initializers.
///
/// See https://github.com/apple/swift/issues/47830 for more.
protocol NeedsFactoryInitializationFromRecordType: Decodable {
    associatedtype CodingKeys: CodingKey

    /// A key from which a `UInt` record type may be extracted from a given
    /// `Decoder`.
    static var recordTypeCodingKey: CodingKeys { get }

    /// Determine the subclass of ourself to which we should delegate
    /// initialization for a given `recordType`.
    /// - Returns
    /// The subclass type to initialize ourselves as. A `nil` result represents
    /// an error state, such as no subclass matching `recordType`.
    static func classToInitialize(
        forRecordType recordType: UInt
    ) -> (any FactoryInitializableFromRecordType.Type)?
}

extension NeedsFactoryInitializationFromRecordType {
    /// Extract a `UInt` record type from the given decoder, and use its value
    /// to delegate initialization to a subclass.
    ///
    /// Expects to be given a decoder for a subclass, and throws if the decoder
    /// does not contain a `super` decoder that in turn contains a valid and
    /// recognized record type.
    public init(from subclassDecoder: Decoder) throws {
        let subclassContainer = try subclassDecoder.container(keyedBy: CodingKeys.self)
        let baseClassDecoder = try subclassContainer.superDecoder()

        let container = try baseClassDecoder.container(keyedBy: CodingKeys.self)
        let recordType = try container.decode(UInt.self, forKey: Self.recordTypeCodingKey)

        guard let classToInitialize = Self.classToInitialize(forRecordType: recordType) else {
            let errorMessage = "No class found to initialize for recordType: \(recordType)"

            Logger.error(errorMessage)

            throw DecodingError.dataCorrupted(.init(
                codingPath: [Self.recordTypeCodingKey],
                debugDescription: errorMessage
            ))
        }

        guard recordType == classToInitialize.recordType else {
            let errorMessage = "Record type \(recordType) unexpectedly matched to class \(classToInitialize) with recordType \(classToInitialize.recordType)!"

            Logger.error(errorMessage)

            throw DecodingError.dataCorrupted(.init(
                codingPath: [Self.recordTypeCodingKey],
                debugDescription: errorMessage
            ))
        }

        let classInstance = try classToInitialize.init(forRecordTypeFactoryInitializationFrom: subclassDecoder)

        guard let selfInstance = classInstance as? Self else {
            owsFail("Factory-initialized class was not a \(Self.self)!")
        }

        self = selfInstance
    }
}
