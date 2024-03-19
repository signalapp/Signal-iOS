//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension OWSLinkPreview {

    internal enum AttachmentReference {
        /// If uniqueId is nil, there is no attachment.
        case legacy(uniqueId: String?)
        /// There may or may not be an attachment, check the AttachmentReferences table.
        case v2
    }

    fileprivate var attachmentReference: AttachmentReference {
        if usesV2AttachmentReference {
            return .v2
        }
        return .legacy(uniqueId: self.legacyImageAttachmentId)
    }

    public static func withoutImage(urlString: String) -> OWSLinkPreview {
        let attachmentRef: AttachmentReference = FeatureFlags.newAttachmentsUseV2 ? .v2 : .legacy(uniqueId: nil)
        return OWSLinkPreview(urlString: urlString, title: nil, attachmentRef: attachmentRef)
    }

    // MARK: - From Proto

    internal class func attachmentReference(
        fromProto imageProto: SSKProtoAttachmentPointer?,
        tx: SDSAnyWriteTransaction
    ) throws -> AttachmentReference {
        // TODO: create v2 attachments
        return try .legacy(uniqueId: legacyAttachmentUniqueId(fromProto: imageProto, tx: tx))
    }

    fileprivate class func legacyAttachmentUniqueId(
        fromProto imageProto: SSKProtoAttachmentPointer?,
        tx: SDSAnyWriteTransaction
    ) throws -> String? {
        if let imageProto {
            if let imageAttachmentPointer = TSAttachmentPointer(fromProto: imageProto, albumMessage: nil) {
                imageAttachmentPointer.anyInsert(transaction: tx)
                return imageAttachmentPointer.uniqueId
            } else {
                Logger.error("Could not parse image proto.")
                throw LinkPreviewError.invalidPreview
            }
        }
        return nil
    }

    // MARK: - To Proto

    internal func buildProtoAttachmentPointer(tx: SDSAnyReadTransaction) -> SSKProtoAttachmentPointer? {
        // TODO: move this whole method into TSResourceManager
        switch attachmentReference {
        case .legacy(let uniqueId):
            guard
                let uniqueId,
                let stream = TSAttachmentStream.anyFetchAttachmentStream(uniqueId: uniqueId, transaction: tx),
                stream.cdnKey.isEmpty.negated,
                stream.cdnNumber > 0
            else {
                return nil
            }
            let resourceReference = TSAttachmentReference(uniqueId: uniqueId, attachment: stream)
            let pointer = TSResourcePointer(resource: stream, cdnNumber: stream.cdnNumber, cdnKey: stream.cdnKey)
            return DependenciesBridge.shared.tsResourceManager.buildProtoForSending(
                from: resourceReference,
                pointer: pointer
            )
        case .v2:
            // TODO: do a lookup on the AttachmentReferences table to build the proto.
            owsFailDebug("V2 attachments should not be used yet!")
            return nil
        }
    }

    // MARK: - From Local Draft

    internal class func saveUnownedAttachmentIfPossible(
        imageData: Data?,
        imageMimeType: String?,
        tx: SDSAnyWriteTransaction
    ) -> String? {
        // TODO: this method only exists to support legacy attachment multisend,
        // will never be used in a v2 attachment context, and can be deleted once
        // legacy attachments are deleted.
        return saveLegacyAttachmentIfPossible(
            imageData: imageData,
            imageMimeType: imageMimeType,
            tx: tx
        )
    }

    internal class func saveAttachmentIfPossible(
        imageData: Data?,
        imageMimeType: String?,
        messageRowId: Int64,
        tx: SDSAnyWriteTransaction
    ) -> AttachmentReference {
        // TODO: create v2 attachments and use the message id
        return .legacy(uniqueId: saveLegacyAttachmentIfPossible(
            imageData: imageData,
            imageMimeType: imageMimeType,
            tx: tx
        ))
    }

    internal class func saveAttachmentIfPossible(
        imageData: Data?,
        imageMimeType: String?,
        storyMessageRowId: Int64,
        tx: SDSAnyWriteTransaction
    ) -> AttachmentReference {
        // TODO: create v2 attachments and use the story message id
        return .legacy(uniqueId: saveLegacyAttachmentIfPossible(
            imageData: imageData,
            imageMimeType: imageMimeType,
            tx: tx
        ))
    }

    private class func saveLegacyAttachmentIfPossible(
        imageData: Data?,
        imageMimeType: String?,
        tx: SDSAnyWriteTransaction
    ) -> String? {
        guard let imageData = imageData else {
            return nil
        }
        guard let imageMimeType = imageMimeType else {
            return nil
        }
        guard let fileExtension = MIMETypeUtil.fileExtension(forMIMEType: imageMimeType) else {
            return nil
        }
        let fileSize = imageData.count
        guard fileSize > 0 else {
            owsFailDebug("Invalid file size for image data.")
            return nil
        }
        let contentType = imageMimeType

        let fileUrl = OWSFileSystem.temporaryFileUrl(fileExtension: fileExtension)
        do {
            try imageData.write(to: fileUrl)
            let dataSource = try DataSourcePath.dataSource(with: fileUrl, shouldDeleteOnDeallocation: true)
            // TODO: create v2 attachment stream
            let attachment = TSAttachmentStream(
                contentType: contentType,
                byteCount: UInt32(fileSize),
                sourceFilename: nil,
                caption: nil,
                attachmentType: .default,
                albumMessageId: nil
            )
            try attachment.writeConsumingDataSource(dataSource)
            attachment.anyInsert(transaction: tx)

            return attachment.uniqueId
        } catch {
            owsFailDebug("Could not write data source for: \(fileUrl), error: \(error)")
            return nil
        }
    }
}
