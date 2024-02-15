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
        // TODO: use v2, but don't actually create any attachment.
        return OWSLinkPreview(urlString: urlString, title: nil, attachmentRef: .legacy(uniqueId: nil))
    }

    @objc
    public func imageAttachment(
        forParentMessage: TSMessage,
        tx: SDSAnyReadTransaction
    ) -> TSAttachment? {
        switch attachmentReference {
        case .legacy(let uniqueId):
            guard let uniqueId else {
                return nil
            }
            return TSAttachment.anyFetch(uniqueId: uniqueId, transaction: tx)
        case .v2:
            // TODO: do a lookup on the AttachmentReferences table and then Attachments table.
            owsFailDebug("V2 attachments should not be used yet!")
            return nil
        }
    }

    public func imageAttachmentUniqueId(
        forParentStoryMessage: StoryMessage,
        tx: SDSAnyReadTransaction
    ) -> String? {
        guard let id = forParentStoryMessage.id else {
            owsFailDebug("Should pass an already-inserted story message")
            return nil
        }
        return imageAttachmentUniqueId(
            forParentStoryMessageRowId: id,
            tx: tx
        )
    }

    public func imageAttachmentUniqueId(
        forParentStoryMessageRowId: Int64,
        tx: SDSAnyReadTransaction
    ) -> String? {
        switch attachmentReference {
        case .legacy(let uniqueId):
            return uniqueId
        case .v2:
            // TODO: do a lookup on the AttachmentReferences table.
            owsFailDebug("V2 attachments should not be used yet!")
            return nil
        }
    }

    /// Returns the unique id of the attachment if its an attachment stream; if there is no attachment
    /// or its a pointer to an undownloaded attachment, returns nil.
    @objc
    public func imageAttachmentStreamId(
        forParentMessage: TSMessage,
        tx: SDSAnyReadTransaction
    ) -> String? {
        switch attachmentReference {
        case .legacy(let uniqueId):
            guard let uniqueId else {
                return nil
            }
            return TSAttachmentStream.anyFetchAttachmentStream(uniqueId: uniqueId, transaction: tx)?.uniqueId
        case .v2:
            // TODO: do a lookup on the AttachmentReferences table.
            owsFailDebug("V2 attachments should not be used yet!")
            return nil
        }
    }

    /// Returns the unique id of the attachment regardless of type.
    @objc
    public func imageAttachmentId(
        forParentMessage: TSMessage,
        tx: SDSAnyReadTransaction
    ) -> String? {
        switch attachmentReference {
        case .legacy(let uniqueId):
            return uniqueId
        case .v2:
            // TODO: do a lookup on the AttachmentReferences table.
            owsFailDebug("V2 attachments should not be used yet!")
            return nil
        }
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
        switch attachmentReference {
        case .legacy(let uniqueId):
            guard let uniqueId else {
                return nil
            }
            return TSAttachmentStream.buildProto(
                attachmentId: uniqueId,
                caption: nil,
                attachmentType: .default,
                transaction: tx
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

    // MARK: - Removing

    @objc
    public func removeAttachment(tx: SDSAnyWriteTransaction) {
        switch attachmentReference {
        case .legacy(let uniqueId):
            guard let imageAttachmentId = uniqueId else {
                owsFailDebug("No attachment id.")
                return
            }
            guard let attachment = TSAttachment.anyFetch(uniqueId: imageAttachmentId, transaction: tx) else {
                owsFailDebug("Could not load attachment.")
                return
            }
            attachment.anyRemove(transaction: tx)
        case .v2:
            // TODO: look up and remove AttachmentReferences row.
            owsFailDebug("V2 attachments should not be used yet!")
        }
    }
}
