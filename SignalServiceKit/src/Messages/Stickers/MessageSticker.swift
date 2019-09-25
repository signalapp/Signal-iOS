//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

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
    public init(info: StickerInfo, stickerData: Data) {
        self.info = info
        self.stickerData = stickerData
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
    public init(info: StickerInfo, attachmentId: String) {
        self.info = info
        self.attachmentId = attachmentId

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
        guard FeatureFlags.stickerReceive else {
            throw StickerError.noSticker
        }
        guard let stickerProto: SSKProtoDataMessageSticker = dataMessage.sticker else {
            throw StickerError.noSticker
        }

        let packID: Data = stickerProto.packID
        let packKey: Data = stickerProto.packKey
        let stickerID: UInt32 = stickerProto.stickerID
        let dataProto: SSKProtoAttachmentPointer = stickerProto.data
        let stickerInfo = StickerInfo(packId: packID, packKey: packKey, stickerId: stickerID)

        let attachment = try saveAttachment(dataProto: dataProto,
                                            stickerInfo: stickerInfo,
                                            transaction: transaction)
        let attachmentId = attachment.uniqueId

        let messageSticker = MessageSticker(info: stickerInfo, attachmentId: attachmentId)
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
        attachmentPointer.anyInsert(transaction: transaction)
        return attachmentPointer
    }

    private class func attachmentForInstalledSticker(dataProto: SSKProtoAttachmentPointer,
                                                     stickerInfo: StickerInfo,
                                                     transaction: SDSAnyWriteTransaction) -> TSAttachmentStream? {
        guard let filePath = StickerManager.filepathForInstalledSticker(stickerInfo: stickerInfo, transaction: transaction) else {
            // Sticker is not installed.
            return nil
        }
        guard let fileSize = OWSFileSystem.fileSize(ofPath: filePath) else {
            owsFailDebug("Could not determine file size for installed sticker.")
            return nil
        }
        do {
            let dataSource = try DataSourcePath.dataSource(withFilePath: filePath, shouldDeleteOnDeallocation: false)
            let contentType = dataProto.contentType ?? OWSMimeTypeImageWebp
            let attachment = TSAttachmentStream(contentType: contentType, byteCount: fileSize.uint32Value, sourceFilename: nil, caption: nil, albumMessageId: nil, shouldAlwaysPad: false)
            try attachment.writeCopyingDataSource(dataSource)
            attachment.anyInsert(transaction: transaction)
            return attachment
        } catch {
            owsFailDebug("Could not write data source for path: \(filePath), error: \(error)")
            return nil
        }
    }

    @objc
    public class func buildValidatedMessageSticker(fromDraft draft: MessageStickerDraft,
                                                   transaction: SDSAnyWriteTransaction) throws -> MessageSticker {
        let attachmentId = try MessageSticker.saveAttachment(stickerData: draft.stickerData,
                                                             transaction: transaction)

        let messageSticker = MessageSticker(info: draft.info, attachmentId: attachmentId)
        guard messageSticker.isValid else {
            throw StickerError.assertionFailure
        }
        return messageSticker
    }

    private class func saveAttachment(stickerData: Data,
                                      transaction: SDSAnyWriteTransaction) throws -> String {
        let fileSize = stickerData.count
        guard fileSize > 0 else {
            owsFailDebug("Invalid file size for data.")
            throw StickerError.assertionFailure
        }
        let fileExtension = "webp"
        let contentType = OWSMimeTypeImageWebp

        let fileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: fileExtension)
        try stickerData.write(to: fileUrl)
        let dataSource = try DataSourcePath.dataSource(with: fileUrl, shouldDeleteOnDeallocation: true)
        let attachment = TSAttachmentStream(contentType: contentType, byteCount: UInt32(fileSize), sourceFilename: nil, caption: nil, albumMessageId: nil, shouldAlwaysPad: true)
        try attachment.writeConsumingDataSource(dataSource)

        attachment.anyInsert(transaction: transaction)
        return attachment.uniqueId
    }
}
