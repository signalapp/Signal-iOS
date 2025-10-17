//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class BackupArchiveMessageAttachmentArchiver: BackupArchiveProtoStreamWriter {
    private typealias ArchiveFrameError = BackupArchive.ArchiveFrameError<BackupArchive.InteractionUniqueId>

    private let attachmentManager: AttachmentManager
    private let attachmentStore: AttachmentStore
    private let backupAttachmentDownloadScheduler: BackupAttachmentDownloadScheduler

    init(
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        backupAttachmentDownloadScheduler: BackupAttachmentDownloadScheduler,
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.backupAttachmentDownloadScheduler = backupAttachmentDownloadScheduler
    }

    /// We tend to deal with all attachments for a given message back-to-back, but in separate steps.
    /// To avoid multiple database round trips, we fetch all attachments for a message at once and cache
    /// the results until we get a different message row id requested.
    private var cachedAttachmentsMessageRowId: Int64?
    private var attachmentsCache = [ReferencedAttachment]()

    private func fetchReferencedAttachments(messageRowId: Int64, tx: DBReadTransaction) -> [ReferencedAttachment] {
        if let cachedAttachmentsMessageRowId, cachedAttachmentsMessageRowId == messageRowId {
            return attachmentsCache
        }
        let attachments = attachmentStore.fetchAllReferencedAttachments(
            owningMessageRowId: messageRowId,
            tx: tx
        )
        cachedAttachmentsMessageRowId = messageRowId
        attachmentsCache = attachments
        return attachments
    }

    private func fetchReferencedAttachments(for ownerId: AttachmentReference.OwnerId, tx: DBReadTransaction) -> [ReferencedAttachment] {
        let messageRowId: Int64
        switch ownerId {
        case
                .messageBodyAttachment(let rowId),
                .messageOversizeText(let rowId),
                .messageLinkPreview(let rowId),
                .quotedReplyAttachment(let rowId),
                .messageSticker(let rowId),
                .messageContactAvatar(let rowId):
            messageRowId = rowId
        case .storyMessageMedia, .storyMessageLinkPreview, .threadWallpaperImage, .globalThreadWallpaperImage:
            owsFailDebug("Invalid type in private method")
            return []
        }
        return fetchReferencedAttachments(messageRowId: messageRowId, tx: tx)
            .filter { referencedAttachment in
                referencedAttachment.reference.owner.id == ownerId
            }
    }

    // MARK: - Archiving

    func archiveBodyAttachments(
        messageId: BackupArchive.InteractionUniqueId,
        messageRowId: Int64,
        context: BackupArchive.ArchivingContext
    ) -> BackupArchive.ArchiveInteractionResult<[BackupProto_MessageAttachment]> {
        let referencedAttachments = self.fetchReferencedAttachments(
            for: .messageBodyAttachment(messageRowId: messageRowId),
            tx: context.tx
        )
        if referencedAttachments.isEmpty {
            return .success([])
        }

        var pointers = [BackupProto_MessageAttachment]()
        for referencedAttachment in referencedAttachments {
            let pointerProto = referencedAttachment.asBackupFilePointer(
                currentBackupAttachmentUploadEra: context.currentBackupAttachmentUploadEra,
                attachmentByteCounter: context.attachmentByteCounter,
            )

            var attachmentProto = BackupProto_MessageAttachment()
            attachmentProto.pointer = pointerProto
            attachmentProto.flag = referencedAttachment.reference.renderingFlag.asBackupProtoFlag
            attachmentProto.wasDownloaded = referencedAttachment.attachment.asStream() != nil

            switch referencedAttachment.reference.owner {
            case .message(.bodyAttachment(let metadata)):
                metadata.idInOwner.map { attachmentProto.clientUuid = $0.data }
            default:
                // Technically this is an error, but ignoring right now doesn't hurt.
                continue
            }

            pointers.append(attachmentProto)
        }

        return .success(pointers)
    }

    public func archiveOversizeTextAttachment(
        _ referencedAttachment: ReferencedAttachment,
        context: BackupArchive.ArchivingContext
    ) -> BackupArchive.ArchiveInteractionResult<BackupProto_FilePointer?> {
        return .success(referencedAttachment.asBackupFilePointer(
            currentBackupAttachmentUploadEra: context.currentBackupAttachmentUploadEra,
            attachmentByteCounter: context.attachmentByteCounter,
        ))
    }

    public func archiveLinkPreviewAttachment(
        messageRowId: Int64,
        messageId: BackupArchive.InteractionUniqueId,
        context: BackupArchive.ArchivingContext
    ) -> BackupArchive.ArchiveInteractionResult<BackupProto_FilePointer?> {
        return self.archiveSingleAttachment(
            ownerType: .linkPreview,
            messageId: messageId,
            messageRowId: messageRowId,
            context: context
        )
    }

    public func archiveQuotedReplyThumbnailAttachment(
        messageId: BackupArchive.InteractionUniqueId,
        messageRowId: Int64,
        context: BackupArchive.ArchivingContext
    ) -> BackupArchive.ArchiveInteractionResult<BackupProto_MessageAttachment?> {
        guard
            let referencedAttachment = self.fetchReferencedAttachments(
                for: .quotedReplyAttachment(messageRowId: messageRowId),
                tx: context.tx
            ).first
        else {
            return .success(nil)
        }

        let pointerProto = referencedAttachment.asBackupFilePointer(
            currentBackupAttachmentUploadEra: context.currentBackupAttachmentUploadEra,
            attachmentByteCounter: context.attachmentByteCounter
        )

        var attachmentProto = BackupProto_MessageAttachment()
        attachmentProto.pointer = pointerProto
        attachmentProto.flag = referencedAttachment.reference.renderingFlag.asBackupProtoFlag
        attachmentProto.wasDownloaded = referencedAttachment.attachment.asStream() != nil
        // NOTE: clientUuid is unecessary for quoted reply attachments.

        return .success(attachmentProto)
    }

    public func archiveContactShareAvatarAttachment(
        messageId: BackupArchive.InteractionUniqueId,
        messageRowId: Int64,
        context: BackupArchive.ArchivingContext
    ) -> BackupArchive.ArchiveInteractionResult<BackupProto_FilePointer?> {
        return self.archiveSingleAttachment(
            ownerType: .contactAvatar,
            messageId: messageId,
            messageRowId: messageRowId,
            context: context
        )
    }

    public func archiveStickerAttachment(
        messageId: BackupArchive.InteractionUniqueId,
        messageRowId: Int64,
        context: BackupArchive.ArchivingContext
    ) -> BackupArchive.ArchiveInteractionResult<BackupProto_FilePointer?> {
        return self.archiveSingleAttachment(
            ownerType: .sticker,
            messageId: messageId,
            messageRowId: messageRowId,
            context: context
        )
    }

    // MARK: Restoring

    public func restoreBodyAttachments(
        _ attachments: [BackupProto_MessageAttachment],
        chatItemId: BackupArchive.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext
    ) -> BackupArchive.RestoreInteractionResult<Void> {
        var uuidErrors = [BackupArchive.RestoreFrameError<BackupArchive.ChatItemId>.ErrorType.InvalidProtoDataError]()
        let withUnwrappedUUIDs: [(BackupProto_MessageAttachment, UUID?)]
        withUnwrappedUUIDs = attachments.map { attachment in
            if attachment.hasClientUuid {
                guard let uuid = UUID(data: attachment.clientUuid) else {
                    uuidErrors.append(.invalidAttachmentClientUUID)
                    return (attachment, nil)
                }
                return (attachment, uuid)
            } else {
                return (attachment, nil)
            }
        }
        guard uuidErrors.isEmpty else {
            return .messageFailure(uuidErrors.map {
                .restoreFrameError(.invalidProtoData($0), chatItemId)
            })
        }

        let ownedAttachments = withUnwrappedUUIDs.map { attachment, clientUUID in
            return OwnedAttachmentBackupPointerProto(
                proto: attachment.pointer,
                renderingFlag: attachment.flag.asAttachmentFlag,
                clientUUID: clientUUID,
                owner: .messageBodyAttachment(.init(
                    messageRowId: messageRowId,
                    receivedAtTimestamp: message.receivedAtTimestamp,
                    threadRowId: thread.threadRowId,
                    isViewOnce: message.isViewOnceMessage,
                    isPastEditRevision: message.isPastEditRevision()
                ))
            )
        }

        return restoreAttachments(
            ownedAttachments,
            chatItemId: chatItemId,
            context: context
        )
    }

    public func restoreOversizeTextAttachment(
        _ attachment: BackupProto_FilePointer,
        chatItemId: BackupArchive.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext
    ) -> BackupArchive.RestoreInteractionResult<Void> {
        let ownedAttachment = OwnedAttachmentBackupPointerProto(
            proto: attachment,
            // Oversize text attachments have no flags
            renderingFlag: .default,
            // ClientUUID is only for body and quoted reply attachments.
            clientUUID: nil,
            owner: .messageOversizeText(.init(
                messageRowId: messageRowId,
                receivedAtTimestamp: message.receivedAtTimestamp,
                threadRowId: thread.threadRowId,
                isPastEditRevision: message.isPastEditRevision()
            ))
        )

        return restoreAttachments(
            [ownedAttachment],
            chatItemId: chatItemId,
            context: context
        )
    }

    public func restoreQuotedReplyThumbnailAttachment(
        _ attachment: BackupProto_MessageAttachment,
        chatItemId: BackupArchive.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext
    ) -> BackupArchive.RestoreInteractionResult<Void> {
        let clientUUID: UUID?
        if attachment.hasClientUuid {
            guard let uuid = UUID(data: attachment.clientUuid) else {
                return .messageFailure([.restoreFrameError(
                    .invalidProtoData(.invalidAttachmentClientUUID),
                    chatItemId
                )])
            }
            clientUUID = uuid
        } else {
            clientUUID = nil
        }

        let ownedAttachment = OwnedAttachmentBackupPointerProto(
            proto: attachment.pointer,
            renderingFlag: attachment.flag.asAttachmentFlag,
            clientUUID: clientUUID,
            owner: .quotedReplyAttachment(.init(
                messageRowId: messageRowId,
                receivedAtTimestamp: message.receivedAtTimestamp,
                threadRowId: thread.threadRowId,
                isPastEditRevision: message.isPastEditRevision()
            ))
        )

        return restoreAttachments(
            [ownedAttachment],
            chatItemId: chatItemId,
            context: context
        )
    }

    public func restoreLinkPreviewAttachment(
        _ attachment: BackupProto_FilePointer,
        chatItemId: BackupArchive.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext
    ) -> BackupArchive.RestoreInteractionResult<Void> {
        let ownedAttachment = OwnedAttachmentBackupPointerProto(
            proto: attachment,
            // Link previews have no flags
            renderingFlag: .default,
            // ClientUUID is only for body and quoted reply attachments.
            clientUUID: nil,
            owner: .messageLinkPreview(.init(
                messageRowId: messageRowId,
                receivedAtTimestamp: message.receivedAtTimestamp,
                threadRowId: thread.threadRowId,
                isPastEditRevision: message.isPastEditRevision()
            ))
        )

        return restoreAttachments(
            [ownedAttachment],
            chatItemId: chatItemId,
            context: context
        )
    }

    public func restoreContactAvatarAttachment(
        _ attachment: BackupProto_FilePointer,
        chatItemId: BackupArchive.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext
    ) -> BackupArchive.RestoreInteractionResult<Void> {
        let ownedAttachment = OwnedAttachmentBackupPointerProto(
            proto: attachment,
            // Contact share avatars have no flags
            renderingFlag: .default,
            // ClientUUID is only for body and quoted reply attachments.
            clientUUID: nil,
            owner: .messageContactAvatar(.init(
                messageRowId: messageRowId,
                receivedAtTimestamp: message.receivedAtTimestamp,
                threadRowId: thread.threadRowId,
                isPastEditRevision: message.isPastEditRevision()
            ))
        )

        return restoreAttachments(
            [ownedAttachment],
            chatItemId: chatItemId,
            context: context
        )
    }

    public func restoreStickerAttachment(
        _ attachment: BackupProto_FilePointer,
        stickerPackId: Data,
        stickerId: UInt32,
        chatItemId: BackupArchive.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext
    ) -> BackupArchive.RestoreInteractionResult<Void> {
        let ownedAttachment = OwnedAttachmentBackupPointerProto(
            proto: attachment,
            // Sticker messages have no flags
            renderingFlag: .default,
            // ClientUUID is only for body and quoted reply attachments.
            clientUUID: nil,
            owner: .messageSticker(.init(
                messageRowId: messageRowId,
                receivedAtTimestamp: message.receivedAtTimestamp,
                threadRowId: thread.threadRowId,
                isPastEditRevision: message.isPastEditRevision(),
                stickerPackId: stickerPackId,
                stickerId: stickerId
            ))
        )

        return restoreAttachments(
            [ownedAttachment],
            chatItemId: chatItemId,
            context: context
        )
    }

    // MARK: - Private

    // MARK: Archiving

    private func archiveSingleAttachment(
        ownerType: AttachmentReference.MessageOwnerTypeRaw,
        messageId: BackupArchive.InteractionUniqueId,
        messageRowId: Int64,
        context: BackupArchive.ArchivingContext
    ) -> BackupArchive.ArchiveInteractionResult<BackupProto_FilePointer?> {
        guard
            let referencedAttachment = self.fetchReferencedAttachments(
                for: ownerType.with(messageRowId: messageRowId),
                tx: context.tx
            ).first
        else {
            return .success(nil)
        }

        let result = referencedAttachment.asBackupFilePointer(
            currentBackupAttachmentUploadEra: context.currentBackupAttachmentUploadEra,
            attachmentByteCounter: context.attachmentByteCounter,
        )

        return .success(result)
    }

    // MARK: Restoring

    private func restoreAttachments(
        _ attachments: [OwnedAttachmentBackupPointerProto],
        chatItemId: BackupArchive.ChatItemId,
        context: BackupArchive.ChatItemRestoringContext
    ) -> BackupArchive.RestoreInteractionResult<Void> {
        // Whether we're free or paid this should be set when we restored the account data frame.
        guard let uploadEra = context.chatContext.customChatColorContext.accountDataContext.uploadEra else {
            return .messageFailure([.restoreFrameError(.invalidProtoData(.accountDataNotFound), chatItemId)])
        }

        let errors = attachmentManager.createAttachmentPointers(
            from: attachments,
            uploadEra: uploadEra,
            attachmentByteCounter: context.attachmentByteCounter,
            tx: context.tx
        )

        guard errors.isEmpty else {
            // Treat attachment failures as message failures; a message
            // might have _only_ attachments and without them its invalid.
            return .messageFailure(errors.map {
                return .restoreFrameError(
                    .fromAttachmentCreationError($0),
                    chatItemId
                )
            })
        }

        let results: [ReferencedAttachment]
        if
            attachments.count == 1,
            let attachment = attachments.first,
            case let .messageBodyAttachment(messageRowId) = attachment.owner.id,
            attachment.proto.contentType == MimeType.textXSignalPlain.rawValue
        {
            // A single body attachment thats of type text gets swizzled to a long
            // text attachment.
            results = attachmentStore.fetchReferencedAttachments(
                for: .messageOversizeText(messageRowId: messageRowId),
                tx: context.tx
            )
        } else {
            results = attachmentStore.fetchReferencedAttachments(owners: attachments.map(\.owner.id), tx: context.tx)
        }
        if results.isEmpty && !attachments.isEmpty {
            return .messageFailure([.restoreFrameError(
                .failedToCreateAttachment,
                chatItemId
            )])
        }

        let accountDataContext = context.chatContext.customChatColorContext.accountDataContext
        guard let backupPlan = accountDataContext.backupPlan else {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(
                    .accountDataNotFound
                ),
                chatItemId
            )])
        }

        do {
            try results.forEach {
                try backupAttachmentDownloadScheduler.enqueueFromBackupIfNeeded(
                    $0,
                    restoreStartTimestampMs: context.startTimestampMs,
                    backupPlan: backupPlan,
                    remoteConfig: accountDataContext.currentRemoteConfig,
                    isPrimaryDevice: context.isPrimaryDevice,
                    tx: context.tx
                )
            }
        } catch {
            return .partialRestore((), [.restoreFrameError(
                .failedToEnqueueAttachmentDownload(error),
                chatItemId
            )])
        }

        return .success(())
    }
}

extension BackupProto_MessageAttachment.Flag {

    fileprivate var asAttachmentFlag: AttachmentReference.RenderingFlag {
        switch self {
        case .none, .UNRECOGNIZED:
            return .default
        case .voiceMessage:
            return .voiceMessage
        case .borderless:
            return .borderless
        case .gif:
            return .shouldLoop
        }
    }
}

extension AttachmentReference.RenderingFlag {

    fileprivate var asBackupProtoFlag: BackupProto_MessageAttachment.Flag {
        switch self {
        case .default:
            return .none
        case .voiceMessage:
            return .voiceMessage
        case .borderless:
            return .borderless
        case .shouldLoop:
            return .gif
        }
    }
}

extension BackupArchive.RestoreFrameError.ErrorType {

    internal static func fromAttachmentCreationError(
        _ error: OwnedAttachmentBackupPointerProto.CreationError
    ) -> Self {
        switch error {
        case .dbInsertionError(let error):
            return .databaseInsertionFailed(error)
        }
    }
}

extension ReferencedAttachment {

    internal func asBackupFilePointer(
        currentBackupAttachmentUploadEra: String,
        attachmentByteCounter: BackupArchiveAttachmentByteCounter
    ) -> BackupProto_FilePointer {
        var proto = BackupProto_FilePointer()
        proto.contentType = attachment.mimeType
        if let sourceFilename = reference.sourceFilename {
            proto.fileName = sourceFilename
        }
        if let caption = reference.legacyMessageCaption {
            proto.caption = caption
        }
        if let blurHash = attachment.blurHash {
            proto.blurHash = blurHash
        }

        switch attachment.streamInfo?.contentType {
        case
                .animatedImage(let pixelSize),
                .image(let pixelSize),
                .video(_, let pixelSize, _):
            proto.width = UInt32(pixelSize.width)
            proto.height = UInt32(pixelSize.height)
        case .audio, .file, .invalid:
            break
        case nil:
            if let mediaSize = reference.sourceMediaSizePixels {
                proto.width = UInt32(mediaSize.width)
                proto.height = UInt32(mediaSize.height)
            }
        }

        proto.locatorInfo = self.asBackupFilePointerLocatorInfo(currentBackupAttachmentUploadEra: currentBackupAttachmentUploadEra)

        if
            attachment.mediaName != nil,
            let unencryptedByteCount =
                attachment.streamInfo?.unencryptedByteCount
                ?? attachment.mediaTierInfo?.unencryptedByteCount
        {
            attachmentByteCounter.addToByteCount(
                attachmentID: attachment.id,
                byteCount: Cryptography.estimatedMediaTierCDNSize(unencryptedSize: UInt64(safeCast: unencryptedByteCount)) ?? UInt64(UInt32.max),
            )
        }

        // Notes:
        // * incrementalMac and incrementalMacChunkSize unsupported by iOS
        return proto
    }

    private func asBackupFilePointerLocatorInfo(
        currentBackupAttachmentUploadEra: String
    ) -> BackupProto_FilePointer.LocatorInfo {
        var locatorInfo = BackupProto_FilePointer.LocatorInfo()

        // Include the transit tier cdn info as a fallback, but only
        // if the encryption key matches.
        // When we need this: we create a backup and don't get to copy to
        // media tier before the device dies; on restore the restoring device
        // can't find the attachment on the media tier but its on the transit
        // tier if its been less than 30 days.
        // When encryption keys don't match: if we reupload (e.g. forward) an
        // attachment after 3+ days, we rotate to a new encryption key; transit
        // tier info uses this new random key and can't be the fallback here.
        let transitTierInfoToExport: Attachment.TransitTierInfo?
        if
            let latestTransitTierInfo = attachment.latestTransitTierInfo,
            latestTransitTierInfo.encryptionKey == attachment.encryptionKey
        {
            transitTierInfoToExport = latestTransitTierInfo
        } else if let originalTransitTierInfo = attachment.originalTransitTierInfo {
            transitTierInfoToExport = originalTransitTierInfo
        } else {
            transitTierInfoToExport = nil
        }

        if let transitTierInfoToExport {
            locatorInfo.transitCdnKey = transitTierInfoToExport.cdnKey
            locatorInfo.transitCdnNumber = transitTierInfoToExport.cdnNumber
            locatorInfo.transitTierUploadTimestamp = transitTierInfoToExport.uploadTimestamp
            // We may overwrite this below with plaintext hash integrity check,
            // which is desired. We only use encrypted digest integrity check
            // if we don't have a plaintext hash and DO have a transit tier upload.
            switch transitTierInfoToExport.integrityCheck {
            case .digestSHA256Ciphertext(let data):
                locatorInfo.integrityCheck = .encryptedDigest(data)
            case .sha256ContentHash(let data):
                locatorInfo.integrityCheck = .plaintextHash(data)
            }
        }

        // If we have absolutely no present-time source of data
        // for this attachment, even if we have a plaintext hash because
        // we _previously_ had data, don't bother exporting it. Its unrecoverable.
        let isTotallyMissingAttachment =
            attachment.streamInfo == nil
            && transitTierInfoToExport == nil
            && attachment.mediaTierInfo == nil

        if !isTotallyMissingAttachment, let plaintextHash = attachment.sha256ContentHash {
            locatorInfo.integrityCheck = .plaintextHash(plaintextHash)
            if let mediaTierCdnNumber = attachment.mediaTierInfo?.cdnNumber {
                locatorInfo.mediaTierCdnNumber = mediaTierCdnNumber
            }
        }

        // Set fields only if some cdn info is available.
        switch locatorInfo.integrityCheck {
        case .plaintextHash, .encryptedDigest:
            locatorInfo.key = attachment.encryptionKey

            if
                let unencryptedByteCount = attachment.streamInfo?.unencryptedByteCount
                    ?? attachment.mediaTierInfo?.unencryptedByteCount
                    ?? attachment.latestTransitTierInfo?.unencryptedByteCount
            {
                locatorInfo.size = unencryptedByteCount
            }
        case .none:
            break
        }

        return locatorInfo
    }
}
