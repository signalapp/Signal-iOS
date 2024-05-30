//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AttachmentManagerImpl: AttachmentManager {

    private let attachmentStore: AttachmentStore

    public init(attachmentStore: AttachmentStore) {
        self.attachmentStore = attachmentStore
    }

    // MARK: - Public

    // MARK: Creating Attachments from source

    public func createAttachmentPointers(
        from protos: [OwnedAttachmentPointerProto],
        tx: DBWriteTransaction
    ) throws {
        try createAttachments(
            protos,
            mimeType: \.proto.contentType,
            owner: \.owner,
            createFn: self._createAttachmentPointer(from:sourceOrder:tx:),
            tx: tx
        )
    }

    public func createAttachmentStreams(
        consuming dataSources: [OwnedAttachmentDataSource],
        tx: DBWriteTransaction
    ) throws {
        try createAttachments(
            dataSources,
            mimeType: { $0.mimeType },
            owner: \.owner,
            createFn: self._createAttachmentStream(consuming:sourceOrder:tx:),
            tx: tx
        )
    }

    // MARK: Quoted Replies

    public func quotedReplyAttachmentInfo(
        originalMessage: TSMessage,
        tx: DBReadTransaction
    ) -> QuotedAttachmentInfo? {
        return _quotedReplyAttachmentInfo(originalMessage: originalMessage, tx: tx)?.info
    }

    public func createQuotedReplyMessageThumbnail(
        originalMessage: TSMessage,
        quotedReplyMessageId: Int64,
        tx: DBWriteTransaction
    ) throws {
        guard
            let info = _quotedReplyAttachmentInfo(originalMessage: originalMessage, tx: tx),
            // Not a stub! Stubs would be .unset
            info.info.info.attachmentType == .V2
        else {
            return
        }
        try _createQuotedReplyMessageThumbnail(
            originalReference: info.originalAttachmentReference,
            originalAttachment: info.originalAttachment,
            quotedReplyMessageId: quotedReplyMessageId,
            tx: tx
        )
    }

    // MARK: Removing Attachments

    public func removeAttachment(
        _ attachment: Attachment,
        from owner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    ) throws {
        try attachmentStore.removeOwner(
            owner,
            for: attachment.id,
            tx: tx
        )
    }

    public func removeAllAttachments(
        from owners: [AttachmentReference.OwnerId],
        tx: DBWriteTransaction
    ) throws {
        try attachmentStore.fetchReferences(owners: owners, tx: tx)
            .forEach { reference in
                try attachmentStore.removeOwner(
                    reference.owner.id,
                    for: reference.attachmentRowId,
                    tx: tx
                )
            }
    }

    // MARK: - Helpers

    private typealias OwnerId = AttachmentReference.OwnerId
    private typealias OwnerBuilder = AttachmentReference.OwnerBuilder

    // MARK: Creating Attachments from source

    private func createAttachments<T>(
        _ inputArray: [T],
        mimeType: (T) -> String?,
        owner: (T) -> OwnerBuilder,
        createFn: (T, Int?, DBWriteTransaction) throws -> Void,
        tx: DBWriteTransaction
    ) throws {
        var indexOffset = 0
        for (i, input) in inputArray.enumerated() {
            let sourceOrder: Int?
            var ownerForInput = owner(input)
            switch ownerForInput {
            case .messageBodyAttachment(let bodyOwnerBuilder):
                // Convert text mime type attachments in the first spot to oversize text.
                if mimeType(input) == MimeType.textXSignalPlain.rawValue {
                    ownerForInput = .messageOversizeText(messageRowId: bodyOwnerBuilder.messageRowId)
                    indexOffset = -1
                }
                sourceOrder = i + indexOffset
            default:
                sourceOrder = nil
                if inputArray.count > 0 {
                    // Only allow multiple attachments in the case of message body attachments.
                    owsFailDebug("Can't have multiple attachments under the same owner reference!")
                }
            }

            try createFn(input, sourceOrder, tx)
        }
    }

    private func _createAttachmentPointer(
        from protoAndOwner: OwnedAttachmentPointerProto,
        // Nil if no order is to be applied.
        sourceOrder: Int?,
        tx: DBWriteTransaction
    ) throws {
        let proto = protoAndOwner.proto
        let owner = protoAndOwner.owner
        let cdnNumber = proto.cdnNumber
        guard let cdnKey = proto.cdnKey?.nilIfEmpty, cdnNumber > 0 else {
            throw OWSAssertionError("Invalid cdn info")
        }
        guard let encryptionKey = proto.key?.nilIfEmpty else {
            throw OWSAssertionError("Invalid encryption key")
        }

        let mimeType: String
        if let protoMimeType = proto.contentType?.nilIfEmpty {
            mimeType = protoMimeType
        } else {
            // Content type might not set if the sending client can't
            // infer a MIME type from the file extension.
            Logger.warn("Invalid attachment content type.")
            if
                let sourceFilename = proto.fileName,
                let fileExtension = sourceFilename.fileExtension?.lowercased().nilIfEmpty,
                let inferredMimeType = MimeTypeUtil.mimeTypeForFileExtension(fileExtension)?.nilIfEmpty
            {
                mimeType = inferredMimeType
            } else {
                mimeType = MimeType.applicationOctetStream.rawValue
            }
        }

        let sourceFilename =  proto.fileName

        let attachment: Attachment = {
            // TODO: Create and insert Attachment for the provided proto.
            fatalError("Unimplemented")
        }()
        let attachmentReference: AttachmentReference = {
            // TODO: Create and insert AttachmentReference from the provided message to the new Attachment
            fatalError("Unimplemented")
        }()
    }

    private func _createAttachmentStream(
        consuming dataSource: OwnedAttachmentDataSource,
        // Nil if no order is to be applied.
        sourceOrder: Int?,
        tx: DBWriteTransaction
    ) throws {
        guard let fileExtension = MimeTypeUtil.fileExtensionForMimeType(dataSource.mimeType) else {
            throw OWSAssertionError("Invalid mime type!")
        }

        switch dataSource.dataSource {
        case .dataSource(let fileDataSource, _):
            guard fileDataSource.dataLength > 0 else {
                throw OWSAssertionError("Invalid file size for data.")
            }
        case .data(let data):
            guard data.count > 0 else {
                throw OWSAssertionError("Invalid size for data.")
            }
        case .existingAttachment(let id):
            guard let existingAttachment = attachmentStore.fetch(id: id, tx: tx) else {
                throw OWSAssertionError("Missing existing attachment!")
            }
        }

        let attachment: Attachment = {
            // TODO: Create and insert Attachment for the provided data.

            // IMPORTANT: respect dataSource.shouldCopyDataSource
            fatalError("Unimplemented")
        }()
        let attachmentReference: AttachmentReference = {
            // TODO: Create and insert AttachmentReference from the provided owner to the new Attachment
            fatalError("Unimplemented")
        }()
    }

    // MARK: Quoted Replies

    private struct WrappedQuotedAttachmentInfo {
        let originalAttachmentReference: AttachmentReference
        let originalAttachment: Attachment
        let info: QuotedAttachmentInfo
    }

    private func _quotedReplyAttachmentInfo(
        originalMessage: TSMessage,
        tx: DBReadTransaction
    ) -> WrappedQuotedAttachmentInfo? {
        guard
            let originalReference = attachmentStore.attachmentToUseInQuote(
                originalMessage: originalMessage,
                tx: tx
            ),
            let originalAttachment = attachmentStore.fetch(id: originalReference.attachmentRowId, tx: tx)
        else {
            return nil
        }
        return .init(
            originalAttachmentReference: originalReference,
            originalAttachment: originalAttachment,
            info: {
                guard MimeTypeUtil.isSupportedVisualMediaMimeType(originalAttachment.mimeType) else {
                    // Can't make a thumbnail, just return a stub.
                    return .init(
                        info: OWSAttachmentInfo(
                            stubWithMimeType: originalAttachment.mimeType,
                            sourceFilename: originalReference.sourceFilename
                        ),
                        renderingFlag: originalReference.renderingFlag
                    )
                }
                return .init(
                    info: OWSAttachmentInfo(forV2ThumbnailReference: ()),
                    renderingFlag: originalReference.renderingFlag
                )
            }()
        )
    }

    private func _createQuotedReplyMessageThumbnail(
        originalReference: AttachmentReference,
        originalAttachment: Attachment,
        quotedReplyMessageId: Int64,
        tx: DBWriteTransaction
    ) throws {
        guard let originalStream = originalAttachment.asStream() else {
            let mimeType = originalAttachment.mimeType
            let sourceFilename = originalReference.sourceFilename
            let renderingFlag = originalReference.renderingFlag

            let attachmentReference: AttachmentReference = {
                // TODO: create and insert a new reference to the same attachment pointer from the new message.
                fatalError("Unimplemented")
            }()
            return
        }

        let targetThumbnailMimeType = OWSThumbnailService.thumbnailMimetype(
            forContentType: originalAttachment.mimeType
        )
        let originalAttachmentId: Attachment.IDType = originalAttachment.id
        let sourceFilename = originalReference.sourceFilename
        let renderingFlag = originalReference.renderingFlag

        guard
            let originalAttachment = self.attachmentStore.fetch(
                id: originalAttachmentId,
                tx: tx
            )
        else {
            owsFailDebug("Original attachment in quote was lost!")
            return
        }

        self.cloneAsThumbnailAndCreateReference(
            originalStream,
            newOwner: .quotedReplyAttachment(messageRowId: quotedReplyMessageId),
            sourceFilename: sourceFilename,
            renderingFlag: renderingFlag,
            targetThumbnailMimeType: targetThumbnailMimeType,
            tx: tx
        )
    }

    private func cloneAsThumbnailAndCreateReference(
        _ originalAttachment: AttachmentStream,
        newOwner: AttachmentReference.OwnerId,
        sourceFilename: String?,
        renderingFlag: AttachmentReference.RenderingFlag,
        targetThumbnailMimeType: String,
        tx: DBWriteTransaction
    ) {
        let isAlreadyThumbnailSizeImage: Bool = {
            switch originalAttachment.contentType {
            case .image(let pixelSize):
                let pointSize = AttachmentStream.pointSize(pixelSize: pixelSize)
                return pointSize.width < AttachmentStream.thumbnailDimensionPointsForQuotedReply
                    && pointSize.height < AttachmentStream.thumbnailDimensionPointsForQuotedReply
            default:
                return false
            }
        }()
        if isAlreadyThumbnailSizeImage {
            let attachmentReference = {
                // TODO: create+insert an AttachmentReference from the new message to the old attachment
                fatalError("Unimplemented")
            }()
        } else {
            let attachment = {
                // TODO: create and insert new cloned thumbnail attachment
                // of size AttachmentStream.thumbnailDimensionPointsForQuotedReply
                fatalError("Unimplemented")
            }()
            let attachmentReference = {
                // TODO: create+insert an AttachmentReference from the new message to the new attachment
                fatalError("Unimplemented")
            }()
        }
    }
}
