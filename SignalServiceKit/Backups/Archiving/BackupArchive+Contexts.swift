//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension BackupArchive {

    /// Base context class used for archiving (creating a backup).
    ///
    /// Requires a write tx on init; we want to hold the write lock while
    /// creating a backup to avoid races with e.g. message processing.
    ///
    /// But only exposes a read tx, because we explicitly do not want
    /// archiving to be updating the database, just reading from it.
    /// (The exception to this is enqueuing attachment uploads.)
    open class ArchivingContext {

        /// For benchmarking archive steps.
        let bencher: BackupArchive.ArchiveBencher
        let attachmentByteCounter: BackupArchiveAttachmentByteCounter
        /// Parameters configuring what content is included in this archive.
        let includedContentFilter: IncludedContentFilter
        /// The timestamp at which the archiving process started.
        let startTimestampMs: UInt64
        /// Always set even if BackupPlan is free
        let currentBackupAttachmentUploadEra: String
        let tx: DBReadTransaction

        init(
            bencher: BackupArchive.ArchiveBencher,
            attachmentByteCounter: BackupArchiveAttachmentByteCounter,
            currentBackupAttachmentUploadEra: String,
            includedContentFilter: IncludedContentFilter,
            startTimestampMs: UInt64,
            tx: DBReadTransaction,
        ) {
            self.bencher = bencher
            self.attachmentByteCounter = attachmentByteCounter
            self.currentBackupAttachmentUploadEra = currentBackupAttachmentUploadEra
            self.includedContentFilter = includedContentFilter
            self.startTimestampMs = startTimestampMs
            self.tx = tx
        }
    }

    /// Base context class used for restoring from a backup.
    open class RestoringContext {

        /// The timestamp at which we began restoring.
        public let startTimestampMs: UInt64
        public let attachmentByteCounter: BackupArchiveAttachmentByteCounter
        public let isPrimaryDevice: Bool
        public let tx: DBWriteTransaction

        init(
            startTimestampMs: UInt64,
            attachmentByteCounter: BackupArchiveAttachmentByteCounter,
            isPrimaryDevice: Bool,
            tx: DBWriteTransaction,
        ) {
            self.startTimestampMs = startTimestampMs
            self.attachmentByteCounter = attachmentByteCounter
            self.isPrimaryDevice = isPrimaryDevice
            self.tx = tx
        }
    }
}
