//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct MessageStickerDataSource {
    public let info: StickerInfo
    public let stickerType: StickerType
    public let emoji: String?
    public let source: AttachmentDataSource
}

public protocol MessageStickerManager {

    func buildValidatedMessageSticker(
        from proto: SSKProtoDataMessageSticker,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<MessageSticker>

    func buildDataSource(fromDraft: MessageStickerDraft) throws -> MessageStickerDataSource

    func buildValidatedMessageSticker(
        from dataSource: MessageStickerDataSource,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<MessageSticker>

    func buildProtoForSending(
        _ messageSticker: MessageSticker,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) throws -> SSKProtoDataMessageSticker
}

public class MessageStickerManagerImpl: MessageStickerManager {

    private let attachmentManager: AttachmentManager
    private let attachmentStore: AttachmentStore
    private let attachmentValidator: AttachmentContentValidator
    private let stickerManager: Shims.StickerManager

    public init(
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        attachmentValidator: AttachmentContentValidator,
        stickerManager: Shims.StickerManager
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.attachmentValidator = attachmentValidator
        self.stickerManager = stickerManager
    }

    public func buildValidatedMessageSticker(
        from stickerProto: SSKProtoDataMessageSticker,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<MessageSticker> {
        let packID: Data = stickerProto.packID
        let packKey: Data = stickerProto.packKey
        let stickerID: UInt32 = stickerProto.stickerID
        let emoji: String? = stickerProto.emoji
        let dataProto: SSKProtoAttachmentPointer = stickerProto.data
        let stickerInfo = StickerInfo(packId: packID, packKey: packKey, stickerId: stickerID)

        let attachmentBuilder = try saveAttachment(
            dataProto: dataProto,
            stickerInfo: stickerInfo,
            tx: tx
        )

        let messageSticker = MessageSticker(info: stickerInfo, emoji: emoji)
        guard messageSticker.isValid else {
            throw StickerError.invalidInput
        }
        return attachmentBuilder.wrap { _ in messageSticker }
    }

    private func saveAttachment(
        dataProto: SSKProtoAttachmentPointer,
        stickerInfo: StickerInfo,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<Void> {
        do {
            let proto: SSKProtoAttachmentPointer
            if dataProto.contentType == MimeType.applicationOctetStream.rawValue {
                let builder = dataProto.asBuilder()
                builder.setContentType(MimeType.imageWebp.rawValue)
                proto = builder.buildInfallibly()
            } else {
                proto = dataProto
            }
            return try attachmentManager.createAttachmentPointerBuilder(
                from: proto,
                tx: tx
            )
        } catch {
            throw StickerError.invalidInput
        }
    }

    public func buildDataSource(fromDraft draft: MessageStickerDraft) throws -> MessageStickerDataSource {
        let validatedDataSource = try attachmentValidator.validateContents(
            data: draft.stickerData,
            mimeType: draft.stickerType.mimeType,
            renderingFlag: .default,
            sourceFilename: nil
        )
        return .init(
            info: draft.info,
            stickerType: draft.stickerType,
            emoji: draft.emoji,
            source: .pendingAttachment(validatedDataSource)
        )
    }

    public func buildValidatedMessageSticker(
        from dataSource: MessageStickerDataSource,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<MessageSticker> {
        let attachmentBuilder = try attachmentManager.createAttachmentStreamBuilder(
            from: dataSource.source,
            tx: tx
        )

        let messageSticker = MessageSticker(info: dataSource.info, emoji: dataSource.emoji)
        guard messageSticker.isValid else {
            throw StickerError.invalidInput
        }
        return attachmentBuilder.wrap { _ in messageSticker }
    }

    public func buildProtoForSending(
        _ messageSticker: MessageSticker,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) throws -> SSKProtoDataMessageSticker {

        guard
            let parentMessageRowId = parentMessage.sqliteRowId,
            let attachment = attachmentStore.fetchFirstReferencedAttachment(
                for: .messageSticker(messageRowId: parentMessageRowId),
                tx: tx
            )
        else {
            throw OWSAssertionError("Could not find sticker attachment")
        }

        guard let attachmentPointer = attachment.attachment.asTransitTierPointer() else {
            throw OWSAssertionError("Generating proto for non-uploaded attachment!")
        }

        let attachmentProto = attachmentManager.buildProtoForSending(
            from: attachment.reference,
            pointer: attachmentPointer
        )

        let protoBuilder = SSKProtoDataMessageSticker.builder(
            packID: messageSticker.packId,
            packKey: messageSticker.packKey,
            stickerID: messageSticker.stickerId,
            data: attachmentProto
        )

        if let emoji = messageSticker.emoji?.nilIfEmpty {
            protoBuilder.setEmoji(emoji)
        }

        return try protoBuilder.build()
    }
}

#if TESTABLE_BUILD

public class MockMessageStickerManager: MessageStickerManager {

    public func buildValidatedMessageSticker(
        from proto: SSKProtoDataMessageSticker,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<MessageSticker> {
        return .withoutFinalizer(MessageSticker(
            info: .init(packId: proto.packID, packKey: proto.packKey, stickerId: proto.stickerID),
            emoji: proto.emoji
        ))
    }

    public func buildDataSource(fromDraft draft: MessageStickerDraft) throws -> MessageStickerDataSource {
        throw OWSAssertionError("Unimplemented")
    }

    public func buildValidatedMessageSticker(
        from dataSource: MessageStickerDataSource,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<MessageSticker> {
        return .withoutFinalizer(MessageSticker(info: dataSource.info, emoji: dataSource.emoji))
    }

    public func buildProtoForSending(
        _ messageSticker: MessageSticker,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) throws -> SSKProtoDataMessageSticker {
        throw OWSAssertionError("Unimplemented")
    }
}

#endif

extension MessageStickerManagerImpl {
    public enum Shims {
        public typealias StickerManager = _MessageStickerManager_StickerManagerShim
    }
    public enum Wrappers {
        public typealias StickerManager = _MessageStickerManager_StickerManagerWrapper
    }
}

public protocol _MessageStickerManager_StickerManagerShim {
    func fetchInstalledSticker(stickerInfo: StickerInfo, tx: DBReadTransaction) -> InstalledSticker?
}

public class _MessageStickerManager_StickerManagerWrapper: _MessageStickerManager_StickerManagerShim {
    public init() {}

    public func fetchInstalledSticker(stickerInfo: StickerInfo, tx: DBReadTransaction) -> InstalledSticker? {
        StickerManager.fetchInstalledSticker(stickerInfo: stickerInfo, transaction: SDSDB.shimOnlyBridge(tx))
    }
}
