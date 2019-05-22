//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import Mantle

@objc
public enum EphemeralMessageError: Int, Error {
    case invalidInput
    case noEphemeralMessage
    case assertionFailure
}

// MARK: -

@objc
public class EphemeralMessageDraft: NSObject {

    @objc
    public let expiresInSeconds: UInt32

    @objc
    public let attachmentData: Data

    @objc
    public let contentType: String

    @objc
    public required init(expiresInSeconds: UInt32,
                         attachmentData: Data,
                         contentType: String) {
        self.expiresInSeconds = expiresInSeconds
        self.attachmentData = attachmentData
        self.contentType = contentType
    }
}

// MARK: -

@objc
public class EphemeralMessage: MTLModel {

    @objc
    public var expiresInSeconds: UInt32 = 0

    @objc
    public var attachmentIds = [String]()

    @objc
    public required init(expiresInSeconds: UInt32,
                         attachmentIds: [String]) {
        self.expiresInSeconds = expiresInSeconds
        self.attachmentIds = attachmentIds

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
    public var isValid: Bool {
        return expiresInSeconds > 0 && attachmentIds.count > 0
    }

    @objc
    public class func isNoEphemeralMessageError(_ error: Error) -> Bool {
        guard let error = error as? EphemeralMessageError else {
            return false
        }
        return error == .noEphemeralMessage
    }

    @objc
    public class func buildValidatedMessageEphemeralMessage(dataMessage: SSKProtoDataMessage,
                                                          transaction: SDSAnyWriteTransaction) throws -> EphemeralMessage {
        guard let ephemeralMessageProto: SSKProtoDataMessageEphemeralMessage = dataMessage.ephemeralMessage else {
            throw EphemeralMessageError.noEphemeralMessage
        }

        let expireTimer: UInt32 = ephemeralMessageProto.expireTimer
        guard let dataProto: SSKProtoAttachmentPointer = ephemeralMessageProto.attachments.first else {
            throw EphemeralMessageError.noEphemeralMessage
        }

        guard let attachmentPointer = TSAttachmentPointer(fromProto: dataProto, albumMessage: nil) else {
            throw EphemeralMessageError.invalidInput
        }
        attachmentPointer.anyInsert(transaction: transaction)
        guard let attachmentId = attachmentPointer.uniqueId else {
            throw EphemeralMessageError.assertionFailure
        }

        let ephemeralMessage = EphemeralMessage(expiresInSeconds: expireTimer, attachmentIds: [attachmentId])
        guard ephemeralMessage.isValid else {
            throw EphemeralMessageError.invalidInput
        }
        return ephemeralMessage
    }

    @objc
    public class func buildValidatedEphemeralMessage(fromDraft draft: EphemeralMessageDraft,
                                                          transaction: SDSAnyWriteTransaction) throws -> EphemeralMessage {
        let attachmentId = try saveAttachment(attachmentData: draft.attachmentData,
                                              contentType: draft.contentType,
                                              transaction: transaction)
        let ephemeralMessage = EphemeralMessage(expiresInSeconds: draft.expiresInSeconds, attachmentIds: [attachmentId])
        guard ephemeralMessage.isValid else {
            throw EphemeralMessageError.assertionFailure
        }
        return ephemeralMessage
    }

    private class func saveAttachment(attachmentData: Data,
                                      contentType: String,
                                      transaction: SDSAnyWriteTransaction) throws -> String {
        let fileSize = attachmentData.count
        guard fileSize > 0 else {
            owsFailDebug("Invalid file size for data.")
            throw EphemeralMessageError.assertionFailure
        }
        guard contentType.count > 0 else {
            owsFailDebug("Invalid content type for data.")
            throw EphemeralMessageError.assertionFailure
        }
        guard let fileExtension = MIMETypeUtil.fileExtension(forMIMEType: contentType) else {
            owsFailDebug("Could not determine file extension for content type.")
            throw EphemeralMessageError.assertionFailure
        }

        let filePath = OWSFileSystem.temporaryFilePath(withFileExtension: fileExtension)
        do {
            try attachmentData.write(to: NSURL.fileURL(withPath: filePath))
        } catch let error as NSError {
            owsFailDebug("file write failed: \(filePath), \(error)")
            throw EphemeralMessageError.assertionFailure
        }

        guard let dataSource = DataSourcePath.dataSource(withFilePath: filePath, shouldDeleteOnDeallocation: true) else {
            owsFailDebug("Could not create data source for path: \(filePath)")
            throw EphemeralMessageError.assertionFailure
        }
        let attachment = TSAttachmentStream(contentType: contentType, byteCount: UInt32(fileSize), sourceFilename: nil, caption: nil, albumMessageId: nil, shouldAlwaysPad: true)
        guard attachment.write(dataSource) else {
            owsFailDebug("Could not write data source for path: \(filePath)")
            throw EphemeralMessageError.assertionFailure
        }
        attachment.anyInsert(transaction: transaction)

        guard let attachmentId = attachment.uniqueId else {
            throw EphemeralMessageError.assertionFailure
        }
        return attachmentId
    }

    @objc
    public func removeAttachments(transaction: YapDatabaseReadWriteTransaction) {
        for attachmentId in attachmentIds {
            guard let attachment = TSAttachment.fetch(uniqueId: attachmentId, transaction: transaction) else {
                owsFailDebug("Could not load attachment.")
                return
            }
            attachment.remove(with: transaction)
        }
    }
}
