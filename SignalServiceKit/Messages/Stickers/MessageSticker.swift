//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - MessageStickerDraft

@objc
public class MessageStickerDraft: NSObject {
    @objc
    public let info: StickerInfo

    @objc
    public var packId: Data {
        return info.packId
    }

    @objc
    public var packKey: Data {
        return info.packKey
    }

    @objc
    public var stickerId: UInt32 {
        return info.stickerId
    }

    @objc
    public let stickerData: Data

    @objc
    public let stickerType: StickerType

    @objc
    public let emoji: String?

    @objc
    public init(info: StickerInfo, stickerData: Data, stickerType: StickerType, emoji: String?) {
        self.info = info
        self.stickerData = stickerData
        self.stickerType = stickerType
        self.emoji = emoji
    }
}

// MARK: - MessageSticker

@objc
public class MessageSticker: MTLModel {
    // MTLModel requires default values.
    @objc
    public var info = StickerInfo.defaultValue

    @objc
    public var packId: Data {
        return info.packId
    }

    @objc
    public var packKey: Data {
        return info.packKey
    }

    @objc
    public var stickerId: UInt32 {
        return info.stickerId
    }

    // MTLModel requires default values.
    @objc
    private var attachmentId: String?

    public var legacyAttachmentId: String? {
        return attachmentId?.nilIfEmpty
    }

    @objc
    public var emoji: String?

    private init(info: StickerInfo, legacyAttachmentId: String?, emoji: String?) {
        self.info = info
        self.attachmentId = legacyAttachmentId
        self.emoji = emoji

        super.init()
    }

    public static func withLegacyAttachment(
        info: StickerInfo,
        legacyAttachmentId: String,
        emoji: String?
    ) -> MessageSticker {
        return MessageSticker(info: info, legacyAttachmentId: legacyAttachmentId, emoji: emoji)
    }

    public static func withForeignReferenceAttachment(info: StickerInfo, emoji: String?) -> MessageSticker {
        return MessageSticker(info: info, legacyAttachmentId: nil, emoji: emoji)
    }

    @objc
    public override init() {
        super.init()
    }

    @objc
    public required init!(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc
    public required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    @objc
    public var isValid: Bool {
        return info.isValid()
    }

    @objc
    public class func isNoStickerError(_ error: Error) -> Bool {
        guard let error = error as? StickerError else {
            return false
        }
        return error == .noSticker
    }

    public class func buildValidatedMessageSticker(
        dataMessage: SSKProtoDataMessage,
        transaction: SDSAnyWriteTransaction
    ) throws -> OwnedAttachmentBuilder<MessageSticker> {
        guard let stickerProto: SSKProtoDataMessageSticker = dataMessage.sticker else {
            throw StickerError.noSticker
        }

        let packID: Data = stickerProto.packID
        let packKey: Data = stickerProto.packKey
        let stickerID: UInt32 = stickerProto.stickerID
        let emoji: String? = stickerProto.emoji
        let dataProto: SSKProtoAttachmentPointer = stickerProto.data
        let stickerInfo = StickerInfo(packId: packID, packKey: packKey, stickerId: stickerID)

        let attachmentBuilder = try saveAttachment(
            dataProto: dataProto,
            stickerInfo: stickerInfo,
            transaction: transaction
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

    private class func saveAttachment(
        dataProto: SSKProtoAttachmentPointer,
        stickerInfo: StickerInfo,
        transaction: SDSAnyWriteTransaction
    ) throws -> OwnedAttachmentBuilder<TSResourceRetrievalInfo> {

        // As an optimization, if the sticker is already installed,
        // try to derive an TSAttachmentStream using that.
        if let attachment = attachmentForInstalledSticker(dataProto: dataProto,
                                                          stickerInfo: stickerInfo,
                                                          transaction: transaction) {
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
            return try DependenciesBridge.shared.tsResourceManager.createAttachmentPointerBuilder(
                from: proto,
                tx: transaction.asV2Write
            )
        } catch {
            throw StickerError.invalidInput
        }
    }

    private class func attachmentForInstalledSticker(
        dataProto: SSKProtoAttachmentPointer,
        stickerInfo: StickerInfo,
        transaction: SDSAnyWriteTransaction
    ) -> OwnedAttachmentBuilder<TSResourceRetrievalInfo>? {
        guard let installedSticker = StickerManager.fetchInstalledSticker(stickerInfo: stickerInfo,
                                                                          transaction: transaction) else {
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

            return try DependenciesBridge.shared.tsResourceManager.createAttachmentStreamBuilder(
                from: attachmentDataSource,
                tx: transaction.asV2Write
            )
        } catch {
            owsFailDebug("Could not write data source for path: \(stickerDataUrl.path), error: \(error)")
            return nil
        }
    }

    public class func buildValidatedMessageSticker(
        fromDraft draft: MessageStickerDraft,
        transaction: SDSAnyWriteTransaction
    ) throws -> OwnedAttachmentBuilder<MessageSticker> {
        let attachmentBuilder = try MessageSticker.saveAttachment(
            stickerData: draft.stickerData,
            stickerType: draft.stickerType,
            transaction: transaction
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

    private class func saveAttachment(
        stickerData: Data,
        stickerType: StickerType,
        transaction: SDSAnyWriteTransaction
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

        return try DependenciesBridge.shared.tsResourceManager.createAttachmentStreamBuilder(
            from: attachmentDataSource,
            tx: transaction.asV2Write
        )
    }
}
