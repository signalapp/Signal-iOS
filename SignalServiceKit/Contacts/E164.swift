//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct E164: Equatable, Hashable, Codable, CustomDebugStringConvertible {
    public let stringValue: String

    public init?(_ stringValue: String?) {
        guard let stringValue, stringValue.isStructurallyValidE164 else {
            return nil
        }
        self.stringValue = stringValue
    }

    public init?(_ uint64Value: UInt64?) {
        guard let uint64Value else {
            return nil
        }
        let stringValue = "+" + String(uint64Value)
        guard let result = E164(stringValue) else {
            return nil
        }
        self = result
    }

    public static func expectNilOrValid(stringValue: String?) -> E164? {
        let result = E164(stringValue)
        owsAssertDebug(stringValue == nil || result != nil, "Couldn't parse an E164 that should be valid")
        return result
    }

    public var uint64Value: UInt64 {
        owsPrecondition(stringValue.first == "+")
        return UInt64(stringValue.dropFirst())!
    }

    public func encode(to encoder: Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(stringValue)
    }

    public init(from decoder: Decoder) throws {
        let stringValue = try decoder.singleValueContainer().decode(String.self)

        guard let selfValue = E164(stringValue) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: [],
                debugDescription: "Failed to construct E164 from underlying string!")
            )
        }

        self = selfValue
    }

    public var debugDescription: String { "<E164 \(stringValue)>" }
}

@objc
final public class E164ObjC: NSObject, NSCopying {
    public let wrappedValue: E164

    public init(_ wrappedValue: E164) {
        self.wrappedValue = wrappedValue
    }

    @objc
    public init?(_ stringValue: String?) {
        guard let stringValue, let wrappedValue = E164(stringValue) else {
            return nil
        }
        self.wrappedValue = wrappedValue
    }

    @objc
    public var stringValue: String { wrappedValue.stringValue }

    @objc
    public override var hash: Int { stringValue.hash }

    @objc
    public override func isEqual(_ object: Any?) -> Bool { stringValue == (object as? E164ObjC)?.stringValue }

    @objc
    public func copy(with zone: NSZone? = nil) -> Any { self }

    @objc
    public override var description: String { wrappedValue.debugDescription }
}
