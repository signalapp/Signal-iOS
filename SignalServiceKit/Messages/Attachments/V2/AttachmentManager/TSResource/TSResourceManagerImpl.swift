//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TSResourceManagerImpl: TSResourceManager {

    private let attachmentManager: AttachmentManagerImpl
    private let attachmentStore: AttachmentStore
    private let threadStore: ThreadStore
    private let tsAttachmentManager: TSAttachmentManager
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
        self.tsAttachmentManager = TSAttachmentManager()
        self.tsResourceStore = tsResourceStore
    }

    // MARK: - Migration

    public func didFinishTSAttachmentToAttachmentMigration(tx: DBReadTransaction) -> Bool {
        let tx = SDSDB.shimOnlyBridge(tx)
        return IncrementalTSAttachmentMigrationStore().getState(tx: tx) == .finished
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
                    threadRowId: threadRowId
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
                        isViewOnce: message.isViewOnceMessage
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
        if let attachmentDataSource = dataSource.v2DataSource {
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
                    dataSource: attachmentDataSource,
                    owner: .messageOversizeText(.init(
                        messageRowId: messageRowId,
                        receivedAtTimestamp: message.receivedAtTimestamp,
                        threadRowId: threadRowId
                    ))
                ),
                tx: tx
            )
        } else {
            try tsAttachmentManager.createBodyAttachmentStreams(
                consuming: [dataSource.legacyDataSource],
                message: message,
                tx: SDSDB.shimOnlyBridge(tx)
            )
        }
    }

    public func createBodyMediaAttachmentStreams(
        consuming dataSources: [TSResourceDataSource],
        message: TSMessage,
        tx: DBWriteTransaction
    ) throws {
        var legacyDataSources = [TSAttachmentDataSource]()
        var v2DataSources = [(AttachmentDataSource, AttachmentReference.RenderingFlag)]()
        for dataSource in dataSources {
            switch dataSource.concreteType {
            case .legacy(let tsAttachmentDataSource):
                legacyDataSources.append(tsAttachmentDataSource)
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
                            isViewOnce: message.isViewOnceMessage
                        ))
                    )
                },
                tx: tx
            )
        }
        if !legacyDataSources.isEmpty {
            try tsAttachmentManager.createBodyAttachmentStreams(
                consuming: legacyDataSources,
                message: message,
                tx: SDSDB.shimOnlyBridge(tx)
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
        case .legacy(let tsAttachmentDataSource):
            let attachmentId = try tsAttachmentManager.createAttachmentStream(
                from: tsAttachmentDataSource,
                tx: SDSDB.shimOnlyBridge(tx)
            )
            return .withoutFinalizer(.legacy(uniqueId: attachmentId))
        }
    }

    // MARK: - Outgoing Proto Creation

    public func buildProtoForSending(
        from reference: TSResourceReference,
        pointer: TSResourcePointer
    ) -> SSKProtoAttachmentPointer? {
        switch pointer.resource.concreteType {
        case .legacy(let tsAttachment):
            guard let stream = tsAttachment as? TSAttachmentStream else {
                return nil
            }
            return stream.buildProto()
        case .v2(let attachment):
            switch reference.concreteType {
            case .legacy:
                owsFailDebug("Invalid attachment type combination!")
                return nil
            case .v2(let attachmentReference):
                guard let attachmentPointer = AttachmentTransitPointer(attachment: attachment) else {
                    owsFailDebug("Invalid attachment type combination!")
                    return nil
                }
                return attachmentManager.buildProtoForSending(
                    from: attachmentReference,
                    pointer: attachmentPointer
                )
            }
        }
    }

    // MARK: - Removes and Deletes

    public func removeBodyAttachment(
        _ attachment: TSResource,
        from message: TSMessage,
        tx: DBWriteTransaction
    ) throws {
        switch attachment.concreteType {
        case .legacy(let legacyAttachment):
            tsAttachmentManager.removeBodyAttachment(legacyAttachment, from: message, tx: SDSDB.shimOnlyBridge(tx))
        case .v2(let attachment):
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
    }

    public func removeAttachments(
        from message: TSMessage,
        with types: TSMessageAttachmentReferenceType,
        tx: DBWriteTransaction
    ) throws {
        message.anyReload(transaction: SDSDB.shimOnlyBridge(tx), ignoreMissing: true)

        var v2Owners = [AttachmentReference.MessageOwnerTypeRaw]()

        if types.contains(.bodyAttachment) || types.contains(.oversizeText) {
            if (message.attachmentIds ?? []).count > 0 {
                tsAttachmentManager.removeBodyAttachments(
                    from: message,
                    removeMedia: types.contains(.bodyAttachment),
                    removeOversizeText: types.contains(.oversizeText),
                    tx: SDSDB.shimOnlyBridge(tx)
                )
            } else {
                if types.contains(.bodyAttachment) {
                    v2Owners.append(.bodyAttachment)
                }
                if types.contains(.oversizeText) {
                    v2Owners.append(.oversizeText)
                }
            }
        }

        if types.contains(.linkPreview), let linkPreview = message.linkPreview {
            if linkPreview.usesV2AttachmentReference {
                v2Owners.append(.linkPreview)
            } else if let attachmentId = linkPreview.legacyImageAttachmentId?.nilIfEmpty {
                tsAttachmentManager.removeAttachment(
                    attachmentId: attachmentId,
                    tx: SDSDB.shimOnlyBridge(tx)
                )
            }
        }

        if types.contains(.sticker), let messageSticker = message.messageSticker {
            if let legacyAttachmentId = messageSticker.legacyAttachmentId {
                tsAttachmentManager.removeAttachment(attachmentId: legacyAttachmentId, tx: SDSDB.shimOnlyBridge(tx))
            } else {
                v2Owners.append(.sticker)
            }
        }

        if
            types.contains(.quotedReply),
            let quoteAttachmentInfo = message.quotedMessage?.attachmentInfo()
        {
            if quoteAttachmentInfo.attachmentType == OWSAttachmentInfoReference.V2 {
                v2Owners.append(.quotedReplyAttachment)
            } else if let id = quoteAttachmentInfo.attachmentId {
                tsAttachmentManager.removeAttachment(attachmentId: id, tx: SDSDB.shimOnlyBridge(tx))
            }
        }

        if
            types.contains(.contactAvatar),
            let contactShare = message.contactShare
        {
            if let legacyAvatarAttachmentId = contactShare.legacyAvatarAttachmentId {
                tsAttachmentManager.removeAttachment(
                    attachmentId: legacyAvatarAttachmentId,
                    tx: SDSDB.shimOnlyBridge(tx)
                )
            } else {
                v2Owners.append(.contactAvatar)
            }
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
        switch storyMessage.attachment {
        case .file(let storyMessageFileAttachment):
            tsAttachmentManager.removeAttachment(
                attachmentId: storyMessageFileAttachment.attachmentId,
                tx: SDSDB.shimOnlyBridge(tx)
            )
        case .text(let textAttachment):
            if let attachmentId = textAttachment.preview?.legacyImageAttachmentId {
                tsAttachmentManager.removeAttachment(
                    attachmentId: attachmentId,
                    tx: SDSDB.shimOnlyBridge(tx)
                )
            }
        case .foreignReferenceAttachment:
            break
        }
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
        _ pointer: TSResourcePointer,
        tx: DBWriteTransaction
    ) {
        switch pointer.resource.concreteType {
        case .legacy(let tsAttachment):
            if let pointer = tsAttachment as? TSAttachmentPointer {
                pointer.updateAttachmentPointerState(.pendingManualDownload, transaction: SDSDB.shimOnlyBridge(tx))
            } else {
                // This just means its already a stream and the state is irrelevant.
                return
            }
        case .v2:
            // Nothing to do; "pending manual download" is the default state.
            return
        }
    }

    // MARK: - Quoted reply thumbnails

    public func newQuotedReplyMessageThumbnailBuilder(
        from dataSource: QuotedReplyTSResourceDataSource,
        fallbackQuoteProto: SSKProtoDataMessageQuote?,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<QuotedAttachmentInfo>? {
        switch dataSource.source {
        case .originalLegacyAttachment(let attachmentUniqueId):
            guard
                let attachment = tsResourceStore.fetch(
                    [.legacy(uniqueId: attachmentUniqueId)],
                    tx: tx
                ).first as? TSAttachment
            else {
                return nil
            }
            // We are in a conundrum. New messages should be using v2 attachments, but
            // we are quoting a legacy message attachment.
            // The process of cloning a legacy attachment as a v2 attachment is asynchronous
            // and cannot be done in this write transaction.
            // So we will try the following in order:
            // 1. Use the provided fallback proto (meaning the user will need to download
            //    the quote thumbnail from the sender's cdn upload, even though we already
            //    technically have the original source locally. Not a big deal.)
            // 2. Otherwise try and use the cdn info from the v1 attachment, if it still exists,
            //    and use that to create a new v2 attachment (even if the v1 is already downloaded).
            // 3. Give up. Omit the thumbnail.
            if
                let quoteAttachmentProto = fallbackQuoteProto?.attachments.first,
                let quoteAttachmentContentType = quoteAttachmentProto.contentType,
                let quoteAttachmentThumnail = quoteAttachmentProto.thumbnail
            {
                return newV2QuotedReplyMessageThumbnailBuilder(
                    from: .quotedAttachmentProto(.init(
                        thumbnail: quoteAttachmentThumnail,
                        originalAttachmentMimeType: quoteAttachmentContentType,
                        originalAttachmentSourceFilename: quoteAttachmentProto.fileName
                    )),
                    originalMessageRowId: dataSource.originalMessageRowId,
                    tx: tx
                )
            } else if let phonyThumbnailAttachmentProto = Self.buildProtoAsIfWeReceivedThisAttachment(attachment) {
                return newV2QuotedReplyMessageThumbnailBuilder(
                    from: .quotedAttachmentProto(.init(
                        thumbnail: phonyThumbnailAttachmentProto,
                        originalAttachmentMimeType: attachment.mimeType,
                        originalAttachmentSourceFilename: attachment.sourceFilename
                    )),
                    originalMessageRowId: dataSource.originalMessageRowId,
                    tx: tx
                )
            } else {
                return nil
            }
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
        attachment: TSResource,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) -> UIImage? {
        switch attachment.concreteType {
        case .v2(let attachment):
            guard let stream = attachment.asStream() else {
                return nil
            }
            // If it is an attachment stream, it should already be pointing at the resized
            // thumbnail image, no copying needed.
            return stream.thumbnailImageSync(quality: .small)
        case .legacy(let tsAttachment):
            guard let info = parentMessage.quotedMessage?.attachmentInfo() else {
                return nil
            }
            return tsAttachmentManager.thumbnailImage(
                attachment: tsAttachment,
                info: info,
                parentMessage: parentMessage,
                tx: SDSDB.shimOnlyBridge(tx)
            )
        }
    }

    public static func buildProtoAsIfWeReceivedThisAttachment(_ attachment: TSAttachment) -> SSKProtoAttachmentPointer? {
        guard
            attachment.cdnNumber >= 3,
            attachment.cdnKey.isEmpty.negated,
            let encryptionKey = attachment.encryptionKey
        else {
            return nil
        }
        let builder = SSKProtoAttachmentPointer.builder()

        builder.setCdnNumber(attachment.cdnNumber)
        builder.setCdnKey(attachment.cdnKey)

        builder.setContentType(attachment.mimeType)

        attachment.sourceFilename.map(builder.setFileName(_:))

        if let flags = attachment.attachmentType.asRenderingFlag.toProto() {
            builder.setFlags(UInt32(flags.rawValue))
        } else {
            builder.setFlags(0)
        }
        attachment.caption.map(builder.setCaption(_:))

        if
            attachment.isVisualMediaMimeType,
            let imageSizePixels = (attachment as? TSAttachmentStream)?.imageSizePixels,
            let imageWidth = UInt32(exactly: imageSizePixels.width.rounded()),
            let imageHeight = UInt32(exactly: imageSizePixels.height.rounded())
        {
            builder.setWidth(imageWidth)
            builder.setHeight(imageHeight)
        }

        if attachment.byteCount > 0 {
            builder.setSize(attachment.byteCount)
        }
        builder.setKey(encryptionKey)
        if let blurHash = attachment.blurHash?.nilIfEmpty {
            builder.setBlurHash(blurHash)
        }
        if
            let digest = (attachment as? TSAttachmentPointer)?.digest
                ?? (attachment as? TSAttachmentStream)?.digest
        {
            builder.setDigest(digest)
        }

        return builder.buildInfallibly()
    }
}
