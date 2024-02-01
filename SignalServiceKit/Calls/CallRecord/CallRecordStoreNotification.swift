//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct CallRecordStoreNotification {
    private enum UserInfoKeys {
        static let updateType: String = "updateType"
    }

    public struct CallRecordIdentifier {
        public let callId: UInt64
        public let threadRowId: Int64

        init(_ callRecord: CallRecord) {
            self.callId = callRecord.callId
            self.threadRowId = callRecord.threadRowId
        }
    }

    public enum UpdateType {
        case inserted
        case deleted(records: [CallRecordIdentifier])
        case statusUpdated(record: CallRecordIdentifier)
    }

    public static let name: NSNotification.Name = .init("CallRecordStoreNotification")

    public let updateType: UpdateType

    init(updateType: UpdateType) {
        self.updateType = updateType
    }

    public init?(_ notification: NSNotification) {
        guard
            notification.name == Self.name,
            let updateType = notification.userInfo?[UserInfoKeys.updateType] as? UpdateType
        else {
            return nil
        }

        self.init(updateType: updateType)
    }

    var asNotification: Notification {
        Notification(
            name: Self.name,
            userInfo: [UserInfoKeys.updateType: updateType]
        )
    }
}
