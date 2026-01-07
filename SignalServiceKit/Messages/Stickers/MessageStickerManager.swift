//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct MessageStickerDataSource {
    public let info: StickerInfo
    public let emoji: String?
    public let source: AttachmentDataSource
}

public struct ValidatedMessageStickerProto {
    public let sticker: MessageSticker
    public let proto: SSKProtoAttachmentPointer
}

public struct ValidatedMessageStickerDataSource {
    public let sticker: MessageSticker
    public let attachmentDataSource: AttachmentDataSource
}

// MARK: -

public protocol MessageStickerManager {

    func buildValidatedMessageSticker(
        from proto: SSKProtoDataMessageSticker,
    ) throws -> ValidatedMessageStickerProto

    func buildDataSource(
        fromDraft: MessageStickerDraft,
    ) async throws -> MessageStickerDataSource

    func validateMessageSticker(
        dataSource: MessageStickerDataSource,
    ) throws -> ValidatedMessageStickerDataSource

    func buildProtoForSending(
        _ messageSticker: MessageSticker,
        parentMessage: TSMessage,
        tx: DBReadTransaction,
    ) throws -> SSKProtoDataMessageSticker
}

// MARK: -

class MessageStickerManagerImpl: MessageStickerManager {

    private let attachmentManager: AttachmentManager
    private let attachmentStore: AttachmentStore
    private let attachmentValidator: AttachmentContentValidator

    init(
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        attachmentValidator: AttachmentContentValidator,
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.attachmentValidator = attachmentValidator
    }

    func buildValidatedMessageSticker(
        from stickerProto: SSKProtoDataMessageSticker,
    ) throws -> ValidatedMessageStickerProto {
        let packID: Data = stickerProto.packID
        let packKey: Data = stickerProto.packKey
        let stickerID: UInt32 = stickerProto.stickerID
        let emoji: String? = stickerProto.emoji
        let attachmentProto: SSKProtoAttachmentPointer = stickerProto.data
        let stickerInfo = StickerInfo(packId: packID, packKey: packKey, stickerId: stickerID)

        let messageSticker = MessageSticker(info: stickerInfo, emoji: emoji)
        guard messageSticker.isValid else {
            throw StickerError.invalidInput
        }

        if attachmentProto.contentType == nil || attachmentProto.contentType == MimeType.applicationOctetStream.rawValue {
            let builder = attachmentProto.asBuilder()
            builder.setContentType(MimeType.imageWebp.rawValue)

            return ValidatedMessageStickerProto(
                sticker: messageSticker,
                proto: builder.buildInfallibly(),
            )
        } else {
            return ValidatedMessageStickerProto(
                sticker: messageSticker,
                proto: attachmentProto,
            )
        }
    }

    func buildDataSource(
        fromDraft draft: MessageStickerDraft,
    ) async throws -> MessageStickerDataSource {
        let validatedDataSource = try await attachmentValidator.validateDataContents(
            draft.stickerData,
            mimeType: draft.stickerType.mimeType,
            renderingFlag: .default,
            sourceFilename: nil,
        )
        return MessageStickerDataSource(
            info: draft.info,
            emoji: draft.emoji,
            source: .pendingAttachment(validatedDataSource),
        )
    }

    func validateMessageSticker(
        dataSource: MessageStickerDataSource,
    ) throws -> ValidatedMessageStickerDataSource {
        let messageSticker = MessageSticker(info: dataSource.info, emoji: dataSource.emoji)
        guard messageSticker.isValid else {
            throw StickerError.invalidInput
        }

        return ValidatedMessageStickerDataSource(
            sticker: messageSticker,
            attachmentDataSource: dataSource.source,
        )
    }

    func buildProtoForSending(
        _ messageSticker: MessageSticker,
        parentMessage: TSMessage,
        tx: DBReadTransaction,
    ) throws -> SSKProtoDataMessageSticker {

        guard
            let parentMessageRowId = parentMessage.sqliteRowId,
            let attachment = attachmentStore.fetchAnyReferencedAttachment(
                for: .messageSticker(messageRowId: parentMessageRowId),
                tx: tx,
            )
        else {
            throw OWSAssertionError("Could not find sticker attachment")
        }

        guard
            let attachmentPointer = attachment.attachment.asTransitTierPointer(),
            case let .digestSHA256Ciphertext(digestSHA256Ciphertext) = attachmentPointer.info.integrityCheck
        else {
            throw OWSAssertionError("Generating proto for non-uploaded attachment!")
        }

        let attachmentProto = attachmentManager.buildProtoForSending(
            from: attachment.reference,
            pointer: attachmentPointer,
            digestSHA256Ciphertext: digestSHA256Ciphertext,
        )

        let protoBuilder = SSKProtoDataMessageSticker.builder(
            packID: messageSticker.packId,
            packKey: messageSticker.packKey,
            stickerID: messageSticker.stickerId,
            data: attachmentProto,
        )

        if let emoji = messageSticker.emoji?.nilIfEmpty {
            protoBuilder.setEmoji(emoji)
        }

        return try protoBuilder.build()
    }
}
