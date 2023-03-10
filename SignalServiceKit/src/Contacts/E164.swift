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

    public var uint64Value: UInt64 {
        owsAssert(stringValue.first == "+")
        return UInt64(stringValue.dropFirst())!
    }

    public func encode(to encoder: Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(stringValue)
    }

    public init(from decoder: Decoder) throws {
        self.stringValue = try decoder.singleValueContainer().decode(String.self)
    }

    public var debugDescription: String { "<E164 \(stringValue)>" }
}

@objc
public class E164ObjC: NSObject, NSCopying {
    public let wrappedValue: E164

    init(_ wrappedValue: E164) {
        self.wrappedValue = wrappedValue
    }

    @objc
    init?(_ stringValue: String?) {
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
