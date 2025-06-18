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
    private let backupSubscriptionManager: BackupSubscriptionManager

    public init(
        attachmentStore: AttachmentStore,
        backupAttachmentUploadStore: BackupAttachmentUploadStore,
        backupSubscriptionManager: BackupSubscriptionManager,
    ) {
        self.attachmentStore = attachmentStore
        self.backupAttachmentUploadStore = backupAttachmentUploadStore
        self.backupSubscriptionManager = backupSubscriptionManager
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
        if fullsize {
            return eligibility.needsUploadFullsize
        } else {
            return eligibility.needsUploadThumbnail
        }
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

        let currentUploadEra = backupSubscriptionManager.getUploadEra(tx: tx)

        let eligibility = Eligibility(
            stream,
            currentUploadEra: currentUploadEra
        )
        guard eligibility.needsUploadFullsize || eligibility.needsUploadFullsize else {
            return
        }

        // Backup uploads are prioritized by attachment owner. Find the highest
        // priority owner to use.
        var referenceToUse: AttachmentReference?
        try attachmentStore.enumerateAllReferences(
            toAttachmentId: attachment.id,
            tx: tx
        ) { reference, _ in
            guard let ownerType = reference.owner.asUploadOwnerType() else {
                return
            }
            if referenceToUse?.owner.asUploadOwnerType()?.isHigherPriority(than: ownerType) != true {
                referenceToUse = reference
            }
        }
        guard let referenceToUse else {
            return
        }

        let referencedStream = ReferencedAttachmentStream(
            reference: referenceToUse,
            attachmentStream: stream
        )

        if mode != .thumbnailOnly, eligibility.needsUploadFullsize {
            try backupAttachmentUploadStore.enqueue(
                referencedStream,
                fullsize: true,
                tx: tx
            )
        }
        if mode != .fullsizeOnly, eligibility.needsUploadThumbnail {
            try backupAttachmentUploadStore.enqueue(
                referencedStream,
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
}

#endif
