//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// MARK: - MessageStickerDraft

@objc
public class MessageStickerDraft: NSObject {
    @objc
    public let stickerMetadata: StickerMetadata

    @objc
    public var stickerData: Data

    @objc
    public init(stickerMetadata: StickerMetadata, stickerData: Data) {
        self.stickerMetadata = stickerMetadata
        self.stickerData = stickerData
    }
}

// MARK: - MessageSticker

@objc
public class MessageSticker: MTLModel {
    // MTLModel requires default values.
    private var stickerMetadata = StickerMetadata.defaultValue

    // MTLModel requires default values.
    @objc
    public var attachmentId: String = ""

    @objc
    public var stickerId: UInt32 {
        return stickerMetadata.stickerId
    }

    @objc
    public var packId: Data {
        return stickerMetadata.packId
    }

    @objc
    public var packKey: Data {
        return stickerMetadata.packKey
    }

    @objc
    public init(stickerMetadata: StickerMetadata, attachmentId: String) {
        self.stickerMetadata = stickerMetadata
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
    public required init(dictionary dictionaryValue: [AnyHashable: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
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

        guard let attachmentPointer = TSAttachmentPointer(fromProto: dataProto, albumMessage: nil) else {
            throw StickerError.invalidInput
        }
        attachmentPointer.anySave(transaction: transaction)
        guard let attachmentId = attachmentPointer.uniqueId else {
            throw StickerError.assertionFailure
        }

        let stickerMetadata = StickerMetadata(packId: packID, packKey: packKey, stickerId: stickerID)
        let messageSticker = MessageSticker(stickerMetadata: stickerMetadata, attachmentId: attachmentId)
        return messageSticker
    }

    @objc
    public class func buildValidatedMessageSticker(fromDraft draft: MessageStickerDraft,
                                                   transaction: SDSAnyWriteTransaction) throws -> MessageSticker {
        guard FeatureFlags.stickerSend else {
            throw StickerError.assertionFailure
        }
        let attachmentId = try MessageSticker.saveAttachment(stickerData: draft.stickerData,
                                                             transaction: transaction)

        let messageSticker = MessageSticker(stickerMetadata: draft.stickerMetadata, attachmentId: attachmentId)

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

        let filePath = OWSFileSystem.temporaryFilePath(withFileExtension: fileExtension)
        do {
            try stickerData.write(to: NSURL.fileURL(withPath: filePath))
        } catch let error as NSError {
            owsFailDebug("file write failed: \(filePath), \(error)")
            throw StickerError.assertionFailure
        }

        guard let dataSource = DataSourcePath.dataSource(withFilePath: filePath, shouldDeleteOnDeallocation: true) else {
            owsFailDebug("Could not create data source for path: \(filePath)")
            throw StickerError.assertionFailure
        }
        let attachment = TSAttachmentStream(contentType: contentType, byteCount: UInt32(fileSize), sourceFilename: nil, caption: nil, albumMessageId: nil)
        guard attachment.write(dataSource) else {
            owsFailDebug("Could not write data source for path: \(filePath)")
            throw StickerError.assertionFailure
        }
        attachment.anySave(transaction: transaction)

        guard let attachmentId = attachment.uniqueId else {
            throw StickerError.assertionFailure
        }
        return attachmentId
    }

    @objc
    public func removeAttachment(transaction: YapDatabaseReadWriteTransaction) {
        guard let attachment = TSAttachment.fetch(uniqueId: attachmentId, transaction: transaction) else {
            owsFailDebug("Could not load attachment.")
            return
        }
        attachment.remove(with: transaction)
    }
}
