//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension MessageBackup {
    /// A rough sketch of an identifier for an ad-hoc call. When we actually
    /// build those and add them to the Backup, this is likely to change or
    /// become irrelevant.
    struct AdHocCallId: MessageBackupLoggableId {
        private let callId: UInt64
        private let recipientId: UInt64

        init(_ callId: UInt64, recipientId: UInt64) {
            self.callId = callId
            self.recipientId = recipientId
        }

        // MARK: MessageBackupLoggableId

        public var typeLogString: String { "BackupProto_CallLink" }
        public var idLogString: String {
            /// Since call IDs are a cross-client identifier, we don't want to
            /// log them directly.
            return "\(callId.hashValue):\(recipientId)"
        }
    }
}

protocol MessageBackupCallLinkArchiver: MessageBackupProtoArchiver {}
