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
            tx: DBReadTransaction,
        ) {
            self.localIdentifiers = localIdentifiers
            self.startDate = startDate
            self.remoteConfig = remoteConfig
            self.currentUploadEra = currentUploadEra
            self.bencher = bencher
            self.attachmentByteCounter = attachmentByteCounter
            self.includedContentFilter = includedContentFilter
            self.tx = tx
        }
    }

    /// Base context class used for restoring from a backup.
    open class RestoringContext {
        /// `LocalIdentifiers` for the user doing the restore.
        public let localIdentifiers: LocalIdentifiers
        /// The timestamp at which we began restoring.
        public let startDate: Date
        /// The remote config at the start of restoring.
        public let remoteConfig: RemoteConfig
        /// Counts restored attachment bytes for future progress reporting.
        public let attachmentByteCounter: BackupArchiveAttachmentByteCounter
        /// Are we restoring onto a primary?
        public let isPrimaryDevice: Bool
        /// The single transaction used to restore the archive.
        public let tx: DBWriteTransaction

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
