//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct DeviceId: Codable, Comparable, CustomStringConvertible, Hashable {
    public let rawValue: Int8

    public static let primary: DeviceId = DeviceId(validating: OWSDevice.primaryDeviceId)!

    public init?(validating rawValue: some FixedWidthInteger) {
        guard let rawValue = Int8(exactly: rawValue), rawValue >= 1 else {
            return nil
        }
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let validatedResult = Self(validating: try container.decode(Int8.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "")
        }
        self = validatedResult
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }

    public var isPrimary: Bool { self == .primary }

    public var description: String { "\(rawValue)" }

    public static func <(lhs: Self, rhs: Self) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    // The `rawValue` isn't ever negative, so these are always safe.
    public var uint8Value: UInt8 { UInt8(rawValue) }
    public var uint32Value: UInt32 { UInt32(rawValue) }
}
