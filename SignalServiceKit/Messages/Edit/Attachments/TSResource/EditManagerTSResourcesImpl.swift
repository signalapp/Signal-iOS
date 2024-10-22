//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class EditManagerTSResourcesImpl: EditManagerTSResources {

    private let editManagerAttachments: EditManagerAttachments
    private let linkPreviewManager: LinkPreviewManager
    private let tsMessageStore: EditManagerAttachmentsImpl.Shims.TSMessageStore
    private let tsAttachmentManager = TSAttachmentManager()
    private let tsAttachmentStore = TSAttachmentStore()

    public init(
        editManagerAttachments: EditManagerAttachments,
        linkPreviewManager: LinkPreviewManager,
        tsMessageStore: EditManagerAttachmentsImpl.Shims.TSMessageStore
    ) {
        self.editManagerAttachments = editManagerAttachments
        self.linkPreviewManager = linkPreviewManager
        self.tsMessageStore = tsMessageStore
    }

    public func reconcileAttachments<EditTarget: EditMessageWrapper>(
        editTarget: EditTarget,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        threadRowId: Int64,
        newOversizeText: MessageEdits.OversizeTextSource?,
        newLinkPreview: MessageEdits.LinkPreviewSource?,
        quotedReplyEdit: MessageEdits.Edit<Void>,
        tx: DBWriteTransaction
    ) throws {
        let canUseExclusiveV2: Bool = {
            // Only use v2 if the edit target has no v1 body attachments
            guard (editTarget.message.attachmentIds ?? []).isEmpty else {
                return false
            }
            // If we are keeping the quoted reply, and its v1, we also can't use v2.
            switch quotedReplyEdit {
            case .keep:
                if editTarget.message.quotedMessage?.attachmentInfo()?.attachmentId != nil {
                    return false
                }
            case .change:
                break
            }
            return true
        }()
        if canUseExclusiveV2 {
            try editManagerAttachments.reconcileAttachments(
                editTarget: editTarget,
                latestRevision: latestRevision,
                latestRevisionRowId: latestRevisionRowId,
                priorRevision: priorRevision,
                priorRevisionRowId: priorRevisionRowId,
                threadRowId: threadRowId,
                newOversizeText: newOversizeText,
                newLinkPreview: newLinkPreview,
                quotedReplyEdit: quotedReplyEdit,
                tx: tx
            )
        } else {
            try reconcileQuotedReply(
                editTarget: editTarget,
                latestRevision: latestRevision,
                latestRevisionRowId: latestRevisionRowId,
                priorRevision: priorRevision,
                priorRevisionRowId: priorRevisionRowId,
                quotedReplyEdit: quotedReplyEdit,
                tx: tx
            )
            try reconcileLinkPreview(
                editTarget: editTarget,
                latestRevision: latestRevision,
                latestRevisionRowId: latestRevisionRowId,
                priorRevision: priorRevision,
                priorRevisionRowId: priorRevisionRowId,
                threadRowId: threadRowId,
                newLinkPreview: newLinkPreview,
                tx: tx
            )
            try reconcileBodyAttachments(
                editTarget: editTarget,
                latestRevision: latestRevision,
                latestRevisionRowId: latestRevisionRowId,
                priorRevision: priorRevision,
                priorRevisionRowId: priorRevisionRowId,
                newOversizeText: newOversizeText,
                tx: tx
            )
        }
    }

    private func reconcileQuotedReply<EditTarget: EditMessageWrapper>(
        editTarget: EditTarget,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        quotedReplyEdit: MessageEdits.Edit<Void>,
        tx: DBWriteTransaction
    ) throws {
        // This copy of the message has no edits applied.
        let quotedReplyPriorToEdit = editTarget.message.quotedMessage

        if let quotedReplyPriorToEdit {
            // If we had a quoted reply, always keep it on the prior revision.
            tsMessageStore.update(priorRevision, with: quotedReplyPriorToEdit, tx: tx)
        }

        switch quotedReplyEdit {
        case .keep:
            if let quotedReplyPriorToEdit {
                // The latest revision keeps the prior revision's quoted reply.
                tsMessageStore.update(latestRevision, with: quotedReplyPriorToEdit, tx: tx)
            }
        case .change:
            // No need to touch the TSMessage.quotedReply as it is already nil by default.
            break
        }
    }

    private func reconcileLinkPreview<EditTarget: EditMessageWrapper>(
        editTarget: EditTarget,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        threadRowId: Int64,
        newLinkPreview: MessageEdits.LinkPreviewSource?,
        tx: DBWriteTransaction
    ) throws {
        // This copy of the message has no edits applied.
        let linkPreviewPriorToEdit = editTarget.message.linkPreview

        if let linkPreviewPriorToEdit {
            // If we had a link preview, always keep it on the prior revision.
            tsMessageStore.update(priorRevision, with: linkPreviewPriorToEdit, tx: tx)
        }

        // Create and assign the new link preview.
        let builder = LinkPreviewTSAttachmentBuilder(tsAttachmentManager: tsAttachmentManager)
        switch newLinkPreview {
        case .none:
            break
        case .draft(let draft):
            let builder = try linkPreviewManager.buildLinkPreview(
                from: draft.legacyDataSource,
                builder: builder,
                ownerType: .message,
                tx: tx
            )
            tsMessageStore.update(latestRevision, with: builder.info, tx: tx)
            try builder.finalize(
                owner: .messageLinkPreview(.init(
                    messageRowId: latestRevisionRowId,
                    receivedAtTimestamp: latestRevision.receivedAtTimestamp,
                    threadRowId: threadRowId
                )),
                tx: tx
            )
        case .proto(let preview, let dataMessage):
            let linkPreviewBuilder: OwnedAttachmentBuilder<OWSLinkPreview>
            do {
                linkPreviewBuilder = try linkPreviewManager.validateAndBuildLinkPreview(
                    from: preview,
                    dataMessage: dataMessage,
                    builder: builder,
                    ownerType: .message,
                    tx: tx
                )
            } catch let error as LinkPreviewError {
                switch error {
                case .invalidPreview:
                    // Just drop the link preview, but keep the message
                    Logger.info("Dropping invalid link preview; keeping message edit")
                    return
                case .noPreview, .fetchFailure, .featureDisabled:
                    owsFailDebug("Invalid link preview error on incoming proto")
                    return
                }
            } catch let error {
                throw error
            }
            tsMessageStore.update(latestRevision, with: linkPreviewBuilder.info, tx: tx)
            try linkPreviewBuilder.finalize(
                owner: .messageLinkPreview(.init(
                    messageRowId: latestRevisionRowId,
                    receivedAtTimestamp: latestRevision.receivedAtTimestamp,
                    threadRowId: threadRowId
                )),
                tx: tx
            )
        }
    }

    private func reconcileBodyAttachments<EditTarget: EditMessageWrapper>(
        editTarget: EditTarget,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        newOversizeText: MessageEdits.OversizeTextSource?,
        tx: DBWriteTransaction
    ) throws {
        let bodyAttachmentIdsPriorToEdit = editTarget.message.attachmentIds ?? []

        // The prior revision always gets the same attachment ids.
        tsMessageStore.update(
            priorRevision,
            withLegacyBodyAttachmentIds: bodyAttachmentIdsPriorToEdit,
            tx: tx
        )

        // Create and assign the new oversize text.
        switch newOversizeText {
        case .none:
            break
        case .dataSource(let dataSource):
            guard let latestRevisionOutgoing = latestRevision as? TSOutgoingMessage else {
                throw OWSAssertionError("Can only set local data source oversize text on outgoing edits")
            }
            try tsAttachmentManager.createBodyAttachmentStreams(
                consuming: [dataSource.legacyDataSource],
                message: latestRevisionOutgoing,
                tx: SDSDB.shimOnlyBridge(tx)
            )
        case .proto(let protoPointer):
            tsAttachmentManager.createBodyAttachmentPointers(
                from: [protoPointer],
                message: latestRevision,
                tx: SDSDB.shimOnlyBridge(tx)
            )
        }

        let bodyMediaAttachmentsPriorToEdit = tsAttachmentStore.attachments(
            withAttachmentIds: bodyAttachmentIdsPriorToEdit,
            ignoringContentType: MimeType.textXSignalPlain.rawValue,
            tx: SDSDB.shimOnlyBridge(tx)
        )

        var latestRevisionLegacyAttachmentIds = latestRevision.attachmentIds ?? []
        latestRevisionLegacyAttachmentIds.append(contentsOf: bodyMediaAttachmentsPriorToEdit.map(\.uniqueId))
        tsMessageStore.update(
            latestRevision,
            withLegacyBodyAttachmentIds: latestRevisionLegacyAttachmentIds,
            tx: tx
        )
    }
}
