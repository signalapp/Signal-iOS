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
        tx: DBReadTransaction,
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
        tx: DBWriteTransaction,
        file: StaticString?,
        function: StaticString?,
        line: UInt?,
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
        tx: DBWriteTransaction,
        file: StaticString?,
        function: StaticString?,
        line: UInt?,
    )
}

extension BackupAttachmentUploadScheduler {

    public func enqueueUsingHighestPriorityOwnerIfNeeded(
        _ attachment: Attachment,
        mode: BackupAttachmentUploadEnqueueMode = .fullsizeAndThumbnailAsNeeded,
        tx: DBWriteTransaction,
        file: StaticString? = #file,
        function: StaticString? = #function,
        line: UInt? = #line,
    ) throws {
        try enqueueUsingHighestPriorityOwnerIfNeeded(
            attachment,
            mode: mode,
            tx: tx,
            file: file,
            function: function,
            line: line,
        )
    }

    func enqueueIfNeededWithOwner(
        _ attachment: Attachment,
        owner: AttachmentReference.Owner,
        tx: DBWriteTransaction,
        file: StaticString? = #file,
        function: StaticString? = #function,
        line: UInt? = #line,
    ) {
        enqueueIfNeededWithOwner(
            attachment,
            owner: owner,
            tx: tx,
            file: file,
            function: function,
            line: line,
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
        tx: DBReadTransaction,
    ) -> Bool {
        guard let stream = attachment.asStream() else {
            return false
        }
        let eligibility = Eligibility(
            stream,
            currentUploadEra: currentUploadEra,
        )
        if fullsize, !eligibility.needsUploadFullsize {
            return false
        }
        if !fullsize, !eligibility.needsUploadThumbnail {
            return false
        }

        let highestPriorityEligibleOwner = self.highestPriorityEligibleOwner(
            attachment,
            tx: tx,
        )
        return highestPriorityEligibleOwner != nil
    }

    public func enqueueUsingHighestPriorityOwnerIfNeeded(
        _ attachment: Attachment,
        mode: BackupAttachmentUploadEnqueueMode,
        tx: DBWriteTransaction,
        file: StaticString? = #file,
        function: StaticString? = #function,
        line: UInt? = #line,
    ) {
        // Before we fetch references, check if the attachment is
        // eligible to begin with.
        guard let stream = attachment.asStream() else {
            if let file, let function, let line {
                Logger.info("Skipping enqueue of non-stream \(attachment.id) from \(file) \(line): \(function)")
            }
            return
        }

        let currentUploadEra = backupAttachmentUploadEraStore.currentUploadEra(tx: tx)

        let eligibility = Eligibility(
            stream,
            currentUploadEra: currentUploadEra,
        )
        guard eligibility.needsUploadFullsize || eligibility.needsUploadThumbnail else {
            if let file, let function, let line {
                Logger.info("Skipping enqueue of fullsize+thumbnail \(attachment.id) from \(file) \(line): \(function)")
            }
            return
        }

        guard
            let uploadOwnerType = highestPriorityEligibleOwner(attachment, tx: tx)
        else {
            if let file, let function, let line {
                Logger.info("No eligible owners; skipping enqueue of \(attachment.id) from \(file) \(line): \(function)")
            }
            return
        }

        if mode != .thumbnailOnly {
            if eligibility.needsUploadFullsize {
                backupAttachmentUploadStore.enqueue(
                    stream,
                    owner: uploadOwnerType,
                    fullsize: true,
                    tx: tx,
                    file: file,
                    function: function,
                    line: line,
                )
            } else if let file, let function, let line {
                Logger.info("Skipping enqueue of fullsize \(attachment.id) from \(file) \(line): \(function)")
            }
        }
        if mode != .fullsizeOnly {
            if eligibility.needsUploadThumbnail {
                backupAttachmentUploadStore.enqueue(
                    stream,
                    owner: uploadOwnerType,
                    fullsize: false,
                    tx: tx,
                    file: file,
                    function: function,
                    line: line,
                )
            } else if let file, let function, let line {
                Logger.info("Skipping enqueue of thumbnail \(attachment.id) from \(file) \(line): \(function)")
            }
        }
    }

    public func enqueueIfNeededWithOwner(
        _ attachment: Attachment,
        owner: AttachmentReference.Owner,
        tx: DBWriteTransaction,
        file: StaticString? = #file,
        function: StaticString? = #function,
        line: UInt? = #line,
    ) {
        guard let stream = attachment.asStream() else {
            if let file, let function, let line {
                Logger.info("Skipping enqueue of non-stream \(attachment.id) from \(file) \(line): \(function)")
            }
            return
        }

        let currentUploadEra = backupAttachmentUploadEraStore.currentUploadEra(tx: tx)

        let eligibility = Eligibility(
            stream,
            currentUploadEra: currentUploadEra,
        )
        guard eligibility.needsUploadFullsize || eligibility.needsUploadThumbnail else {
            if let file, let function, let line {
                Logger.info("Skipping enqueue of fullsize+thumbnail \(attachment.id) from \(file) \(line): \(function)")
            }
            return
        }

        // We only include the provided owner because this is an incremental check;
        // if some other owner made the attachment eligible for upload, it'd already
        // be enqueued. We only care if this particular owner makes it newly eligible
        // (or it was eligible both before and now, but the enqueuing it idempotent).
        guard let uploadOwnerType = self.asEligibleUploadOwnerType(owner, tx: tx) else {
            if let file, let function, let line {
                Logger.info(
                    "Passed in owner not eligible (may be eligible with other owners);"
                        + " skipping enqueue of \(attachment.id) from \(file) \(line): \(function)",
                )
            }
            return
        }

        if eligibility.needsUploadFullsize {
            backupAttachmentUploadStore.enqueue(
                stream,
                owner: uploadOwnerType,
                fullsize: true,
                tx: tx,
            )
        } else if let file, let function, let line {
            Logger.info("Skipping enqueue of fullsize \(attachment.id) from \(file) \(line): \(function)")
        }
        if eligibility.needsUploadThumbnail {
            backupAttachmentUploadStore.enqueue(
                stream,
                owner: uploadOwnerType,
                fullsize: false,
                tx: tx,
            )
        } else if let file, let function, let line {
            Logger.info("Skipping enqueue of thumbnail \(attachment.id) from \(file) \(line): \(function)")
        }
    }

    private struct Eligibility {
        let needsUploadFullsize: Bool
        let needsUploadThumbnail: Bool

        init(
            _ attachment: AttachmentStream,
            currentUploadEra: String,
        ) {
            self.needsUploadFullsize = {
                if attachment.encryptedByteCount > OWSMediaUtils.kMaxAttachmentUploadSizeBytes {
                    Logger.info("Skipping upload of too-large attachment \(attachment.id), \(attachment.encryptedByteCount) bytes")
                    return false
                }
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
        tx: DBReadTransaction,
    ) -> QueuedBackupAttachmentUpload.OwnerType? {
        switch owner {
        case .message(let messageSource):
            switch messageSource.rawMessageOwnerType {
            case .oversizeText:
                // We inline oversize text in the backup, and don't back
                // up the corresponding attachment.
                return nil
            case
                .bodyAttachment,
                .contactAvatar,
                .linkPreview,
                .quotedReplyAttachment,
                .sticker:
                break
            }

            guard
                let message = interactionStore.fetchInteraction(
                    rowId: messageSource.messageRowId,
                    tx: tx,
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
                backupPurpose: .remoteBackup,
            )
            if
                includedContentFilter.shouldSkipAttachment(
                    owningMessage: message,
                    currentTimestamp: dateProvider().ows_millisecondsSince1970,
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
        tx: DBReadTransaction,
    ) -> QueuedBackupAttachmentUpload.OwnerType? {
        // Backup uploads are prioritized by attachment owner. Find the highest
        // priority owner to use.
        var uploadOwnerType: QueuedBackupAttachmentUpload.OwnerType?
        attachmentStore.enumerateAllReferences(
            toAttachmentId: attachment.id,
            tx: tx,
        ) { reference, _ in
            guard
                let ownerType = self.asEligibleUploadOwnerType(
                    reference.owner,
                    tx: tx,
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
        tx: DBReadTransaction,
    ) -> Bool {
        return false
    }

    var enqueuedAttachmentIds = [Attachment.IDType]()

    public func enqueueUsingHighestPriorityOwnerIfNeeded(
        _ attachment: Attachment,
        mode: BackupAttachmentUploadEnqueueMode,
        tx: DBWriteTransaction,
        file: StaticString?,
        function: StaticString?,
        line: UInt?,
    ) throws {
        enqueuedAttachmentIds.append(attachment.id)
    }

    public func enqueueIfNeededWithOwner(
        _ attachment: Attachment,
        owner: AttachmentReference.Owner,
        tx: DBWriteTransaction,
        file: StaticString?,
        function: StaticString?,
        line: UInt?,
    ) {
        // Do nothing
    }
}

#endif
