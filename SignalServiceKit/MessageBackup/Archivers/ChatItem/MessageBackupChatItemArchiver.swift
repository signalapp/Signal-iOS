//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public extension MessageBackup {

    /// An identifier for a ``BackupProto_ChatItem`` backup frame.
    struct ChatItemId: MessageBackupLoggableId, Hashable {
        let value: UInt64

        public init(backupProtoChatItem: BackupProto_ChatItem) {
            self.value = backupProtoChatItem.dateSent
        }

        public init(interaction: TSInteraction) {
            self.value = interaction.timestamp
        }

        // MARK: MessageBackupLoggableId

        public var typeLogString: String { "BackupProto_ChatItem" }
        public var idLogString: String { "timestamp: \(value)" }
    }
}

public protocol MessageBackupChatItemArchiver: MessageBackupProtoArchiver {

    typealias ChatItemId = MessageBackup.ChatItemId
    typealias ArchiveMultiFrameResult = MessageBackup.ArchiveMultiFrameResult<MessageBackup.InteractionUniqueId>
    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<ChatItemId>

    /// Archive all ``TSInteraction``s (they map to ``BackupProto_ChatItem`` and ``BackupProto_Call``).
    ///
    /// - Returns: ``ArchiveMultiFrameResult.success`` if all frames were written without error, or either
    /// partial or complete failure otherwise.
    /// How to handle ``ArchiveMultiFrameResult.partialSuccess`` is up to the caller,
    /// but typically an error will be shown to the user, but the backup will be allowed to proceed.
    /// ``ArchiveMultiFrameResult.completeFailure``, on the other hand, will stop the entire backup,
    /// and should be used if some critical or category-wide failure occurs.
    func archiveInteractions(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext
    ) throws(CancellationError) -> ArchiveMultiFrameResult

    /// Restore a single ``BackupProto_ChatItem`` frame.
    ///
    /// - Returns: ``RestoreFrameResult.success`` if all frames were read without error.
    /// How to handle ``RestoreFrameResult.failure`` is up to the caller,
    /// but typically an error will be shown to the user, but the restore will be allowed to proceed.
    func restore(
        _ chatItem: BackupProto_ChatItem,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreFrameResult
}
