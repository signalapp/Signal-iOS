//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct CallRecordStoreNotification {
    private enum UserInfoKeys {
        static let callId: String = "callId"
        static let threadRowId: String = "threadRowId"
        static let updateType: String = "updateType"
    }

    public enum UpdateType {
        case inserted
        case deleted
        case statusUpdated
    }

    public static let name: NSNotification.Name = .init("CallRecordStoreNotification")

    public let callId: UInt64
    public let threadRowId: Int64
    public let updateType: UpdateType

    init(
        callId: UInt64,
        threadRowId: Int64,
        updateType: UpdateType
    ) {
        self.callId = callId
        self.threadRowId = threadRowId
        self.updateType = updateType
    }

    public init?(_ notification: NSNotification) {
        guard
            notification.name == Self.name,
            let callId = notification.userInfo?[UserInfoKeys.callId] as? UInt64,
            let threadRowId = notification.userInfo?[UserInfoKeys.threadRowId] as? Int64,
            let updateType = notification.userInfo?[UserInfoKeys.updateType] as? UpdateType
        else {
            return nil
        }

        self.init(
            callId: callId,
            threadRowId: threadRowId,
            updateType: updateType
        )
    }

    var asNotification: Notification {
        Notification(
            name: Self.name,
            userInfo: [
                UserInfoKeys.callId: callId,
                UserInfoKeys.threadRowId: threadRowId,
                UserInfoKeys.updateType: updateType
            ]
        )
    }
}
