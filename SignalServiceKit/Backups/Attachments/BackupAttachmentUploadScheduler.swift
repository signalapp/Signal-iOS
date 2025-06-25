//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum BackupAttachmentUploadEnqueueMode: Equatable {
    case fullsizeOnly
    case thumbnailOnly
    case fullsizeAndThumbnailAsNeeded
}

public protocol BackupAttachmentUploadScheduler {

    /// Returns true if the provided attachment is eligible to be uploaded
    /// to backup/media tier, independently of the current backupPlan state.
    ///
    /// - parameter fullsize: true to check eligibility to upload fullsize,
    /// false to check eligibility to upload the thumbnail.
    func isEligibleToUpload(
        _ attachment: Attachment,
        fullsize: Bool,
        currentUploadEra: String,
        tx: DBReadTransaction
    ) -> Bool

    /// "Enqueue" an attachment from a backup for upload, if needed and eligible, otherwise do nothing.
    ///
    /// Fetches all attachment owners and uses the highest priority one available.
    ///
    /// Doesn't actually trigger an upload; callers must later call
    /// ``BackupAttachmentUploadQueueRunner.backUpAllAttachments()`` to upload.
    func enqueueUsingHighestPriorityOwnerIfNeeded(
        _ attachment: Attachment,
        mode: BackupAttachmentUploadEnqueueMode,
        tx: DBWriteTransaction
    ) throws

    /// "Enqueue" an attachment from a backup for upload, if needed and eligible via the provided
    /// owner, otherwise do nothing.
    ///
    /// The attachment may or may not already be enqueued for upload using via other owners;
    /// if so the provided owner (if eligible) may increase the priority.
    ///
    /// Doesn't actually trigger an upload; callers must later call
    /// ``BackupAttachmentUploadQueueRunner.backUpAllAttachments()`` to upload.
    func enqueueIfNeededWithOwner(
        _ attachment: Attachment,
        owner: AttachmentReference.Owner,
        tx: DBWriteTransaction
    ) throws
}

extension BackupAttachmentUploadScheduler {

    public func enqueueUsingHighestPriorityOwnerIfNeeded(
        _ attachment: Attachment,
        tx: DBWriteTransaction
    ) throws {
        try enqueueUsingHighestPriorityOwnerIfNeeded(
            attachment,
            mode: .fullsizeAndThumbnailAsNeeded,
            tx: tx
        )
    }
}

public class BackupAttachmentUploadSchedulerImpl: BackupAttachmentUploadScheduler {

    private let attachmentStore: AttachmentStore
    private let backupAttachmentUploadStore: BackupAttachmentUploadStore
    private let backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore
    private let dateProvider: DateProvider
    private let interactionStore: InteractionStore

    public init(
        attachmentStore: AttachmentStore,
        backupAttachmentUploadStore: BackupAttachmentUploadStore,
        backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore,
        dateProvider: @escaping DateProvider,
        interactionStore: InteractionStore,
    ) {
        self.attachmentStore = attachmentStore
        self.backupAttachmentUploadStore = backupAttachmentUploadStore
        self.backupAttachmentUploadEraStore = backupAttachmentUploadEraStore
        self.dateProvider = dateProvider
        self.interactionStore = interactionStore
    }

    public func isEligibleToUpload(
        _ attachment: Attachment,
        fullsize: Bool,
        currentUploadEra: String,
        tx: DBReadTransaction
    ) -> Bool {
        guard let stream = attachment.asStream() else {
            return false
        }
        let eligibility = Eligibility(
            stream,
            currentUploadEra: currentUploadEra
        )
        if fullsize, !eligibility.needsUploadFullsize {
            return false
        }
        if !fullsize, !eligibility.needsUploadThumbnail {
            return false
        }

        let highestPriorityEligibleOwner = try? self.highestPriorityEligibleOwner(
            attachment,
            tx: tx
        )
        return highestPriorityEligibleOwner != nil
    }

    public func enqueueUsingHighestPriorityOwnerIfNeeded(
        _ attachment: Attachment,
        mode: BackupAttachmentUploadEnqueueMode,
        tx: DBWriteTransaction
    ) throws {
        // Before we fetch references, check if the attachment is
        // eligible to begin with.
        guard let stream = attachment.asStream() else {
            return
        }

        let currentUploadEra = backupAttachmentUploadEraStore.currentUploadEra(tx: tx)

        let eligibility = Eligibility(
            stream,
            currentUploadEra: currentUploadEra
        )
        guard eligibility.needsUploadFullsize || eligibility.needsUploadFullsize else {
            return
        }

        guard
            let uploadOwnerType = try highestPriorityEligibleOwner(attachment, tx: tx)
        else {
            return
        }

        if mode != .thumbnailOnly, eligibility.needsUploadFullsize {
            try backupAttachmentUploadStore.enqueue(
                stream,
                owner: uploadOwnerType,
                fullsize: true,
                tx: tx
            )
        }
        if mode != .fullsizeOnly, eligibility.needsUploadThumbnail {
            try backupAttachmentUploadStore.enqueue(
                stream,
                owner: uploadOwnerType,
                fullsize: false,
                tx: tx
            )
        }
    }

    public func enqueueIfNeededWithOwner(
        _ attachment: Attachment,
        owner: AttachmentReference.Owner,
        tx: DBWriteTransaction
    ) throws {
        guard let stream = attachment.asStream() else {
            return
        }

        let currentUploadEra = backupAttachmentUploadEraStore.currentUploadEra(tx: tx)

        let eligibility = Eligibility(
            stream,
            currentUploadEra: currentUploadEra
        )
        guard eligibility.needsUploadFullsize || eligibility.needsUploadThumbnail else {
            return
        }

        guard let uploadOwnerType = self.asEligibleUploadOwnerType(owner, tx: tx) else {
            return
        }

        if eligibility.needsUploadFullsize {
            try backupAttachmentUploadStore.enqueue(
                stream,
                owner: uploadOwnerType,
                fullsize: true,
                tx: tx
            )
        }
        if eligibility.needsUploadThumbnail {
            try backupAttachmentUploadStore.enqueue(
                stream,
                owner: uploadOwnerType,
                fullsize: false,
                tx: tx
            )
        }
    }

    private struct Eligibility {
        let needsUploadFullsize: Bool
        let needsUploadThumbnail: Bool

        init(
            _ attachment: AttachmentStream,
            currentUploadEra: String
        ) {
            self.needsUploadFullsize = {
                if let mediaTierInfo = attachment.attachment.mediaTierInfo {
                    return !mediaTierInfo.isUploaded(currentUploadEra: currentUploadEra)
                } else {
                    return true
                }
            }()
            self.needsUploadThumbnail = {
                if let thumbnailMediaTierInfo = attachment.attachment.thumbnailMediaTierInfo {
                    return !thumbnailMediaTierInfo.isUploaded(currentUploadEra: currentUploadEra)
                } else {
                    return AttachmentBackupThumbnail.canBeThumbnailed(attachment.attachment)
                }
            }()
        }
    }

    private func asEligibleUploadOwnerType(
        _ owner: AttachmentReference.Owner,
        tx: DBReadTransaction
    ) -> QueuedBackupAttachmentUpload.OwnerType? {
        switch owner {
        case .message(let messageSource):
            guard
                let message = interactionStore.fetchInteraction(
                    rowId: messageSource.messageRowId,
                    tx: tx
                ) as? TSMessage
            else {
                owsFailDebug("Missing message!")
                return nil
            }
            // For every owning reference, check that we _would_ include the
            // attachment for it in a remote backup. If we wouldn't, that
            // reference shouldn't be used as the anchor for upload (and if
            // it is the only reference, we shouldn't upload at all!)
            let includedContentFilter = BackupArchive.IncludedContentFilter(
                backupPurpose: .remoteBackup
            )
            if
                includedContentFilter.shouldSkipAttachment(
                    owningMessage: message,
                    currentTimestamp: dateProvider().ows_millisecondsSince1970
                )
            {
                return nil
            }
            return .message(timestamp: messageSource.receivedAtTimestamp)
        case .thread(let threadSource):
            switch threadSource {
            case .threadWallpaperImage, .globalThreadWallpaperImage:
                return .threadWallpaper
            }
        case .storyMessage:
            return nil
        }
    }

    private func highestPriorityEligibleOwner(
        _ attachment: Attachment,
        tx: DBReadTransaction
    ) throws -> QueuedBackupAttachmentUpload.OwnerType? {
        // Backup uploads are prioritized by attachment owner. Find the highest
        // priority owner to use.
        var uploadOwnerType: QueuedBackupAttachmentUpload.OwnerType?
        try attachmentStore.enumerateAllReferences(
            toAttachmentId: attachment.id,
            tx: tx
        ) { reference, _ in
            guard
                let ownerType = self.asEligibleUploadOwnerType(
                    reference.owner,
                    tx: tx
                )
            else {
                return
            }
            if uploadOwnerType?.isHigherPriority(than: ownerType) != true {
                uploadOwnerType = ownerType
            }
        }

        return uploadOwnerType
    }
}

extension Attachment.MediaTierInfo {

    public func isUploaded(currentUploadEra: String) -> Bool {
        return self.uploadEra == currentUploadEra && cdnNumber != nil
    }
}

extension Attachment.ThumbnailMediaTierInfo {

    public func isUploaded(currentUploadEra: String) -> Bool {
        return self.uploadEra == currentUploadEra
            && cdnNumber != nil
    }
}

#if TESTABLE_BUILD

open class BackupAttachmentUploadSchedulerMock: BackupAttachmentUploadScheduler {

    public init() {}

    public func isEligibleToUpload(
        _ attachment: Attachment,
        fullsize: Bool,
        currentUploadEra: String,
        tx: DBReadTransaction
    ) -> Bool {
        return false
    }

    public func enqueueUsingHighestPriorityOwnerIfNeeded(
        _ attachment: Attachment,
        mode: BackupAttachmentUploadEnqueueMode,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    public func enqueueIfNeededWithOwner(
        _ attachment: Attachment,
        owner: AttachmentReference.Owner,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }
}

#endif
