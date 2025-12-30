//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

/// In charge of scheduling deleting attachments off the backup cdn after they've been deleted locally (or otherwise orphaned).
public protocol OrphanedBackupAttachmentScheduler {

    /// Called when creating an attachment with the provided media name, or
    /// when updating an attachment (e.g. after downloading) with the media name.
    /// Required to clean up any pending orphan delete jobs that should now be
    /// invalidated.
    ///
    /// Say we had an attachment with mediaId abcd and deleted it, without having
    /// deleted it on the backup cdn. Later, we list all backup media on the server,
    /// and see mediaId abcd there with no associated local attachment.
    /// We add it to the orphan table to schedule for deletion.
    /// Later, we either send or receive (and download) an attachment with the same
    /// mediaId (same file contents). We don't want to delete the upload anymore,
    /// so dequeue it for deletion.
    func didCreateOrUpdateAttachment(
        withMediaName mediaName: String,
        tx: DBWriteTransaction,
    )

    /// Orphan all existing media tier uploads for an attachment, marking them for
    /// deletion from the media tier CDN.
    /// Do this before wiping media tier info on an attachment. Note that this doesn't
    /// need to be done when deleting an attachment, as a SQLite trigger handles
    /// deletion automatically.
    func orphanExistingMediaTierUploads(
        of attachment: Attachment,
        tx: DBWriteTransaction,
    ) throws
}

public class OrphanedBackupAttachmentSchedulerImpl: OrphanedBackupAttachmentScheduler {

    private let accountKeyStore: AccountKeyStore
    private let orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore

    public init(
        accountKeyStore: AccountKeyStore,
        orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore,
    ) {
        self.accountKeyStore = accountKeyStore
        self.orphanedBackupAttachmentStore = orphanedBackupAttachmentStore
    }

    public func didCreateOrUpdateAttachment(
        withMediaName mediaName: String,
        tx: DBWriteTransaction,
    ) {
        try! OrphanedBackupAttachment
            .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaName) == mediaName)
            .deleteAll(tx.database)
        let mediaKey = accountKeyStore.getOrGenerateMediaRootBackupKey(tx: tx)
        for type in OrphanedBackupAttachment.SizeType.allCases {
            do {
                let mediaId = try mediaKey.deriveMediaId(
                    {
                        switch type {
                        case .fullsize:
                            mediaName
                        case .thumbnail:
                            AttachmentBackupThumbnail
                                .thumbnailMediaName(fullsizeMediaName: mediaName)
                        }
                    }(),
                )
                try! OrphanedBackupAttachment
                    .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaId) == mediaId)
                    .deleteAll(tx.database)
            } catch {
                owsFailDebug("Unexpected encryption material error")
            }

        }
    }

    public func orphanExistingMediaTierUploads(
        of attachment: Attachment,
        tx: DBWriteTransaction,
    ) throws {
        guard let mediaName = attachment.mediaName else {
            // If we didn't have a mediaName assigned,
            // there's no uploads to orphan (that we know of locally).
            return
        }
        if
            let mediaTierInfo = attachment.mediaTierInfo,
            let cdnNumber = mediaTierInfo.cdnNumber
        {
            var fullsizeOrphanRecord = OrphanedBackupAttachment.locallyOrphaned(
                cdnNumber: cdnNumber,
                mediaName: mediaName,
                type: .fullsize,
            )
            try orphanedBackupAttachmentStore.insert(&fullsizeOrphanRecord, tx: tx)
        }
        if
            let thumbnailMediaTierInfo = attachment.thumbnailMediaTierInfo,
            let cdnNumber = thumbnailMediaTierInfo.cdnNumber
        {
            var fullsizeOrphanRecord = OrphanedBackupAttachment.locallyOrphaned(
                cdnNumber: cdnNumber,
                mediaName: AttachmentBackupThumbnail.thumbnailMediaName(
                    fullsizeMediaName: mediaName,
                ),
                type: .thumbnail,
            )
            try orphanedBackupAttachmentStore.insert(&fullsizeOrphanRecord, tx: tx)
        }
    }
}

#if TESTABLE_BUILD

open class OrphanedBackupAttachmentSchedulerMock: OrphanedBackupAttachmentScheduler {

    public init() {}

    open func didCreateOrUpdateAttachment(
        withMediaName mediaName: String,
        tx: DBWriteTransaction,
    ) {
        // Do nothing
    }

    open func orphanExistingMediaTierUploads(
        of attachment: Attachment,
        tx: DBWriteTransaction,
    ) throws {
        // Do nothing
    }
}

#endif
