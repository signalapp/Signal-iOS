//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public struct OWSDevice: Codable, FetchableRecord, PersistableRecord {
    public static let primaryDeviceId: UInt32 = 1

    public static let databaseTableName: String = "OWSDevice"

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case sqliteRowId = "id"
        case deviceId
        case name
        case createdAt
        case lastSeenAt
    }

    public var sqliteRowId: Int64?
    public let deviceId: Int
    public let createdAt: Date
    public let lastSeenAt: Date
    public var name: String?

    init(
        deviceId: DeviceId,
        createdAt: Date,
        lastSeenAt: Date,
        name: String?,
    ) {
        self.deviceId = Int(deviceId.rawValue)
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.name = name
    }

    public mutating func didInsert(with rowID: Int64, for column: String?) {
        sqliteRowId = rowID
    }

    // MARK: -

    public var isPrimaryDevice: Bool {
        deviceId == Self.primaryDeviceId
    }

    public var isLinkedDevice: Bool {
        !isPrimaryDevice
    }

    public var displayName: String {
        if let name {
            return name
        } else if isPrimaryDevice {
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
