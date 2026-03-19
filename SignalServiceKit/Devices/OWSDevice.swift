//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB
public import LibSignalClient

public struct OWSDevice: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName: String = "Device"
    public static let databaseDateEncodingStrategy: DatabaseDateEncodingStrategy = .timeIntervalSince1970

    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case deviceId
        case name
        case createdAt
        case lastSeenAt
    }

    public let deviceId: DeviceId
    public let createdAt: Date
    public let lastSeenAt: Date
    public var name: String?

    // MARK: -

    public var displayName: String {
        if let name {
            return name
        } else if self.deviceId.isPrimary {
            return OWSLocalizedString(
                "DEVICE_NAME_THIS_DEVICE",
                comment: "A label for this device in the device list.",
            )
        } else {
            return OWSLocalizedString(
                "DEVICE_NAME_UNNAMED_DEVICE",
                comment: "A label for an unnamed device in the device list.",
            )
        }
    }
}

// MARK: -

#if DEBUG
extension OWSDevice {
    public static func previewItem(
        id: DeviceId,
        name: String,
    ) -> OWSDevice {
        OWSDevice(
            deviceId: id,
            createdAt: Date().addingTimeInterval(-86_400 * TimeInterval(Int.random(in: 10...20))),
            lastSeenAt: Date().addingTimeInterval(-86_400 * TimeInterval(Int.random(in: 0...10))),
            name: name,
        )
    }
}
#endif
