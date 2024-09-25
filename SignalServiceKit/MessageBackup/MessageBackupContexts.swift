//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension MessageBackup {

    /// Base context class used for archiving (creating a backup).
    ///
    /// Requires a write tx on init; we want to hold the write lock while
    /// creating a backup to avoid races with e.g. message processing.
    ///
    /// But only exposes a read tx, because we explicitly do not want
    /// archiving to be updating the database, just reading from it.
    /// (The exception to this is enqueuing attachment uploads.)
    open class ArchivingContext {

        private let _tx: DBWriteTransaction

        public var tx: DBReadTransaction { _tx }

        /// Nil if not a paid backups account.
        private let currentBackupAttachmentUploadEra: String?
        private let backupAttachmentUploadManager: BackupAttachmentUploadManager

        init(
            currentBackupAttachmentUploadEra: String?,
            backupAttachmentUploadManager: BackupAttachmentUploadManager,
            tx: DBWriteTransaction
        ) {
            self.currentBackupAttachmentUploadEra = currentBackupAttachmentUploadEra
            self.backupAttachmentUploadManager = backupAttachmentUploadManager
            self._tx = tx
        }

        func enqueueAttachmentForUploadIfNeeded(_ referencedAttachment: ReferencedAttachment) throws {
            guard let currentBackupAttachmentUploadEra else {
                return
            }
            try backupAttachmentUploadManager.enqueueIfNeeded(
                referencedAttachment,
                currentUploadEra: currentBackupAttachmentUploadEra,
                tx: _tx
            )
        }
    }

    /// Base context class used for restoring from a backup.
    open class RestoringContext {
        /// Represents an action that should be taken after all `Frame`s have
        /// been restored.
        public enum PostFrameRestoreAction {
            /// A `TSInfoMessage` indicating a contact is hidden should be
            /// inserted for the `SignalRecipient` with the given SQLite row ID.
            ///
            /// We always want some in-chat indication that a hidden contact is,
            /// in fact, hidden. However, that "hidden" state is stored on a
            /// `Contact`, with no related `ChatItem`. Consequently, when we
            /// encounter a hidden `Contact` frame, we'll track that we should,
            /// after all other frames are restored, insert an in-chat message
            /// that the contact is hidden.
            case insertContactHiddenInfoMessage(recipientRowId: Int64)
        }

        public let tx: DBWriteTransaction
        public private(set) var postFrameRestoreActions: [PostFrameRestoreAction]

        init(tx: DBWriteTransaction) {
            self.tx = tx
            self.postFrameRestoreActions = []
        }

        func addPostRestoreFrameAction(_ action: PostFrameRestoreAction) {
            postFrameRestoreActions.append(action)
        }
    }
}
