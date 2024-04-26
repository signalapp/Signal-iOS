//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension MessageBackup {
    /// An identifier for a ``BackupProto.Call`` backup frame.
    struct CallId: MessageBackupLoggableId {
        let callId: UInt64
        let conversationRecipientId: MessageBackup.RecipientId

        init(
            callId: UInt64,
            conversationRecipientId: MessageBackup.RecipientId
        ) {
            self.callId = callId
            self.conversationRecipientId = conversationRecipientId
        }

        // MARK: MessageBackupLoggableId

        public var typeLogString: String { "BackupProto.Call" }
        public var idLogString: String {
            /// Since call IDs are a cross-client identifier, we don't want to
            /// log them directly.
            let callIdHash = callId.hashValue
            return "Call ID hash: \(callIdHash), conversation: \(conversationRecipientId)"
        }
    }
}

public protocol MessageBackupCallArchiver: MessageBackupProtoArchiver {

}
