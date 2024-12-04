//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TSResourceManagerImpl: TSResourceManager {

    private let attachmentManager: AttachmentManagerImpl
    private let attachmentStore: AttachmentStore
    private let threadStore: ThreadStore
    private let tsResourceStore: TSResourceStore

    public init(
        attachmentManager: AttachmentManagerImpl,
        attachmentStore: AttachmentStore,
        threadStore: ThreadStore,
        tsResourceStore: TSResourceStore
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.threadStore = threadStore
        self.tsResourceStore = tsResourceStore
    }

    // MARK: - Migration

    public func didFinishTSAttachmentToAttachmentMigration(tx: DBReadTransaction) -> Bool {
        return true
    }

    // MARK: - Creating Attachments from source

    // MARK: Body Attachments (special treatment)

    public func createOversizeTextAttachmentPointer(
        from proto: SSKProtoAttachmentPointer,
        message: TSMessage,
        tx: DBWriteTransaction
    ) throws {
        guard let messageRowId = message.sqliteRowId else {
            owsFailDebug("Adding attachments to an uninserted message!")
            return
        }
        guard let threadRowId = threadStore.fetchThread(uniqueId: message.uniqueThreadId, tx: tx)?.sqliteRowId else {
            owsFailDebug("Adding attachments to an message without a thread")
            return
        }
        try attachmentManager.createAttachmentPointer(
            from: .init(
                proto: proto,
                owner: .messageOversizeText(.init(
                    messageRowId: messageRowId,
                    receivedAtTimestamp: message.receivedAtTimestamp,
                    threadRowId: threadRowId,
                    isPastEditRevision: message.isPastEditRevision()
                ))
            ),
            tx: tx
        )
    }

    public func createBodyAttachmentPointers(
        from protos: [SSKProtoAttachmentPointer],
        message: TSMessage,
        tx: DBWriteTransaction
    ) throws {
        guard let messageRowId = message.sqliteRowId else {
            owsFailDebug("Adding attachments to an uninserted message!")
            return
        }
        guard let threadRowId = threadStore.fetchThread(uniqueId: message.uniqueThreadId, tx: tx)?.sqliteRowId else {
            owsFailDebug("Adding attachments to an message without a thread")
            return
        }
        try attachmentManager.createAttachmentPointers(
            from: protos.map { proto in
                return .init(
                    proto: proto,
                    owner: .messageBodyAttachment(.init(
                        messageRowId: messageRowId,
                        receivedAtTimestamp: message.receivedAtTimestamp,
                        threadRowId: threadRowId,
                        isViewOnce: message.isViewOnceMessage,
                        isPastEditRevision: message.isPastEditRevision()
                    ))
                )
            },
            tx: tx
        )
    }

    public func createOversizeTextAttachmentStream(
        consuming dataSource: OversizeTextDataSource,
        message: TSMessage,
        tx: DBWriteTransaction
    ) throws {
        guard let messageRowId = message.sqliteRowId else {
            owsFailDebug("Adding attachments to an uninserted message!")
            return
        }
        guard let threadRowId = threadStore.fetchThread(uniqueId: message.uniqueThreadId, tx: tx)?.sqliteRowId else {
            owsFailDebug("Adding attachments to an message without a thread")
            return
        }
        try attachmentManager.createAttachmentStream(
            consuming: .init(
                dataSource: dataSource.v2DataSource,
                owner: .messageOversizeText(.init(
                    messageRowId: messageRowId,
                    receivedAtTimestamp: message.receivedAtTimestamp,
                    threadRowId: threadRowId,
                    isPastEditRevision: message.isPastEditRevision()
                ))
            ),
            tx: tx
        )
    }

    public func createBodyMediaAttachmentStreams(
        consuming dataSources: [TSResourceDataSource],
        message: TSMessage,
        tx: DBWriteTransaction
    ) throws {
        var v2DataSources = [(AttachmentDataSource, AttachmentReference.RenderingFlag)]()
        for dataSource in dataSources {
            switch dataSource.concreteType {
            case .v2(let attachmentDataSource, let renderingFlag):
                v2DataSources.append((attachmentDataSource, renderingFlag))
            }
        }
        if !v2DataSources.isEmpty {
            guard let messageRowId = message.sqliteRowId else {
                owsFailDebug("Adding attachments to an uninserted message!")
                return
            }
            guard let threadRowId = threadStore.fetchThread(uniqueId: message.uniqueThreadId, tx: tx)?.sqliteRowId else {
                owsFailDebug("Adding attachments to an message without a thread")
                return
            }
            try attachmentManager.createAttachmentStreams(
                consuming: v2DataSources.map { dataSource in
                    return .init(
                        dataSource: dataSource.0,
                        owner: .messageBodyAttachment(.init(
                            messageRowId: messageRowId,
                            receivedAtTimestamp: message.receivedAtTimestamp,
                            threadRowId: threadRowId,
                            isViewOnce: message.isViewOnceMessage,
                            isPastEditRevision: message.isPastEditRevision()
                        ))
                    )
                },
                tx: tx
            )
        }
    }

    // MARK: Other Attachments

    public func createAttachmentPointerBuilder(
        from proto: SSKProtoAttachmentPointer,
        ownerType: TSResourceOwnerType,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<TSResourceRetrievalInfo> {
        return OwnedAttachmentBuilder<TSResourceRetrievalInfo>(
            info: .v2,
            finalize: { [attachmentManager] owner, innerTx in
                return try attachmentManager.createAttachmentPointer(
                    from: .init(proto: proto, owner: owner),
                    tx: innerTx
                )
            }
        )
    }

    public func createAttachmentStreamBuilder(
        from dataSource: TSResourceDataSource,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<TSResourceRetrievalInfo> {
        switch dataSource.concreteType {
        case .v2(let attachmentDataSource, _):
            return OwnedAttachmentBuilder<TSResourceRetrievalInfo>(
                info: .v2,
                finalize: { [attachmentManager] owner, innerTx in
                    return try attachmentManager.createAttachmentStream(
                        consuming: .init(dataSource: attachmentDataSource, owner: owner),
                        tx: innerTx
                    )
                }
            )
        }
    }

    // MARK: - Outgoing Proto Creation

    public func buildProtoForSending(
        from reference: TSResourceReference,
        pointer: AttachmentTransitPointer
    ) -> SSKProtoAttachmentPointer? {
        let attachment = pointer.attachment
        let attachmentReference = reference.concreteType
        guard let attachmentPointer = AttachmentTransitPointer(attachment: attachment) else {
            owsFailDebug("Invalid attachment type combination!")
            return nil
        }
        return attachmentManager.buildProtoForSending(
            from: attachmentReference,
            pointer: attachmentPointer
        )
    }

    // MARK: - Removes and Deletes

    public func removeBodyAttachment(
        _ attachment: Attachment,
        from message: TSMessage,
        tx: DBWriteTransaction
    ) throws {
        guard let messageRowId = message.sqliteRowId else {
            owsFailDebug("Removing attachment from uninserted message!")
            return
        }
        try attachmentManager.removeAttachment(
            attachment,
            from: .messageBodyAttachment(messageRowId: messageRowId),
            tx: tx
        )
    }

    public func removeAttachments(
        from message: TSMessage,
        with types: TSMessageAttachmentReferenceType,
        tx: DBWriteTransaction
    ) throws {
        message.anyReload(transaction: SDSDB.shimOnlyBridge(tx), ignoreMissing: true)

        var v2Owners = [AttachmentReference.MessageOwnerTypeRaw]()

        if types.contains(.bodyAttachment) || types.contains(.oversizeText) {
            if types.contains(.bodyAttachment) {
                v2Owners.append(.bodyAttachment)
            }
            if types.contains(.oversizeText) {
                v2Owners.append(.oversizeText)
            }
        }

        if types.contains(.linkPreview), let linkPreview = message.linkPreview {
            v2Owners.append(.linkPreview)
        }

        if types.contains(.sticker), let messageSticker = message.messageSticker {
            v2Owners.append(.sticker)
        }

        if
            types.contains(.quotedReply),
            let quoteAttachmentInfo = message.quotedMessage?.attachmentInfo()
        {
            v2Owners.append(.quotedReplyAttachment)
        }

        if
            types.contains(.contactAvatar),
            let contactShare = message.contactShare
        {
            v2Owners.append(.contactAvatar)
        }

        guard let messageRowId = message.sqliteRowId else {
            owsFailDebug("Removing attachments from un-inserted message.")
            return
        }
        try attachmentManager.removeAllAttachments(
            from: v2Owners.map { $0.with(messageRowId: messageRowId) },
            tx: tx
        )
    }

    public func removeAttachments(from storyMessage: StoryMessage, tx: DBWriteTransaction) throws {
        guard let storyMessageRowId = storyMessage.id else {
            owsFailDebug("Removing attachments from an un-inserted message")
            return
        }
        try attachmentManager.removeAllAttachments(
            from: [
                .storyMessageMedia(storyMessageRowId: storyMessageRowId),
                .storyMessageLinkPreview(storyMessageRowId: storyMessageRowId)
            ],
            tx: tx
        )
    }

    // MARK: - Updates

    public func markPointerAsPendingManualDownload(
        _ pointer: AttachmentTransitPointer,
        tx: DBWriteTransaction
    ) {
        // Nothing to do; "pending manual download" is the default state.
        return
    }

    // MARK: - Quoted reply thumbnails

    public func newQuotedReplyMessageThumbnailBuilder(
        from dataSource: QuotedReplyTSResourceDataSource,
        fallbackQuoteProto: SSKProtoDataMessageQuote?,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<QuotedAttachmentInfo>? {
        switch dataSource.source {
        case .v2Source(let v2DataSource):
            return newV2QuotedReplyMessageThumbnailBuilder(
                from: v2DataSource,
                originalMessageRowId: dataSource.originalMessageRowId,
                tx: tx
            )
        }
    }

    private func newV2QuotedReplyMessageThumbnailBuilder(
        from dataSource: QuotedReplyAttachmentDataSource.Source,
        originalMessageRowId: Int64?,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<QuotedAttachmentInfo> {
        let (
            mimeType, sourceFilename, renderingFlag
        ): (
            String, String?, AttachmentReference.RenderingFlag
        ) = {
            switch dataSource {
            case .pendingAttachment(let pendingAttachmentSource):
                return (
                    pendingAttachmentSource.originalAttachmentMimeType,
                    pendingAttachmentSource.originalAttachmentSourceFilename,
                    pendingAttachmentSource.pendingAttachment.renderingFlag
                )
            case .originalAttachment(let originalAttachmentSource):
                return (
                    originalAttachmentSource.mimeType,
                    originalAttachmentSource.sourceFilename,
                    originalAttachmentSource.renderingFlag
                )
            case .quotedAttachmentProto(let quotedAttachmentProtoSource):
                return (
                    quotedAttachmentProtoSource.originalAttachmentMimeType,
                    quotedAttachmentProtoSource.originalAttachmentSourceFilename,
                    .fromProto(quotedAttachmentProtoSource.thumbnail)
                )
            }
        }()

        guard MimeTypeUtil.isSupportedVisualMediaMimeType(mimeType) else {
            // Can't make a thumbnail, just return a stub.
            return .withoutFinalizer(
                QuotedAttachmentInfo(
                    info: .stub(
                        withOriginalAttachmentMimeType: mimeType,
                        originalAttachmentSourceFilename: sourceFilename
                    ),
                    renderingFlag: renderingFlag
                )
            )
        }

        return OwnedAttachmentBuilder<QuotedAttachmentInfo>(
            info: QuotedAttachmentInfo(
                info: .forV2ThumbnailReference(
                    withOriginalAttachmentMimeType: mimeType,
                    originalAttachmentSourceFilename: sourceFilename
                ),
                renderingFlag: renderingFlag
            ),
            finalize: { [attachmentManager, dataSource] ownerId, tx in
                let replyMessageOwner: AttachmentReference.OwnerBuilder.MessageAttachmentBuilder
                switch ownerId {
                case .quotedReplyAttachment(let metadata):
                    replyMessageOwner = metadata
                default:
                    owsFailDebug("Invalid owner sent to quoted reply builder!")
                    return
                }

                try attachmentManager.createQuotedReplyMessageThumbnail(
                    consuming: .init(
                        dataSource: .init(originalMessageRowId: originalMessageRowId, source: dataSource),
                        owner: replyMessageOwner
                    ),
                    tx: tx
                )
            }
        )
    }

    public func thumbnailImage(
        attachment: Attachment,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) -> UIImage? {
        guard let stream = attachment.asStream() else {
            return nil
        }
        // If it is an attachment stream, it should already be pointing at the resized
        // thumbnail image, no copying needed.
        return stream.thumbnailImageSync(quality: .small)
    }
}
