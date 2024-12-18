//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class MessageBackupMessageAttachmentArchiver: MessageBackupProtoArchiver {
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>

    private let attachmentManager: AttachmentManager
    private let attachmentStore: AttachmentStore
    private let backupAttachmentDownloadManager: BackupAttachmentDownloadManager

    init(
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        backupAttachmentDownloadManager: BackupAttachmentDownloadManager
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.backupAttachmentDownloadManager = backupAttachmentDownloadManager
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
        messageId: MessageBackup.InteractionUniqueId,
        messageRowId: Int64,
        context: MessageBackup.ArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<[BackupProto_MessageAttachment]> {
        let referencedAttachments = self.fetchReferencedAttachments(
            for: .messageBodyAttachment(messageRowId: messageRowId),
            tx: context.tx
        )
        if referencedAttachments.isEmpty {
            return .success([])
        }

        let isFreeTierBackup = Self.isFreeTierBackup()
        var pointers = [BackupProto_MessageAttachment]()
        for referencedAttachment in referencedAttachments {
            let pointerProto = referencedAttachment.asBackupFilePointer(isFreeTierBackup: isFreeTierBackup)

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

        var attachmentFailures: [MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>] = []
        if !isFreeTierBackup {
            for referencedAttachment in referencedAttachments {
                do {
                    try context.enqueueAttachmentForUploadIfNeeded(referencedAttachment)
                } catch {
                    // If some attachment fails, thats ~mostly~ fine. Everything else
                    // can still go through, the one attachment just won't upload.
                    attachmentFailures.append(.archiveFrameError(
                        .failedToEnqueueAttachmentForUpload,
                        messageId
                    ))
                }
            }
        }

        if attachmentFailures.isEmpty {
            return .success(pointers)
        } else {
            return .partialFailure(pointers, attachmentFailures)
        }
    }

    public func archiveOversizeTextAttachment(
        messageRowId: Int64,
        messageId: MessageBackup.InteractionUniqueId,
        context: MessageBackup.ArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<BackupProto_FilePointer?> {
        return self.archiveSingleAttachment(
            ownerType: .oversizeText,
            messageId: messageId,
            messageRowId: messageRowId,
            context: context
        )
    }

    public func archiveLinkPreviewAttachment(
        messageRowId: Int64,
        messageId: MessageBackup.InteractionUniqueId,
        context: MessageBackup.ArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<BackupProto_FilePointer?> {
        return self.archiveSingleAttachment(
            ownerType: .linkPreview,
            messageId: messageId,
            messageRowId: messageRowId,
            context: context
        )
    }

    public func archiveQuotedReplyThumbnailAttachment(
        messageId: MessageBackup.InteractionUniqueId,
        messageRowId: Int64,
        context: MessageBackup.ArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<BackupProto_MessageAttachment?> {
        guard
            let referencedAttachment = self.fetchReferencedAttachments(
                for: .quotedReplyAttachment(messageRowId: messageRowId),
                tx: context.tx
            ).first
        else {
            return .success(nil)
        }

        let isFreeTierBackup = Self.isFreeTierBackup()
        let pointerProto = referencedAttachment.asBackupFilePointer(isFreeTierBackup: isFreeTierBackup)

        var attachmentProto = BackupProto_MessageAttachment()
        attachmentProto.pointer = pointerProto
        attachmentProto.flag = referencedAttachment.reference.renderingFlag.asBackupProtoFlag
        attachmentProto.wasDownloaded = referencedAttachment.attachment.asStream() != nil
        // NOTE: clientUuid is unecessary for quoted reply attachments.

        if !isFreeTierBackup {
            do {
                try context.enqueueAttachmentForUploadIfNeeded(referencedAttachment)
            } catch {
                // If some attachment fails, thats ~mostly~ fine. Everything else
                // can still go through, the one attachment just won't upload.
                return .partialFailure(attachmentProto, [.archiveFrameError(
                    .failedToEnqueueAttachmentForUpload,
                    messageId
                )])
            }
        }

        return .success(attachmentProto)
    }

    public func archiveContactShareAvatarAttachment(
        messageId: MessageBackup.InteractionUniqueId,
        messageRowId: Int64,
        context: MessageBackup.ArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<BackupProto_FilePointer?> {
        return self.archiveSingleAttachment(
            ownerType: .contactAvatar,
            messageId: messageId,
            messageRowId: messageRowId,
            context: context
        )
    }

    public func archiveStickerAttachment(
        messageId: MessageBackup.InteractionUniqueId,
        messageRowId: Int64,
        context: MessageBackup.ArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<BackupProto_FilePointer?> {
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
        chatItemId: MessageBackup.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        var uuidErrors = [MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>.ErrorType.InvalidProtoDataError]()
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
        chatItemId: MessageBackup.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> MessageBackup.RestoreInteractionResult<Void> {
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
        chatItemId: MessageBackup.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> MessageBackup.RestoreInteractionResult<Void> {
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
        chatItemId: MessageBackup.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> MessageBackup.RestoreInteractionResult<Void> {
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
        chatItemId: MessageBackup.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> MessageBackup.RestoreInteractionResult<Void> {
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
        chatItemId: MessageBackup.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> MessageBackup.RestoreInteractionResult<Void> {
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

    internal static func currentUploadEra() throws -> String {
        // TODO: [Backups] use actual subscription id. For now use a fixed,
        // arbitrary id, so that it never changes.
        let backupSubscriptionId = Data(repeating: 4, count: 32)
        return try Attachment.uploadEra(backupSubscriptionId: backupSubscriptionId)
    }

    internal static func isFreeTierBackup() -> Bool {
        // TODO: [Backups] need a way to check if we are a free tier user;
        // if so we only use the AttachmentLocator instead of BackupLocator.
        return !FeatureFlags.messageBackupRemoteExportAlpha
    }

    // MARK: Archiving

    private func archiveSingleAttachment(
        ownerType: AttachmentReference.MessageOwnerTypeRaw,
        messageId: MessageBackup.InteractionUniqueId,
        messageRowId: Int64,
        context: MessageBackup.ArchivingContext
    ) -> MessageBackup.ArchiveInteractionResult<BackupProto_FilePointer?> {
        guard
            let referencedAttachment = self.fetchReferencedAttachments(
                for: ownerType.with(messageRowId: messageRowId),
                tx: context.tx
            ).first
        else {
            return .success(nil)
        }

        let isFreeTierBackup = Self.isFreeTierBackup()
        let result = referencedAttachment.asBackupFilePointer(isFreeTierBackup: isFreeTierBackup)

        if !isFreeTierBackup {
            do {
                try context.enqueueAttachmentForUploadIfNeeded(referencedAttachment)
            } catch {
                // If some attachment fails, thats ~mostly~ fine. Everything else
                // can still go through, the one attachment just won't upload.
                return .partialFailure(
                    result, [.archiveFrameError(
                        .failedToEnqueueAttachmentForUpload,
                        messageId
                    )]
                )
            }
        }

        return .success(result)
    }

    // MARK: Restoring

    private func restoreAttachments(
        _ attachments: [OwnedAttachmentBackupPointerProto],
        chatItemId: MessageBackup.ChatItemId,
        context: MessageBackup.ChatItemRestoringContext
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        let uploadEra: String
        switch context.uploadEra {
        case nil:
            return .messageFailure([.restoreFrameError(.invalidProtoData(.accountDataNotFound), chatItemId)])
        case .fromProtoSubscriberId(let value), .random(let value):
            uploadEra = value
        }

        let errors = attachmentManager.createAttachmentPointers(
            from: attachments,
            uploadEra: uploadEra,
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

        do {
            try results.forEach {
                try backupAttachmentDownloadManager.enqueueIfNeeded($0, tx: context.tx)
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

extension MessageBackup.RestoreFrameError.ErrorType {

    internal static func fromAttachmentCreationError(
        _ error: OwnedAttachmentBackupPointerProto.CreationError
    ) -> Self {
        switch error {
        case .missingTransitCdnKey:
            return .invalidProtoData(.filePointerMissingTransitCdnKey)
        case .missingMediaName:
            return .invalidProtoData(.filePointerMissingMediaName)
        case .missingEncryptionKey:
            return .invalidProtoData(.filePointerMissingEncryptionKey)
        case .missingDigest:
            return .invalidProtoData(.filePointerMissingDigest)
        case .dbInsertionError(let error):
            return .databaseInsertionFailed(error)
        }
    }
}

extension ReferencedAttachment {

    internal func asBackupFilePointer(
        isFreeTierBackup: Bool
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

        let locator: BackupProto_FilePointer.OneOf_Locator
        let incrementalMacInfo: Attachment.IncrementalMacInfo?
        if
            // We only create the backup locator for non-free tier backups.
            !isFreeTierBackup,
            let mediaName = attachment.mediaName,
            let mediaTierDigest =
                attachment.mediaTierInfo?.digestSHA256Ciphertext
                ?? attachment.streamInfo?.digestSHA256Ciphertext,
            let mediaTierUnencryptedByteCount =
                attachment.mediaTierInfo?.unencryptedByteCount
                ?? attachment.streamInfo?.unencryptedByteCount
        {
            var backupLocator = BackupProto_FilePointer.BackupLocator()
            backupLocator.mediaName = mediaName
            // Backups use the same encryption key we use locally, always.
            backupLocator.key = attachment.encryptionKey
            backupLocator.digest = mediaTierDigest
            backupLocator.size = mediaTierUnencryptedByteCount

            // We may not have uploaded yet, so we may not know the cdn number.
            // Set it if we have it; its ok if we don't.
            if let cdnNumber = attachment.mediaTierInfo?.cdnNumber {
                backupLocator.cdnNumber = cdnNumber
            }

            // Include the transit tier cdn info as a fallback, but only
            // if the encryption key matches.
            // When we need this: we create a backup and don't get to copy to
            // media tier before the device dies; on restore the restoring device
            // can't find the attachment on the media tier but its on the transit
            // tier if its been less than 30 days.
            // When encryption keys don't match: if we reupload (e.g. forward) an
            // attachment after 3+ days, we rotate to a new encryption key; transit
            // tier info uses this new random key and can't be the fallback here.
            if
                let transitTierInfo = attachment.transitTierInfo,
                transitTierInfo.encryptionKey == attachment.encryptionKey
            {
                backupLocator.transitCdnKey = transitTierInfo.cdnKey
                backupLocator.transitCdnNumber = transitTierInfo.cdnNumber
            }

            locator = .backupLocator(backupLocator)
            incrementalMacInfo = attachment.mediaTierInfo?.incrementalMacInfo
        } else if
            let transitTierInfo = attachment.transitTierInfo
        {
            var transitTierLocator = BackupProto_FilePointer.AttachmentLocator()
            transitTierLocator.cdnKey = transitTierInfo.cdnKey
            transitTierLocator.cdnNumber = transitTierInfo.cdnNumber
            if transitTierInfo.uploadTimestamp > 0 {
                transitTierLocator.uploadTimestamp = transitTierInfo.uploadTimestamp
            }
            transitTierLocator.key = transitTierInfo.encryptionKey
            transitTierLocator.digest = transitTierInfo.digestSHA256Ciphertext
            if let unencryptedByteCount = transitTierInfo.unencryptedByteCount {
                transitTierLocator.size = unencryptedByteCount
            }
            locator = .attachmentLocator(transitTierLocator)
            incrementalMacInfo = transitTierInfo.incrementalMacInfo
        } else {
            locator = .invalidAttachmentLocator(BackupProto_FilePointer.InvalidAttachmentLocator())
            incrementalMacInfo = nil
        }

        proto.locator = locator

        if let incrementalMacInfo {
            proto.incrementalMac = incrementalMacInfo.mac
            proto.incrementalMacChunkSize = incrementalMacInfo.chunkSize
        }

        // Notes:
        // * incrementalMac and incrementalMacChunkSize unsupported by iOS
        return proto
    }
}
