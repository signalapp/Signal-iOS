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

    public func createAttachmentPointers(
        from protos: [SSKProtoAttachmentPointer],
        owner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    ) {
        fatalError("Unimplemented")
    }

    public func createQuotedReplyAttachmentBuilder(
        fromUntrustedRemote proto: SSKProtoAttachmentPointer,
        tx: DBReadTransaction
    ) -> QuotedMessageAttachmentBuilder? {
        let cdnNumber = proto.cdnNumber
        guard let cdnKey = proto.cdnKey?.nilIfEmpty, cdnNumber > 0 else {
            owsFailDebug("Invalid cdn info")
            return nil
        }
        guard let encryptionKey = proto.key?.nilIfEmpty else {
            owsFailDebug("Invalid encryption key")
            return nil
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
                let inferredMimeType = MIMETypeUtil.mimeType(forFileExtension: fileExtension)?.nilIfEmpty
            {
                mimeType = inferredMimeType
            } else {
                mimeType = OWSMimeTypeApplicationOctetStream
            }
        }

        let sourceFilename =  proto.fileName
        return QuotedAttachmentBuilder(
            attachmentInfo: OWSAttachmentInfo(
                attachmentId: nil,
                ofType: .V2,
                contentType: mimeType,
                sourceFilename: sourceFilename
            ),
            finalizeBlock: { [self] (newMessageRowId: Int64, tx: DBWriteTransaction) in
                let attachment: Attachment = {
                    // TODO: Create and insert Attachment for the provided proto.
                    fatalError("Unimplemented")
                }()
                let attachmentReference: AttachmentReference = {
                    // TODO: Create and insert AttachmentReference from the provided message to the new Attachment
                    fatalError("Unimplemented")
                }()
            }
        )
    }

    public func createAttachmentStreams(
        consumingDataSourcesOf unsavedAttachmentInfos: [OutgoingAttachmentInfo],
        owner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    ) throws {
        fatalError("Unimplemented")
    }

    public func newQuotedReplyMessageThumbnailBuilder(
        originalMessage: TSMessage,
        tx: DBReadTransaction
    ) -> QuotedMessageAttachmentBuilder? {
        guard
            let originalReference = attachmentStore.attachmentToUseInQuote(
                originalMessage: originalMessage,
                tx: tx
            )
        else {
            return nil
        }
        return newQuotedReplyMessageThumbnailBuilder(
            originalReference: originalReference,
            tx: tx
        )
    }

    public func removeAttachment(
        _ attachment: TSResource,
        from owner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    ) {
        fatalError("Unimplemented")
    }

    public func removeAllAttachments(
        from owners: [AttachmentReference.OwnerId],
        tx: DBWriteTransaction
    ) {
        fatalError("Unimplemented")
    }

    // MARK: - Helpers

    private class QuotedAttachmentBuilder: QuotedMessageAttachmentBuilder {
        let attachmentInfo: OWSAttachmentInfo

        let finalizeBlock: (_ newMessageRowId: Int64, _ tx: DBWriteTransaction) -> Void

        init(
            attachmentInfo: OWSAttachmentInfo,
            finalizeBlock: @escaping (_ newMessageRowId: Int64, _ tx: DBWriteTransaction) -> Void
        ) {
            self.attachmentInfo = attachmentInfo
            self.finalizeBlock = finalizeBlock
        }

        var hasBeenFinalized: Bool = false
        func finalize(newMessageRowId: Int64, tx: DBWriteTransaction) {
            finalizeBlock(newMessageRowId, tx)
            hasBeenFinalized = true
        }
    }

    func newQuotedReplyMessageThumbnailBuilder(
        originalReference: AttachmentReference,
        tx: DBReadTransaction
    ) -> QuotedMessageAttachmentBuilder? {
        guard
            let originalAttachment = attachmentStore.fetch(id: originalReference.attachmentRowId, tx: tx)
        else {
            return nil
        }
        guard MIMETypeUtil.canMakeThumbnail(originalAttachment.mimeType) else {
            // Can't make a thumbnail!
            return NoOpFinalizingAttachmentBuilder(
                attachmentInfo: OWSAttachmentInfo(
                    attachmentId: nil,
                    ofType: .unset,
                    contentType: originalAttachment.mimeType,
                    sourceFilename: originalReference.sourceFilename
                )
            )
        }
        guard let originalStream = originalAttachment.asStream() else {
            let mimeType = originalAttachment.mimeType
            let sourceFilename = originalReference.sourceFilename
            let renderingFlag = originalReference.renderingFlag

            return Self.QuotedAttachmentBuilder(
                attachmentInfo: OWSAttachmentInfo(
                    attachmentId: nil,
                    ofType: .V2,
                    contentType: mimeType,
                    sourceFilename: sourceFilename
                ),
                finalizeBlock: { [self] (newMessageRowId: Int64, tx: DBWriteTransaction) in
                    let attachmentReference: AttachmentReference = {
                        // TODO: create and insert a new reference to the same attachment pointer from the new message.
                        fatalError("Unimplemented")
                    }()
                }
            )
        }

        let targetThumbnailMimeType = OWSThumbnailService.thumbnailMimetype(
            forContentType: originalAttachment.mimeType
        )
        let originalAttachmentId: Attachment.IDType = originalAttachment.id
        let sourceFilename = originalReference.sourceFilename
        let renderingFlag = originalReference.renderingFlag

        return Self.QuotedAttachmentBuilder(
            attachmentInfo: OWSAttachmentInfo(
                attachmentId: nil,
                ofType: .V2,
                contentType: targetThumbnailMimeType,
                sourceFilename: sourceFilename
            ),
            finalizeBlock: { [self, originalAttachmentId] (newMessageRowId: Int64, tx: DBWriteTransaction) in
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
                    originalAttachment,
                    newOwner: .quotedReplyAttachment(messageRowId: newMessageRowId),
                    sourceFilename: sourceFilename,
                    renderingFlag: renderingFlag,
                    targetThumbnailMimeType: targetThumbnailMimeType,
                    tx: tx
                )
            }
        )
    }

    private func cloneAsThumbnailAndCreateReference(
        _ originalAttachment: Attachment,
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
