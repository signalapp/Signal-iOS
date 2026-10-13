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
    class ArchivingContext {
        /// `LocalIdentifiers` for the user doing the archiving.
        let localIdentifiers: LocalIdentifiers
        /// The timestamp at which the archiving process started.
        let startDate: Date
        /// The remote config at the start of archiving.
        let remoteConfig: RemoteConfig
        /// The upload era at the start of archiving.
        /// - SeeAlso ``BackupAttachmentUploadEraStore``
        let currentUploadEra: String
        /// For benchmarking archive steps.
        let bencher: BackupArchive.ArchiveBencher
        /// Counts archived attachment bytes for future progress reporting.
        let attachmentByteCounter: BackupArchiveAttachmentByteCounter
        /// Parameters configuring what content is included in this archive.
        let includedContentFilter: IncludedContentFilter
        /// Tracks attachments to be written to a local-file backup. Presence indicates we are archiving a local-file backup.
        let localFileBackupAttachmentCollector: LocalFileBackupAttachmentCollector?
        /// The single transaction used to create the archive.
        let tx: DBReadTransaction

        init(
            localIdentifiers: LocalIdentifiers,
            startDate: Date,
            remoteConfig: RemoteConfig,
            currentUploadEra: String,
            bencher: BackupArchive.ArchiveBencher,
            attachmentByteCounter: BackupArchiveAttachmentByteCounter,
            includedContentFilter: IncludedContentFilter,
            localFileBackupAttachmentCollector: LocalFileBackupAttachmentCollector?,
            tx: DBReadTransaction,
        ) {
            self.localIdentifiers = localIdentifiers
            self.startDate = startDate
            self.remoteConfig = remoteConfig
            self.currentUploadEra = currentUploadEra
            self.bencher = bencher
            self.attachmentByteCounter = attachmentByteCounter
            self.includedContentFilter = includedContentFilter
            self.localFileBackupAttachmentCollector = localFileBackupAttachmentCollector
            self.tx = tx
        }
    }

    /// Base context class used for restoring from a backup.
    class RestoringContext {
        /// `LocalIdentifiers` for the user doing the restore.
        let localIdentifiers: LocalIdentifiers
        /// The timestamp at which we began restoring.
        let startDate: Date
        /// The remote config at the start of restoring.
        let remoteConfig: RemoteConfig
        /// Counts restored attachment bytes for future progress reporting.
        let attachmentByteCounter: BackupArchiveAttachmentByteCounter
        /// Are we restoring onto a primary?
        let isPrimaryDevice: Bool
        /// The single transaction used to restore the archive.
        let tx: DBWriteTransaction

        init(
            localIdentifiers: LocalIdentifiers,
            startDate: Date,
            remoteConfig: RemoteConfig,
            attachmentByteCounter: BackupArchiveAttachmentByteCounter,
            isPrimaryDevice: Bool,
            tx: DBWriteTransaction,
        ) {
            self.localIdentifiers = localIdentifiers
            self.startDate = startDate
            self.remoteConfig = remoteConfig
            self.attachmentByteCounter = attachmentByteCounter
            self.isPrimaryDevice = isPrimaryDevice
            self.tx = tx
        }
    }
}
