//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public struct OWSDevice: Codable, FetchableRecord, PersistableRecord {
    public static let primaryDeviceId: UInt32 = 1

    public static let databaseTableName: String = "model_OWSDevice"

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case sqliteRowId = "id"
        case uniqueId
        case recordType

        case deviceId
        case encryptedName = "name"
        case createdAt
        case lastSeenAt
    }

    public var sqliteRowId: Int64?
    public let uniqueId: String
    public let recordType: UInt = SDSRecordType.device.rawValue

    public let deviceId: Int
    public var encryptedName: String?
    public let createdAt: Date
    public let lastSeenAt: Date

    init(
        deviceId: DeviceId,
        encryptedName: String?,
        createdAt: Date,
        lastSeenAt: Date
    ) {
        self.uniqueId = UUID().uuidString

        self.deviceId = Int(deviceId.rawValue)
        self.encryptedName = encryptedName
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
    }

    public mutating func didInsert(with rowID: Int64, for column: String?) {
        sqliteRowId = rowID
    }

#if DEBUG
    public static func previewItem(id: DeviceId) -> OWSDevice {
        OWSDevice(
            deviceId: id,
            encryptedName: nil,
            createdAt: Date().addingTimeInterval(-86_400 * TimeInterval(Int.random(in: 10...20))),
            lastSeenAt: Date().addingTimeInterval(-86_400 * TimeInterval(Int.random(in: 0...10)))
        )
    }
#endif
}

public extension OWSDevice {
    func displayName(
        identityManager: OWSIdentityManager,
        tx: DBReadTransaction
    ) -> String {
        if let encryptedName = self.encryptedName {
            if let identityKeyPair = identityManager.identityKeyPair(for: .aci, tx: tx) {
                do {
                    return try DeviceNames.decryptDeviceName(
                        base64String: encryptedName,
                        identityKeyPair: identityKeyPair.keyPair
                    )
                } catch let error {
                    Logger.error("Failed to decrypt device name: \(error). Is this a legacy device name?")
                }
            }

            return encryptedName
        }

        if deviceId == Self.primaryDeviceId {
            return OWSLocalizedString(
                "DEVICE_NAME_THIS_DEVICE",
                comment: "A label for this device in the device list."
            )
        }

        return OWSLocalizedString(
            "DEVICE_NAME_UNNAMED_DEVICE",
            comment: "A label for an unnamed device in the device list."
        )
    }

    var isPrimaryDevice: Bool {
        deviceId == Self.primaryDeviceId
    }

    var isLinkedDevice: Bool {
        !isPrimaryDevice
    }
}
