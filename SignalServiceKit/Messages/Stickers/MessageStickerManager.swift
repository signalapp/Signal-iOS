//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol MessageStickerManager {

    func buildValidatedMessageSticker(
        from proto: SSKProtoDataMessageSticker,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<MessageSticker>

    func buildValidatedMessageSticker(
        fromDraft draft: MessageStickerDraft,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<MessageSticker>
}

public class MessageStickerManagerImpl: MessageStickerManager {

    private let attachmentManager: TSResourceManager
    private let stickerManager: Shims.StickerManager

    public init(
        attachmentManager: TSResourceManager,
        stickerManager: Shims.StickerManager
    ) {
        self.attachmentManager = attachmentManager
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

        // As an optimization, if the sticker is already installed,
        // try to derive an TSAttachmentStream using that.
        if
            let attachment = attachmentForInstalledSticker(
                dataProto: dataProto,
                stickerInfo: stickerInfo,
                tx: tx
            )
        {
            return attachment
        }

        do {
            let proto: SSKProtoAttachmentPointer
            if dataProto.contentType == OWSMimeTypeApplicationOctetStream {
                let builder = dataProto.asBuilder()
                builder.setContentType(OWSMimeTypeImageWebp)
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

    private func attachmentForInstalledSticker(
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
        guard let fileSize = OWSFileSystem.fileSize(of: stickerDataUrl) else {
            owsFailDebug("Could not determine file size for installed sticker.")
            return nil
        }
        do {
            let dataSource = try DataSourcePath.dataSource(with: stickerDataUrl, shouldDeleteOnDeallocation: false)
            let mimeType: String
            let imageMetadata = NSData.imageMetadata(withPath: stickerDataUrl.path, mimeType: nil)
            if imageMetadata.imageFormat != .unknown,
               let mimeTypeFromMetadata = imageMetadata.mimeType {
                mimeType = mimeTypeFromMetadata
            } else if let dataMimeType = dataProto.contentType, !dataMimeType.isEmpty {
                mimeType = dataMimeType
            } else {
                mimeType = OWSMimeTypeImageWebp
            }

            let attachmentDataSource = TSResourceDataSource.from(
                dataSource: dataSource,
                mimeType: mimeType,
                caption: nil,
                renderingFlag: .default,
                shouldCopyDataSource: true
            )

            return try attachmentManager.createAttachmentStreamBuilder(
                from: attachmentDataSource,
                tx: tx
            )
        } catch {
            owsFailDebug("Could not write data source for path: \(stickerDataUrl.path), error: \(error)")
            return nil
        }
    }

    public func buildValidatedMessageSticker(
        fromDraft draft: MessageStickerDraft,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<MessageSticker> {
        let attachmentBuilder = try saveAttachment(
            stickerData: draft.stickerData,
            stickerType: draft.stickerType,
            tx: tx
        )

        let messageSticker: MessageSticker
        switch attachmentBuilder.info {
        case .legacy(let uniqueId):
            messageSticker = .withLegacyAttachment(info: draft.info, legacyAttachmentId: uniqueId, emoji: draft.emoji)
        case .v2:
            messageSticker = .withForeignReferenceAttachment(info: draft.info, emoji: draft.emoji)
        }
        guard messageSticker.isValid else {
            throw StickerError.invalidInput
        }
        return attachmentBuilder.wrap { _ in messageSticker }
    }

    private func saveAttachment(
        stickerData: Data,
        stickerType: StickerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<TSResourceRetrievalInfo> {
        let fileSize = stickerData.count
        guard fileSize > 0 else {
            owsFailDebug("Invalid file size for data.")
            throw StickerError.assertionFailure
        }
        let fileExtension = stickerType.fileExtension
        var mimeType = stickerType.contentType
        let fileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: fileExtension)
        try stickerData.write(to: fileUrl)

        let imageMetadata = NSData.imageMetadata(withPath: fileUrl.path, mimeType: nil)
        if imageMetadata.imageFormat != .unknown,
           let mimeTypeFromMetadata = imageMetadata.mimeType {
            mimeType = mimeTypeFromMetadata
        }

        let dataSource = try DataSourcePath.dataSource(with: fileUrl, shouldDeleteOnDeallocation: true)

        let attachmentDataSource = TSResourceDataSource.from(
            dataSource: dataSource,
            mimeType: mimeType,
            caption: nil,
            renderingFlag: .default,
            // this data source should be consumed.
            shouldCopyDataSource: false
        )

        return try attachmentManager.createAttachmentStreamBuilder(
            from: attachmentDataSource,
            tx: tx
        )
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

    public func buildValidatedMessageSticker(
        fromDraft draft: MessageStickerDraft,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<MessageSticker> {
        return .withoutFinalizer(.withForeignReferenceAttachment(info: draft.info, emoji: draft.emoji))
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
