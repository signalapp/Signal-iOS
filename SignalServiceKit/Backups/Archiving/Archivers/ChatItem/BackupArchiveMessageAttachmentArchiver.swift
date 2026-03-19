//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

class BackupArchiveMessageAttachmentArchiver: BackupArchiveProtoStreamWriter {
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

    // MARK: - Archiving

    func archiveBodyAttachments(
        referencedAttachments: [ReferencedAttachment],
        context: BackupArchive.ArchivingContext,
    ) -> [BackupProto_MessageAttachment] {
        var pointers = [BackupProto_MessageAttachment]()

        for referencedAttachment in referencedAttachments {
            let pointerProto = referencedAttachment.asBackupFilePointer(
                context: context,
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

        return pointers
    }

    func archiveOversizeTextAttachment(
        referencedAttachment: ReferencedAttachment,
        context: BackupArchive.ArchivingContext,
    ) -> BackupProto_FilePointer {
        return referencedAttachment.asBackupFilePointer(context: context)
    }

    func archiveLinkPreviewAttachment(
        referencedAttachment: ReferencedAttachment,
        context: BackupArchive.ArchivingContext,
    ) -> BackupProto_FilePointer {
        return referencedAttachment.asBackupFilePointer(context: context)
    }

    func archiveQuotedReplyThumbnailAttachment(
        referencedAttachment: ReferencedAttachment,
        context: BackupArchive.ArchivingContext,
    ) -> BackupProto_MessageAttachment {
        let pointerProto = referencedAttachment.asBackupFilePointer(context: context)

        var attachmentProto = BackupProto_MessageAttachment()
        attachmentProto.pointer = pointerProto
        attachmentProto.flag = referencedAttachment.reference.renderingFlag.asBackupProtoFlag
        attachmentProto.wasDownloaded = referencedAttachment.attachment.asStream() != nil
        // NOTE: clientUuid is unecessary for quoted reply attachments.

        return attachmentProto
    }

    func archiveContactAvatar(
        referencedAttachment: ReferencedAttachment,
        context: BackupArchive.ArchivingContext,
    ) -> BackupProto_FilePointer {
        return referencedAttachment.asBackupFilePointer(context: context)
    }

    func archiveStickerAttachment(
        referencedAttachment: ReferencedAttachment,
        context: BackupArchive.ArchivingContext,
    ) -> BackupProto_FilePointer {
        return referencedAttachment.asBackupFilePointer(context: context)
    }

    // MARK: Restoring -

    func restoreBodyAttachments(
        _ attachments: [BackupProto_MessageAttachment],
        chatItemId: BackupArchive.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
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

        let ownedAttachments = withUnwrappedUUIDs.enumerated().map { idx, withUnwrappedUUID in
            let (attachment, clientUUID) = withUnwrappedUUID
            return OwnedAttachmentBackupPointerProto(
                proto: attachment.pointer,
                renderingFlag: attachment.flag.asAttachmentFlag,
                clientUUID: clientUUID,
                owner: .messageBodyAttachment(.init(
                    messageRowId: messageRowId,
                    receivedAtTimestamp: message.receivedAtTimestamp,
                    threadRowId: thread.threadRowId,
                    isViewOnce: message.isViewOnceMessage,
                    isPastEditRevision: message.isPastEditRevision(),
                    orderInMessage: UInt32(idx),
                )),
            )
        }

        return restoreAttachments(
            ownedAttachments,
            chatItemId: chatItemId,
            context: context,
        )
    }

    func restoreOversizeTextAttachment(
        _ attachment: BackupProto_FilePointer,
        chatItemId: BackupArchive.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
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
                isPastEditRevision: message.isPastEditRevision(),
            )),
        )

        return restoreAttachments(
            [ownedAttachment],
            chatItemId: chatItemId,
            context: context,
        )
    }

    func restoreQuotedReplyThumbnailAttachment(
        _ attachment: BackupProto_MessageAttachment,
        chatItemId: BackupArchive.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> BackupArchive.RestoreInteractionResult<Void> {
        let clientUUID: UUID?
        if attachment.hasClientUuid {
            guard let uuid = UUID(data: attachment.clientUuid) else {
                return .messageFailure([.restoreFrameError(
                    .invalidProtoData(.invalidAttachmentClientUUID),
                    chatItemId,
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
                isPastEditRevision: message.isPastEditRevision(),
            )),
        )

        return restoreAttachments(
            [ownedAttachment],
            chatItemId: chatItemId,
            context: context,
        )
    }

    func restoreLinkPreviewAttachment(
        _ attachment: BackupProto_FilePointer,
        chatItemId: BackupArchive.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
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
                isPastEditRevision: message.isPastEditRevision(),
            )),
        )

        return restoreAttachments(
            [ownedAttachment],
            chatItemId: chatItemId,
            context: context,
        )
    }

    func restoreContactAvatarAttachment(
        _ attachment: BackupProto_FilePointer,
        chatItemId: BackupArchive.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
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
                isPastEditRevision: message.isPastEditRevision(),
            )),
        )

        return restoreAttachments(
            [ownedAttachment],
            chatItemId: chatItemId,
            context: context,
        )
    }

    func restoreStickerAttachment(
        _ attachment: BackupProto_FilePointer,
        stickerPackId: Data,
        stickerId: UInt32,
        chatItemId: BackupArchive.ChatItemId,
        messageRowId: Int64,
        message: TSMessage,
        thread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
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
                stickerId: stickerId,
            )),
        )

        return restoreAttachments(
            [ownedAttachment],
            chatItemId: chatItemId,
            context: context,
        )
    }

    private func restoreAttachments(
        _ attachments: [OwnedAttachmentBackupPointerProto],
        chatItemId: BackupArchive.ChatItemId,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> BackupArchive.RestoreInteractionResult<Void> {
        // Whether we're free or paid this should be set when we restored the account data frame.
        guard let uploadEra = context.chatContext.customChatColorContext.accountDataContext.uploadEra else {
            return .messageFailure([.restoreFrameError(.invalidProtoData(.accountDataNotFound), chatItemId)])
        }

        for attachment in attachments {
            attachmentManager.createAttachmentPointer(
                from: attachment,
                uploadEra: uploadEra,
                attachmentByteCounter: context.attachmentByteCounter,
                tx: context.tx,
            )
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
                tx: context.tx,
            )
        } else {
            results = attachmentStore.fetchReferencedAttachments(owners: attachments.map(\.owner.id), tx: context.tx)
        }
        if results.isEmpty, !attachments.isEmpty {
            return .messageFailure([.restoreFrameError(
                .failedToCreateAttachment,
                chatItemId,
            )])
        }

        guard let backupPlan = context.accountDataContext.backupPlan else {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.accountDataNotFound),
                chatItemId,
            )])
        }

        for referencedAttachment in results {
            backupAttachmentDownloadScheduler.enqueueFromBackupIfNeeded(
                referencedAttachment,
                restoreStartTimestampMs: context.startDate.ows_millisecondsSince1970,
                backupPlan: backupPlan,
                remoteConfig: context.remoteConfig,
                isPrimaryDevice: context.isPrimaryDevice,
                tx: context.tx,
            )
        }

        return .success(())
    }
}

// MARK: -

extension BackupProto_MessageAttachment.Flag {

    var asAttachmentFlag: AttachmentReference.RenderingFlag {
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

extension ReferencedAttachment {

    func asBackupFilePointer(
        context: BackupArchive.ArchivingContext,
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

        proto.locatorInfo = self.asBackupFilePointerLocatorInfo(context: context)

        if
            let mediaTierInfo = attachment.mediaTierInfo,
            mediaTierInfo.isUploaded(currentUploadEra: context.currentUploadEra)
        {
            let estimatedMediaTierSize = Cryptography.estimatedMediaTierCDNSize(
                unencryptedSize: UInt64(safeCast: mediaTierInfo.unencryptedByteCount),
            ) ?? UInt64(UInt32.max)

            context.attachmentByteCounter.addToByteCount(
                attachmentID: attachment.id,
                byteCount: estimatedMediaTierSize,
            )
        }

        // Notes:
        // * incrementalMac and incrementalMacChunkSize unsupported by iOS
        return proto
    }

    private func asBackupFilePointerLocatorInfo(
        context: BackupArchive.ArchivingContext,
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
        var transitTierInfoToExport: Attachment.TransitTierInfo?
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

        if
            let transitTierUploadDate = transitTierInfoToExport.map({ Date(millisecondsSince1970: $0.uploadTimestamp) }),
            transitTierUploadDate.addingTimeInterval(context.remoteConfig.messageQueueTime) < context.startDate
        {
            // This transit tier info is expired, so there's no point in
            // exporting it.
            transitTierInfoToExport = nil
        }

        if let transitTierInfoToExport {
            locatorInfo.transitCdnKey = transitTierInfoToExport.cdnKey
            locatorInfo.transitCdnNumber = transitTierInfoToExport.cdnNumber
            locatorInfo.transitTierUploadTimestamp = transitTierInfoToExport.uploadTimestamp
        }

        if let mediaTierInfo = attachment.mediaTierInfo {
            locatorInfo.key = attachment.encryptionKey
            locatorInfo.size = mediaTierInfo.unencryptedByteCount
            locatorInfo.integrityCheck = .plaintextHash(mediaTierInfo.sha256ContentHash)

            if let cdnNumber = mediaTierInfo.cdnNumber {
                locatorInfo.mediaTierCdnNumber = cdnNumber
            }
        } else if let streamInfo = attachment.streamInfo {
            locatorInfo.key = attachment.encryptionKey
            locatorInfo.size = streamInfo.unencryptedByteCount
            locatorInfo.integrityCheck = .plaintextHash(streamInfo.sha256ContentHash)
        } else if let transitTierInfoToExport {
            locatorInfo.key = attachment.encryptionKey
            locatorInfo.size = transitTierInfoToExport.unencryptedByteCount ?? 0

            // At the time of writing, TransitTierInfo.integrityCheck prefers
            // the encrypted digest even if both are present. (See comment in
            // that type's init.) So, manually check for the plaintext hash
            // here, falling back to the encrypted digest otherwise.
            if let plaintextHash = attachment.sha256ContentHash {
                locatorInfo.integrityCheck = .plaintextHash(plaintextHash)
            } else {
                switch transitTierInfoToExport.integrityCheck {
                case .sha256ContentHash(let plaintextHash):
                    owsFailDebug("Missing Attachment plaintext hash, but had one on TransitTierInfo!")
                    locatorInfo.integrityCheck = .plaintextHash(plaintextHash)
                case .digestSHA256Ciphertext(let encryptedDigest):
                    locatorInfo.integrityCheck = .encryptedDigest(encryptedDigest)
                }
            }
        } else {
            // This attachment isn't uploaded anywhere and this device won't be
            // able to upload it in the future. So, we leave a bunch of fields
            // unset so any restoring device knows it's unavailable.
        }

        return locatorInfo
    }
}
