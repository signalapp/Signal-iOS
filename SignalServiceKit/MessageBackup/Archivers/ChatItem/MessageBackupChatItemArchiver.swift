//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol MessageBackupChatItemArchiver: MessageBackupProtoArchiver {

    typealias ChatItemId = MessageBackup.ChatItemId

    typealias ArchiveMultiFrameResult = MessageBackup.ArchiveMultiFrameResult<MessageBackup.InteractionUniqueId>

    /// Archive all ``TSInteraction``s (they map to ``BackupProtoChatItem`` and ``BackupProtoCall``).
    ///
    /// - Returns: ``ArchiveMultiFrameResult.success`` if all frames were written without error, or either
    /// partial or complete failure otherwise.
    /// How to handle ``ArchiveMultiFrameResult.partialSuccess`` is up to the caller,
    /// but typically an error will be shown to the user, but the backup will be allowed to proceed.
    /// ``ArchiveMultiFrameResult.completeFailure``, on the other hand, will stop the entire backup,
    /// and should be used if some critical or category-wide failure occurs.
    func archiveInteractions(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveMultiFrameResult

    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<ChatItemId>

    /// Restore a single ``BackupProtoChatItem`` frame.
    ///
    /// - Returns: ``RestoreFrameResult.success`` if all frames were read without error.
    /// How to handle ``RestoreFrameResult.failure`` is up to the caller,
    /// but typically an error will be shown to the user, but the restore will be allowed to proceed.
    func restore(
        _ chatItem: BackupProtoChatItem,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult
}
