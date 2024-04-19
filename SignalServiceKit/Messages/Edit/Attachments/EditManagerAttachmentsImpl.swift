//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class EditManagerAttachmentsImpl: EditManagerAttachments {

    private let attachmentManager: AttachmentManager
    private let attachmentStore: AttachmentStore
    private let linkPreviewManager: LinkPreviewManager
    private let tsMessageStore: EditManagerAttachmentsImpl.Shims.TSMessageStore
    private let tsResourceManager: TSResourceManager
    private let tsResourceStore: TSResourceStore

    public init(
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        linkPreviewManager: LinkPreviewManager,
        tsMessageStore: EditManagerAttachmentsImpl.Shims.TSMessageStore,
        tsResourceManager: TSResourceManager,
        tsResourceStore: TSResourceStore
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.linkPreviewManager = linkPreviewManager
        self.tsMessageStore = tsMessageStore
        self.tsResourceManager = tsResourceManager
        self.tsResourceStore = tsResourceStore
    }

    public func reconcileAttachments<EditTarget: EditMessageWrapper>(
        editTarget: EditTarget,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        newOversizeText: MessageEdits.OversizeTextSource?,
        newLinkPreview: MessageEdits.LinkPreviewSource?,
        quotedReplyEdit: MessageEdits.Edit<Void>,
        tx: DBWriteTransaction
    ) throws {
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
            newLinkPreview: newLinkPreview,
            tx: tx
        )
        try reconcileOversizeText(
            editTarget: editTarget,
            latestRevision: latestRevision,
            latestRevisionRowId: latestRevisionRowId,
            priorRevision: priorRevision,
            priorRevisionRowId: priorRevisionRowId,
            newOversizeText: newOversizeText,
            tx: tx
        )
        try reconcileBodyMediaAttachments(
            editTarget: editTarget,
            latestRevision: latestRevision,
            latestRevisionRowId: latestRevisionRowId,
            priorRevision: priorRevision,
            priorRevisionRowId: priorRevisionRowId,
            tx: tx
        )
    }

    // MARK: - Attachments

    private func reconcileQuotedReply<EditTarget: EditMessageWrapper>(
        editTarget: EditTarget,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        quotedReplyEdit: MessageEdits.Edit<Void>,
        tx: DBWriteTransaction
    ) throws {
        // The editTarget's copy of the message has no edits applied.
        let quotedReplyPriorToEdit = editTarget.message.quotedMessage

        let attachmentReferencePriorToEdit = attachmentStore.quotedThumbnailAttachment(
            for: editTarget.message,
            tx: tx
        )

        if let quotedReplyPriorToEdit {
            // If we had a quoted reply, always keep it on the prior revision.
            tsMessageStore.update(priorRevision, with: quotedReplyPriorToEdit, tx: tx)
        }
        if let attachmentReferencePriorToEdit {
            // IMPORTANT: we MUST assign the prior revision owner BEFORE removing
            // the new revision as owner; otherwise the removal could delete the attachment
            // before we get the chance to reassign!

            // Always assign the prior revision as an owner of the existing attachment.
            try attachmentStore.addOwner(
                duplicating: attachmentReferencePriorToEdit,
                withNewOwner: .quotedReplyAttachment(messageRowId: priorRevisionRowId),
                tx: tx
            )
        }

        switch quotedReplyEdit {
        case .keep:
            if let quotedReplyPriorToEdit {
                // The latest revision keeps the prior revision's quoted reply.
                tsMessageStore.update(latestRevision, with: quotedReplyPriorToEdit, tx: tx)
            }

            if let attachmentReferencePriorToEdit {
                // The latest revision message is already an owner because it maintained the original's row id.
                // Just update the timestamp.
                attachmentStore.update(
                    attachmentReferencePriorToEdit,
                    withReceivedAtTimestamp: latestRevision.receivedAtTimestamp,
                    tx: tx
                )
            }
        case .change:
            // Drop the quoted reply on the latest revision.
            if let attachmentReferencePriorToEdit {
                // Break the owner edge from the latest revision.
                attachmentStore.removeOwner(
                    .quotedReplyAttachment(messageRowId: latestRevisionRowId),
                    for: attachmentReferencePriorToEdit.attachmentRowId,
                    tx: tx
                )
            }
            // No need to touch the TSMessage.quotedReply as it is already nil by default.
        }
    }

    private func reconcileLinkPreview<EditTarget: EditMessageWrapper>(
        editTarget: EditTarget,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        newLinkPreview: MessageEdits.LinkPreviewSource?,
        tx: DBWriteTransaction
    ) throws {
        // The editTarget's copy of the message has no edits applied.
        let linkPreviewPriorToEdit = editTarget.message.linkPreview

        let attachmentReferencePriorToEdit = attachmentStore.fetchFirstReference(
            owner: .messageLinkPreview(messageRowId: editTarget.message.sqliteRowId!),
            tx: tx
        )

        if let linkPreviewPriorToEdit {
            // If we had a link preview, always keep it on the prior revision.
            tsMessageStore.update(priorRevision, with: linkPreviewPriorToEdit, tx: tx)
        }
        if let attachmentReferencePriorToEdit {
            // IMPORTANT: we MUST assign the prior revision owner BEFORE removing
            // the new revision as owner; otherwise the removal could delete the attachment
            // before we get the chance to reassign!

            // Always assign the prior revision as an owner of the existing attachment.
            try attachmentStore.addOwner(
                duplicating: attachmentReferencePriorToEdit,
                withNewOwner: .messageLinkPreview(messageRowId: priorRevisionRowId),
                tx: tx
            )

            // Break the owner edge from the latest revision since we always
            // either drop the link preview or create a new one.
            attachmentStore.removeOwner(
                .messageLinkPreview(messageRowId: latestRevisionRowId),
                for: attachmentReferencePriorToEdit.attachmentRowId,
                tx: tx
            )
        }

        // Create and assign the new link preview.
        let builder = LinkPreviewAttachmentBuilder(attachmentManager: attachmentManager)
        switch newLinkPreview {
        case .none:
            break
        case .draft(let draft):
            let builder = try linkPreviewManager.validateAndBuildLinkPreview(
                from: draft,
                builder: builder,
                tx: tx
            )
            tsMessageStore.update(latestRevision, with: builder.info, tx: tx)
            try builder.finalize(
                owner: .messageLinkPreview(messageRowId: latestRevisionRowId),
                tx: tx
            )
        case .proto(let preview, let dataMessage):
            let builder = try linkPreviewManager.validateAndBuildLinkPreview(
                from: preview,
                dataMessage: dataMessage,
                builder: builder,
                tx: tx
            )
            tsMessageStore.update(latestRevision, with: builder.info, tx: tx)
            try builder.finalize(
                owner: .messageLinkPreview(messageRowId: latestRevisionRowId),
                tx: tx
            )
        }
    }

    private func reconcileOversizeText<EditTarget: EditMessageWrapper>(
        editTarget: EditTarget,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        newOversizeText: MessageEdits.OversizeTextSource?,
        tx: DBWriteTransaction
    ) throws {
        // The editTarget's copy of the message has no edits applied;
        // fetch _its_ attachment.
        let oversizeTextReferencePriorToEdit = attachmentStore.fetchFirstReference(
            owner: .messageOversizeText(messageRowId: editTarget.message.sqliteRowId!),
            tx: tx
        )

        if let oversizeTextReferencePriorToEdit {
            // IMPORTANT: we MUST assign the prior revision owner BEFORE removing
            // the new revision as owner; otherwise the removal could delete the attachment
            // before we get the chance to reassign!

            // If we had oversize text, always keep it on the prior revision.
            try attachmentStore.addOwner(
                duplicating: oversizeTextReferencePriorToEdit,
                withNewOwner: .messageOversizeText(messageRowId: priorRevisionRowId),
                tx: tx
            )

            // Break the owner edge from the latest revision since we always
            // either drop the oversize text or create a new one.
            attachmentStore.removeOwner(
                .messageOversizeText(messageRowId: latestRevisionRowId),
                for: oversizeTextReferencePriorToEdit.attachmentRowId,
                tx: tx
            )
        }

        // Create and assign the new oversize text.
        switch newOversizeText {
        case .none:
            break
        case .dataSource(let dataSource):
            try attachmentManager.createAttachmentStream(
                consuming: .init(
                    dataSource: AttachmentDataSource(
                        mimeType: MimeType.textXSignalPlain.rawValue,
                        contentHash: nil,
                        sourceFilename: nil,
                        dataSource: .dataSource(dataSource, shouldCopy: false)
                    ),
                    owner: .messageOversizeText(messageRowId: latestRevisionRowId)
                ),
                tx: tx
            )
        case .proto(let protoPointer):
            try attachmentManager.createAttachmentPointer(
                from: .init(
                    proto: protoPointer,
                    owner: .messageOversizeText(messageRowId: latestRevisionRowId)
                ),
                tx: tx
            )
        }
    }

    private func reconcileBodyMediaAttachments<EditTarget: EditMessageWrapper>(
        editTarget: EditTarget,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        tx: DBWriteTransaction
    ) throws {
        // The editTarget's copy of the message has no edits applied;
        // fetch _its_ attachment(s).
        let attachmentReferencesPriorToEdit = attachmentStore.fetchReferences(
            owner: .messageBodyAttachment(messageRowId: editTarget.message.sqliteRowId!),
            tx: tx
        )

        for attachmentReference in attachmentReferencesPriorToEdit {
            // Always assign the prior revision as a new owner of the existing attachment.
            try attachmentStore.addOwner(
                duplicating: attachmentReference,
                withNewOwner: .messageBodyAttachment(messageRowId: priorRevisionRowId),
                tx: tx
            )

            // The latest revision stays an owner; just update the timestamp.
            attachmentStore.update(
                attachmentReference,
                withReceivedAtTimestamp: latestRevision.receivedAtTimestamp,
                tx: tx
            )
        }
    }
}
