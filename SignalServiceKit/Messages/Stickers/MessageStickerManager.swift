//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct MessageStickerDataSource {
    public let info: StickerInfo
    public let stickerType: StickerType
    public let emoji: String?
    public let source: TSResourceDataSource
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

    private let attachmentManager: TSResourceManager
    private let attachmentStore: TSResourceStore
    private let attachmentValidator: TSResourceContentValidator
    private let stickerManager: Shims.StickerManager

    public init(
        attachmentManager: TSResourceManager,
        attachmentStore: TSResourceStore,
        attachmentValidator: TSResourceContentValidator,
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

        let messageSticker: MessageSticker
        switch attachmentBuilder.info {
        case .legacy(let uniqueId):
            messageSticker = .withLegacyAttachment(info: stickerInfo, legacyAttachmentId: uniqueId, emoji: emoji)
        case .v2:
            messageSticker = .withForeignReferenceAttachment(info: stickerInfo, emoji: emoji)
        }
        guard messageSticker.isValid else {
            throw StickerError.invalidInput
        }
        return attachmentBuilder.wrap { _ in messageSticker }
    }

    private func saveAttachment(
        dataProto: SSKProtoAttachmentPointer,
        stickerInfo: StickerInfo,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<TSResourceRetrievalInfo> {
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
                ownerType: .message,
                tx: tx
            )
        } catch {
            throw StickerError.invalidInput
        }
    }

    private func tsAttachmentForInstalledSticker(
        dataProto: SSKProtoAttachmentPointer,
        stickerInfo: StickerInfo,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<TSResourceRetrievalInfo>? {
        guard
            let installedSticker = stickerManager.fetchInstalledSticker(
                stickerInfo: stickerInfo,
                tx: tx
            )
        else {
            // Sticker is not installed.
            return nil
        }
        guard let stickerDataUrl = StickerManager.stickerDataUrl(forInstalledSticker: installedSticker,
                                                                 verifyExists: true) else {
            owsFailDebug("Missing data for installed sticker.")
            return nil
        }
        guard OWSFileSystem.fileSize(of: stickerDataUrl) != nil else {
            owsFailDebug("Could not determine file size for installed sticker.")
            return nil
        }
        do {
            let dataSource = try DataSourcePath(fileUrl: stickerDataUrl, shouldDeleteOnDeallocation: false)
            let mimeType: String
            let imageMetadata = Data.imageMetadata(withPath: stickerDataUrl.path, mimeType: nil)
            if imageMetadata.imageFormat != .unknown,
               let mimeTypeFromMetadata = imageMetadata.mimeType {
                mimeType = mimeTypeFromMetadata
            } else if let dataMimeType = dataProto.contentType, !dataMimeType.isEmpty {
                mimeType = dataMimeType
            } else {
                mimeType = MimeType.imageWebp.rawValue
            }

            let attachmentDataSource = TSAttachmentDataSource(
                mimeType: mimeType,
                caption: nil,
                renderingFlag: .default,
                sourceFilename: nil,
                dataSource: .dataSource(dataSource, shouldCopy: true)
            )

            return try attachmentManager.createAttachmentStreamBuilder(
                from: attachmentDataSource.tsDataSource,
                tx: tx
            )
        } catch {
            owsFailDebug("Could not write data source for path: \(stickerDataUrl.path), error: \(error)")
            return nil
        }
    }

    public func buildDataSource(fromDraft draft: MessageStickerDraft) throws -> MessageStickerDataSource {
        let validatedDataSource = try attachmentValidator.validateContents(
            data: draft.stickerData,
            mimeType: draft.stickerType.mimeType,
            sourceFilename: nil,
            caption: nil,
            renderingFlag: .default,
            ownerType: .message
        )
        return .init(
            info: draft.info,
            stickerType: draft.stickerType,
            emoji: draft.emoji,
            source: validatedDataSource
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

        let messageSticker: MessageSticker
        switch attachmentBuilder.info {
        case .legacy(let uniqueId):
            messageSticker = .withLegacyAttachment(info: dataSource.info, legacyAttachmentId: uniqueId, emoji: dataSource.emoji)
        case .v2:
            messageSticker = .withForeignReferenceAttachment(info: dataSource.info, emoji: dataSource.emoji)
        }
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
            let attachmentReference = attachmentStore.stickerAttachment(
                for: parentMessage,
                tx: tx
            ),
            let attachment = attachmentStore.fetch(attachmentReference.resourceId, tx: tx)
        else {
            throw OWSAssertionError("Could not find sticker attachment")
        }

        guard let attachmentPointer = attachment.asTransitTierPointer() else {
            throw OWSAssertionError("Generating proto for non-uploaded attachment!")
        }

        guard
            let attachmentProto = attachmentManager.buildProtoForSending(
                from: attachmentReference,
                pointer: attachmentPointer
            )
        else {
            throw OWSAssertionError("Could not build sticker attachment protobuf.")
        }

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
        return .withoutFinalizer(.withForeignReferenceAttachment(
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
        return .withoutFinalizer(.withForeignReferenceAttachment(info: dataSource.info, emoji: dataSource.emoji))
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
