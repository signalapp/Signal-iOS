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
    public var attachmentId: String = ""

    @objc
    public var emoji: String?

    @objc
    public init(info: StickerInfo, attachmentId: String, emoji: String?) {
        self.info = info
        self.attachmentId = attachmentId
        self.emoji = emoji

        super.init()
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

    @objc
    public class func buildValidatedMessageSticker(dataMessage: SSKProtoDataMessage,
                                                   transaction: SDSAnyWriteTransaction) throws -> MessageSticker {
        guard let stickerProto: SSKProtoDataMessageSticker = dataMessage.sticker else {
            throw StickerError.noSticker
        }

        let packID: Data = stickerProto.packID
        let packKey: Data = stickerProto.packKey
        let stickerID: UInt32 = stickerProto.stickerID
        let emoji: String? = stickerProto.emoji
        let dataProto: SSKProtoAttachmentPointer = stickerProto.data
        let stickerInfo = StickerInfo(packId: packID, packKey: packKey, stickerId: stickerID)

        let attachment = try saveAttachment(dataProto: dataProto,
                                            stickerInfo: stickerInfo,
                                            transaction: transaction)
        let attachmentId = attachment.uniqueId

        let messageSticker = MessageSticker(info: stickerInfo, attachmentId: attachmentId, emoji: emoji)
        guard messageSticker.isValid else {
            throw StickerError.invalidInput
        }
        return messageSticker
    }

    private class func saveAttachment(dataProto: SSKProtoAttachmentPointer,
                                      stickerInfo: StickerInfo,
                                      transaction: SDSAnyWriteTransaction) throws -> TSAttachment {

        // As an optimization, if the sticker is already installed,
        // try to derive an TSAttachmentStream using that.
        if let attachment = attachmentForInstalledSticker(dataProto: dataProto,
                                                          stickerInfo: stickerInfo,
                                                          transaction: transaction) {
            return attachment
        }

        guard let attachmentPointer = TSAttachmentPointer(fromProto: dataProto, albumMessage: nil) else {
            throw StickerError.invalidInput
        }

        attachmentPointer.setDefaultContentType(OWSMimeTypeImageWebp)

        attachmentPointer.anyInsert(transaction: transaction)
        return attachmentPointer
    }

    private class func attachmentForInstalledSticker(dataProto: SSKProtoAttachmentPointer,
                                                     stickerInfo: StickerInfo,
                                                     transaction: SDSAnyWriteTransaction) -> TSAttachmentStream? {
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
            let contentType: String
            let imageMetadata = NSData.imageMetadata(withPath: stickerDataUrl.path, mimeType: nil)
            if imageMetadata.imageFormat != .unknown,
               let mimeTypeFromMetadata = imageMetadata.mimeType {
                contentType = mimeTypeFromMetadata
            } else if let dataContentType = dataProto.contentType,
                !dataContentType.isEmpty {
                contentType = dataContentType
            } else {
                contentType = OWSMimeTypeImageWebp
            }
            let attachment = TSAttachmentStream(
                contentType: contentType,
                byteCount: fileSize.uint32Value,
                sourceFilename: nil,
                caption: nil,
                attachmentType: .default,
                albumMessageId: nil
            )
            try attachment.writeCopyingDataSource(dataSource)
            attachment.anyInsert(transaction: transaction)
            return attachment
        } catch {
            owsFailDebug("Could not write data source for path: \(stickerDataUrl.path), error: \(error)")
            return nil
        }
    }

    @objc
    public class func buildValidatedMessageSticker(fromDraft draft: MessageStickerDraft,
                                                   transaction: SDSAnyWriteTransaction) throws -> MessageSticker {
        let attachmentId = try MessageSticker.saveAttachment(stickerData: draft.stickerData,
                                                             stickerType: draft.stickerType,
                                                             transaction: transaction)

        let messageSticker = MessageSticker(info: draft.info, attachmentId: attachmentId, emoji: draft.emoji)
        guard messageSticker.isValid else {
            throw StickerError.assertionFailure
        }
        return messageSticker
    }

    private class func saveAttachment(stickerData: Data,
                                      stickerType: StickerType,
                                      transaction: SDSAnyWriteTransaction) throws -> String {
        let fileSize = stickerData.count
        guard fileSize > 0 else {
            owsFailDebug("Invalid file size for data.")
            throw StickerError.assertionFailure
        }
        let fileExtension = stickerType.fileExtension
        var contentType = stickerType.contentType
        let fileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: fileExtension)
        try stickerData.write(to: fileUrl)

        let imageMetadata = NSData.imageMetadata(withPath: fileUrl.path, mimeType: nil)
        if imageMetadata.imageFormat != .unknown,
           let mimeTypeFromMetadata = imageMetadata.mimeType {
            contentType = mimeTypeFromMetadata
        }

        let dataSource = try DataSourcePath.dataSource(with: fileUrl, shouldDeleteOnDeallocation: true)
        let attachment = TSAttachmentStream(
            contentType: contentType,
            byteCount: UInt32(fileSize),
            sourceFilename: nil,
            caption: nil,
            attachmentType: .default,
            albumMessageId: nil
        )
        try attachment.writeConsumingDataSource(dataSource)

        attachment.anyInsert(transaction: transaction)
        return attachment.uniqueId
    }
}
