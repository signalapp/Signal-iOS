//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TSAttachmentManager {

    public init() {}

    // MARK: - TSMessage Writes

    public func createBodyAttachmentPointers(
        from protos: [SSKProtoAttachmentPointer],
        message: TSMessage,
        tx: SDSAnyWriteTransaction
    ) {
        let attachmentPointers = TSAttachmentPointer.attachmentPointers(
            fromProtos: protos,
            albumMessage: message
        )
        for pointer in attachmentPointers {
            pointer.anyInsert(transaction: tx)
        }
        self.addBodyAttachments(attachmentPointers, to: message, tx: tx)
    }

    public func createBodyAttachmentStreams(
        consuming dataSources: [TSAttachmentDataSource],
        message: TSMessage,
        tx: SDSAnyWriteTransaction
    ) throws {
        try _createBodyAttachmentStreams(
            consuming: dataSources,
            message: message,
            albumMessageId: message.uniqueId,
            tx: tx
        )
    }

    public func createContactSyncAttachmentStreams(
        consuming dataSources: [TSAttachmentDataSource],
        message: TSOutgoingMessage,
        tx: SDSAnyWriteTransaction
    ) throws {
        try _createBodyAttachmentStreams(
            consuming: dataSources,
            message: message,
            // This attachment is "unowned" in the database
            // and the message is ephemeral for sending only,
            // so we don't include the owning message id.
            albumMessageId: nil,
            tx: tx
        )
    }

    private func _createBodyAttachmentStreams(
        consuming dataSources: [TSAttachmentDataSource],
        message: TSMessage,
        albumMessageId: String?,
        tx: SDSAnyWriteTransaction
    ) throws {
        let attachmentStreams = try dataSources.map { dataSource in
            return try self._createAttachmentStream(
                from: dataSource,
                albumMessageId: albumMessageId,
                tx: tx
            )
        }

        self.addBodyAttachments(attachmentStreams, to: message, tx: tx)
        attachmentStreams.forEach { $0.anyInsert(transaction: tx) }
    }

    public func removeBodyAttachment(
        _ attachment: TSAttachment,
        from message: TSMessage,
        tx: SDSAnyWriteTransaction
    ) {
        owsAssertDebug(message.attachmentIds?.contains(attachment.uniqueId) == true)
        attachment.anyRemove(transaction: tx)

        message.anyUpdateMessage(transaction: tx) { message in
            var attachmentIds = message.attachmentIds
            attachmentIds?.removeAll(where: { $0 == attachment.uniqueId })
            message.setLegacyBodyAttachmentIds(attachmentIds)
        }
    }

    // MARK: - Remove Message Attachments

    public func removeBodyAttachments(
        from message: TSMessage,
        removeMedia: Bool,
        removeOversizeText: Bool,
        tx: SDSAnyWriteTransaction
    ) {
        // We remove attachments before
        // anyUpdateWithTransaction, because anyUpdateWithTransaction's
        // block can be called twice, once on this instance and once
        // on the copy from the database.  We only want to remove
        // attachments once.

        var removedIds = Set<String>()
        for attachmentId in message.attachmentIds ?? [] {
            self.removeAttachment(
                attachmentId: attachmentId,
                filterBlock: { attachment in
                    // We can only discriminate oversize text attachments at the
                    // last minute by consulting the attachment model.
                    if attachment.isOversizeTextMimeType {
                        if removeOversizeText {
                            removedIds.insert(attachmentId)
                            return true
                        } else {
                            return false
                        }
                    } else {
                        if removeMedia {
                            removedIds.insert(attachmentId)
                            return true
                        } else {
                            return false
                        }
                    }
                },
                tx: tx
            )
        }

        message.anyUpdateMessage(transaction: tx) { message in
            message.setLegacyBodyAttachmentIds(message.attachmentIds?.filter { !removedIds.contains($0) })
        }
    }

    public func removeAttachment(
        attachmentId: String,
        tx: SDSAnyWriteTransaction
    ) {
        removeAttachment(attachmentId: attachmentId, filterBlock: { _ in true }, tx: tx)
    }

    private func removeAttachment(
        attachmentId: String,
        filterBlock: (TSAttachment) -> Bool,
        tx: SDSAnyWriteTransaction
    ) {
        if attachmentId.isEmpty {
            owsFailDebug("Invalid attachmentId")
            return
        }

        // We need to fetch each attachment, since [TSAttachment removeWithTransaction:] does important work.
        let attachment = TSAttachment.anyFetch(uniqueId: attachmentId, transaction: tx)
        guard let attachment else  {
            Logger.warn("couldn't load interaction's attachment for deletion.")
            return
        }
        if filterBlock(attachment).negated {
            return
        }
        attachment.anyRemove(transaction: tx)
    }

    // MARK: - Helpers

    private func addBodyAttachments(
        _ attachments: [TSAttachment],
        to message: TSMessage,
        tx: SDSAnyWriteTransaction
    ) {
        message.anyUpdateMessage(transaction: tx) { message in
            var attachmentIds = message.attachmentIds ?? []
            var attachmentIdSet = Set(attachmentIds)
            for attachment in attachments {
                if attachmentIdSet.contains(attachment.uniqueId) {
                    continue
                }
                attachmentIds.append(attachment.uniqueId)
                attachmentIdSet.insert(attachment.uniqueId)
            }
            message.setLegacyBodyAttachmentIds(attachmentIds)
        }
    }

    // MARK: - Quoted reply thumbnails

    func thumbnailImage(
        attachment: TSAttachment,
        info: OWSAttachmentInfo,
        parentMessage: TSMessage,
        tx: SDSAnyReadTransaction
    ) -> UIImage? {
        let attachment = self.fetchQuotedMessageThumbnailCopyingIfNeeded(
            attachment: attachment,
            info: info,
            parentMessage: parentMessage,
            tx: tx
        )

        if let attachmentStream = attachment as? TSAttachmentStream {
            return attachmentStream.thumbnailImageSmallSync()
        } else if !info.attachmentType.isThumbnailOwned {
            // If the quoted message isn't owning the thumbnail attachment, it's going to be referencing
            // some other attachment (e.g. undownloaded media). In this case, let's just use the blur hash
            if let blurHash = attachment?.blurHash {
                return BlurHash.image(for: blurHash)
            } else {
                return nil
            }
        } else {
            return nil
        }
    }

    private func fetchQuotedMessageThumbnailCopyingIfNeeded(
        attachment: TSAttachment,
        info: OWSAttachmentInfo,
        parentMessage: TSMessage,
        tx: SDSAnyReadTransaction
    ) -> TSAttachment? {
        // We should clone the attachment if it's been downloaded but our quotedMessage doesn't have its own copy.
        let needsClone = attachment is TSAttachmentStream && !info.attachmentType.isThumbnailOwned

        guard needsClone else {
            return attachment
        }

        // OH GOD THIS IS HORRIBLE keeping this now because this code will be deprecated/deleted soon.
        // If we happen to be handed a write transaction, we can perform the clone synchronously
        // Otherwise, just hand the caller what we have. We'll clone it async.
        if let writeTx = tx as? SDSAnyWriteTransaction {
            return Self.refetchMessageAndCreateThumbnailIfNeeded(
                originalParentMessageInstance: parentMessage,
                tx: writeTx
            )
        } else {
            SSKEnvironment.shared.databaseStorageRef.asyncWrite { writeTx in
                _ = Self.refetchMessageAndCreateThumbnailIfNeeded(
                    originalParentMessageInstance: parentMessage,
                    tx: writeTx
                )
            }
            return attachment
        }
    }

    /// Very important that this method is static; we call it from an async write so we need to reload everything,
    /// including the OWSAttachmentInfo, and not used the same instance with the same cached value.
    private static func refetchMessageAndCreateThumbnailIfNeeded(
        originalParentMessageInstance: TSMessage,
        tx: SDSAnyWriteTransaction
    ) -> TSAttachmentStream? {
        // This block _could_ run async, so we need to be careful to re-fetch the message
        // and its quotedMessage in case the values on disk have changed.
        guard
            let refetchedMessage = TSMessage.anyFetchMessage(uniqueId: originalParentMessageInstance.uniqueId, transaction: tx),
            let quotedMessage = refetchedMessage.quotedMessage,
            let info = quotedMessage.attachmentInfo()
        else {
            return nil
        }

        // We want to clone the existing attachment to a new attachment if necessary. This means:
        // - Fetching the attachment and making sure it's an attachment stream
        // - If we already own the attachment, we've already cloned it!
        // - Otherwise, we should copy the attachment stream to a new attachment
        // - Updating the message's state to now point to the new attachment
        guard
            let attachmentId = info.attachmentId,
            let attachmentStream = TSAttachment.anyFetch(
                uniqueId: attachmentId,
                transaction: tx
            ) as? TSAttachmentStream
        else {
            // No stream, nothing to clone. exit early.
            return nil
        }

        if info.attachmentType.isThumbnailOwned {
            // We already own it, nothing to do!
            return attachmentStream
        }

        // Do this outside the anyUpdateMessage block because that can get executed more than once.
        Logger.info("Cloning attachment to thumbnail")
        guard let thumbnailClone = attachmentStream.cloneAsThumbnail() else {
            Logger.error("Unable to clone")
            return nil
        }
        thumbnailClone.anyInsert(transaction: tx)

        originalParentMessageInstance.anyUpdateMessage(transaction: tx) { message in
            // We update the same reference the message has, so when this closure exits and the
            // message is rewritten to disk it will be rewritten with the updated quotedMessage.
            message.quotedMessage?.setLegacyThumbnailAttachmentStream(thumbnailClone)
        }
        return thumbnailClone
    }

    // MARK: - Creating quoted reply from proto

    public func createAttachmentPointer(
        from proto: SSKProtoAttachmentPointer,
        tx: SDSAnyWriteTransaction
    ) throws -> TSAttachment {
        guard
            let thumbnailAttachment = TSAttachmentPointer(fromProto: proto, albumMessage: nil)
        else {
            throw OWSAssertionError("Invalid proto, could not create attachment")
        }
        thumbnailAttachment.anyInsert(transaction: tx)
        return thumbnailAttachment
    }

    public func cloneThumbnailForNewQuotedReplyMessage(
        originalAttachment: TSAttachment,
        tx: SDSAnyWriteTransaction
    ) -> QuotedAttachmentInfo? {
        if
            let stream = originalAttachment as? TSAttachmentStream,
            MimeTypeUtil.isSupportedVisualMediaMimeType(stream.mimeType)
        {
            // We found an attachment stream on the original message! Use it as our quoted attachment
            if let thumbnail = stream.cloneAsThumbnail() {
                thumbnail.anyInsert(transaction: tx)
                return QuotedAttachmentInfo(
                    info: .withLegacyAttachmentId(
                        thumbnail.uniqueId,
                        ofType: .thumbnail,
                        originalAttachmentMimeType: stream.mimeType,
                        originalAttachmentSourceFilename: stream.sourceFilename
                    ),
                    renderingFlag: thumbnail.attachmentType.asRenderingFlag
                )
            } else {
                owsFailDebug("Unable to clone!")
                return nil
            }

        } else if
            let pointer = originalAttachment as? TSAttachmentPointer,
            MimeTypeUtil.isSupportedVisualMediaMimeType(pointer.mimeType)
        {
            // No attachment stream, but we have a pointer. It's likely this media hasn't finished downloading yet.
            return QuotedAttachmentInfo(
                info: .withLegacyAttachmentId(
                    pointer.uniqueId,
                    ofType: .original,
                    originalAttachmentMimeType: pointer.mimeType,
                    originalAttachmentSourceFilename: pointer.sourceFilename
                ),
                renderingFlag: pointer.attachmentType.asRenderingFlag
            )
        } else {
            // We have an attachment in the original message, but it doesn't support thumbnailing
            return QuotedAttachmentInfo(
                info: .stub(
                    withOriginalAttachmentMimeType: originalAttachment.mimeType,
                    originalAttachmentSourceFilename: originalAttachment.sourceFilename
                ),
                renderingFlag: originalAttachment.attachmentType.asRenderingFlag
            )
        }
    }

    // MARK: - Creating from local data

    public func createAttachmentStream(
        from dataSource: TSAttachmentDataSource,
        tx: SDSAnyWriteTransaction
    ) throws -> String {
        let attachment = try _createAttachmentStream(from: dataSource, tx: tx)
        attachment.anyInsert(transaction: tx)
        return attachment.uniqueId
    }

    private func _createAttachmentStream(
        from dataSource: TSAttachmentDataSource,
        albumMessageId: String? = nil,
        tx: SDSAnyWriteTransaction
    ) throws -> TSAttachmentStream {
        guard MimeTypeUtil.fileExtensionForMimeType(dataSource.mimeType) != nil else {
            throw OWSAssertionError("Invalid mime type!")
        }

        let attachment: TSAttachmentStream
        switch dataSource.dataSource {
        case .dataSource(let fileDataSource, let shouldCopy):
            guard fileDataSource.dataLength > 0 else {
                throw OWSAssertionError("Invalid file size for image data.")
            }

            attachment = TSAttachmentStream(
                contentType: dataSource.mimeType,
                byteCount: UInt32(fileDataSource.dataLength),
                sourceFilename: dataSource.sourceFilename,
                caption: dataSource.caption?.text,
                attachmentType: dataSource.renderingFlag.tsAttachmentType,
                albumMessageId: albumMessageId
            )
            if shouldCopy {
                try attachment.writeCopyingDataSource(fileDataSource)
            } else {
                try attachment.writeConsumingDataSource(fileDataSource)
            }
        case .data(let data):
            guard data.count > 0 else {
                throw OWSAssertionError("Invalid file size for image data.")
            }
            attachment = TSAttachmentStream(
                contentType: dataSource.mimeType,
                byteCount: UInt32(data.count),
                sourceFilename: dataSource.sourceFilename,
                caption: dataSource.caption?.text,
                attachmentType: dataSource.renderingFlag.tsAttachmentType,
                albumMessageId: albumMessageId
            )
            try attachment.write(data)
        case .existingAttachment(let uniqueId):
            guard let existingAttachment = TSAttachmentStream.anyFetchAttachmentStream(
                uniqueId: uniqueId,
                transaction: tx
            ) else {
                throw OWSAssertionError("Missing source attachment!")
            }
            let data = try existingAttachment.readDataFromFile()
            attachment = TSAttachmentStream(
                contentType: dataSource.mimeType,
                byteCount: existingAttachment.byteCount,
                sourceFilename: dataSource.sourceFilename,
                caption: dataSource.caption?.text,
                attachmentType: dataSource.renderingFlag.tsAttachmentType,
                albumMessageId: albumMessageId
            )
            try attachment.write(data)
        }
        return attachment
    }
}

fileprivate extension OWSAttachmentInfoReference {

    var isThumbnailOwned: Bool {
        switch self {
        case .untrustedPointer, .thumbnail:
            return true
        case .original, .originalForSend, .unset:
            return false
        case .V2:
            owsFailDebug("Should not have a v2 pointer in this class!")
            return true
        @unknown default:
            return false
        }
    }
}
