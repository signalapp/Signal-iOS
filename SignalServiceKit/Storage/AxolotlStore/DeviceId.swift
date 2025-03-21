//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct DeviceId: Codable, Comparable, CustomStringConvertible, Hashable {
    private let rawValue: UInt32

    public static let primary: DeviceId = DeviceId(rawValue: OWSDevice.primaryDeviceId)

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(UInt32.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }

    public var description: String { "\(rawValue)" }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    public var uint32Value: UInt32 { rawValue }
}
