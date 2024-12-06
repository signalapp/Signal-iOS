//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class EditManagerAttachmentsImpl: EditManagerAttachments {

    private let attachmentManager: AttachmentManager
    private let attachmentStore: AttachmentStore
    private let attachmentValidator: AttachmentContentValidator
    private let linkPreviewManager: LinkPreviewManager
    private let tsMessageStore: EditManagerAttachmentsImpl.Shims.TSMessageStore

    public init(
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        attachmentValidator: AttachmentContentValidator,
        linkPreviewManager: LinkPreviewManager,
        tsMessageStore: EditManagerAttachmentsImpl.Shims.TSMessageStore
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.attachmentValidator = attachmentValidator
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
        try reconcileQuotedReply(
            editTarget: editTarget,
            latestRevision: latestRevision,
            latestRevisionRowId: latestRevisionRowId,
            priorRevision: priorRevision,
            priorRevisionRowId: priorRevisionRowId,
            threadRowId: threadRowId,
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
        try reconcileOversizeText(
            editTarget: editTarget,
            latestRevision: latestRevision,
            latestRevisionRowId: latestRevisionRowId,
            priorRevision: priorRevision,
            priorRevisionRowId: priorRevisionRowId,
            threadRowId: threadRowId,
            newOversizeText: newOversizeText,
            tx: tx
        )
        try reconcileBodyMediaAttachments(
            editTarget: editTarget,
            latestRevision: latestRevision,
            latestRevisionRowId: latestRevisionRowId,
            priorRevision: priorRevision,
            priorRevisionRowId: priorRevisionRowId,
            threadRowId: threadRowId,
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
        threadRowId: Int64,
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

            switch attachmentReferencePriorToEdit.owner {
            case .message(let messageSource):
                // Always assign the prior revision as an owner of the existing attachment.
                try attachmentStore.duplicateExistingMessageOwner(
                    messageSource,
                    with: attachmentReferencePriorToEdit,
                    newOwnerMessageRowId: priorRevisionRowId,
                    newOwnerThreadRowId: threadRowId,
                    newOwnerIsPastEditRevision: true,
                    tx: tx
                )
            default:
                throw OWSAssertionError("Invalid attachment reference type!")
            }
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
                try attachmentStore.update(
                    attachmentReferencePriorToEdit,
                    withReceivedAtTimestamp: latestRevision.receivedAtTimestamp,
                    tx: tx
                )
            }
        case .change:
            // Drop the quoted reply on the latest revision.
            if let attachmentReferencePriorToEdit {
                // Break the owner edge from the latest revision.
                try attachmentStore.removeAllOwners(
                    withId: .quotedReplyAttachment(messageRowId: latestRevisionRowId),
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
        threadRowId: Int64,
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

            switch attachmentReferencePriorToEdit.owner {
            case .message(let messageSource):
                // Always assign the prior revision as an owner of the existing attachment.
                try attachmentStore.duplicateExistingMessageOwner(
                    messageSource,
                    with: attachmentReferencePriorToEdit,
                    newOwnerMessageRowId: priorRevisionRowId,
                    newOwnerThreadRowId: threadRowId,
                    newOwnerIsPastEditRevision: true,
                    tx: tx
                )
            default:
                throw OWSAssertionError("Invalid attachment reference type!")
            }

            // Break the owner edge from the latest revision since we always
            // either drop the link preview or create a new one.
            try attachmentStore.removeAllOwners(
                withId: .messageLinkPreview(messageRowId: latestRevisionRowId),
                for: attachmentReferencePriorToEdit.attachmentRowId,
                tx: tx
            )
        }

        // Create and assign the new link preview.
        let builder = LinkPreviewBuilderImpl(
            attachmentManager: attachmentManager,
            attachmentValidator: attachmentValidator
        )
        switch newLinkPreview {
        case .none:
            break
        case .draft(let draft):
            let builder = try linkPreviewManager.buildLinkPreview(
                from: draft,
                builder: builder,
                tx: tx
            )
            tsMessageStore.update(latestRevision, with: builder.info, tx: tx)
            try builder.finalize(
                owner: .messageLinkPreview(.init(
                    messageRowId: latestRevisionRowId,
                    receivedAtTimestamp: latestRevision.receivedAtTimestamp,
                    threadRowId: threadRowId,
                    isPastEditRevision: latestRevision.isPastEditRevision()
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
                    threadRowId: threadRowId,
                    isPastEditRevision: latestRevision.isPastEditRevision()
                )),
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
        threadRowId: Int64,
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

            switch oversizeTextReferencePriorToEdit.owner {
            case .message(let messageSource):
                // If we had oversize text, always keep it on the prior revision.
                try attachmentStore.duplicateExistingMessageOwner(
                    messageSource,
                    with: oversizeTextReferencePriorToEdit,
                    newOwnerMessageRowId: priorRevisionRowId,
                    newOwnerThreadRowId: threadRowId,
                    newOwnerIsPastEditRevision: true,
                    tx: tx
                )
            default:
                throw OWSAssertionError("Invalid attachment reference type!")
            }

            // Break the owner edge from the latest revision since we always
            // either drop the oversize text or create a new one.
            try attachmentStore.removeAllOwners(
                withId: .messageOversizeText(messageRowId: latestRevisionRowId),
                for: oversizeTextReferencePriorToEdit.attachmentRowId,
                tx: tx
            )
        }

        // Create and assign the new oversize text.
        switch newOversizeText {
        case .none:
            break
        case .dataSource(let dataSource):
            let attachmentDataSource = dataSource
            try attachmentManager.createAttachmentStream(
                consuming: .init(
                    dataSource: attachmentDataSource,
                    owner: .messageOversizeText(.init(
                        messageRowId: latestRevisionRowId,
                        receivedAtTimestamp: latestRevision.receivedAtTimestamp,
                        threadRowId: threadRowId,
                        isPastEditRevision: latestRevision.isPastEditRevision()
                    ))
                ),
                tx: tx
            )
        case .proto(let protoPointer):
            try attachmentManager.createAttachmentPointer(
                from: .init(
                    proto: protoPointer,
                    owner: .messageOversizeText(.init(
                        messageRowId: latestRevisionRowId,
                        receivedAtTimestamp: latestRevision.receivedAtTimestamp,
                        threadRowId: threadRowId,
                        isPastEditRevision: latestRevision.isPastEditRevision()
                    ))
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
        threadRowId: Int64,
        tx: DBWriteTransaction
    ) throws {
        // The editTarget's copy of the message has no edits applied;
        // fetch _its_ attachment(s).
        let attachmentReferencesPriorToEdit = attachmentStore.fetchReferences(
            owner: .messageBodyAttachment(messageRowId: editTarget.message.sqliteRowId!),
            tx: tx
        )

        for attachmentReference in attachmentReferencesPriorToEdit {
            switch attachmentReference.owner {
            case .message(let messageSource):
                // Always assign the prior revision as a new owner of the existing attachment.
                try attachmentStore.duplicateExistingMessageOwner(
                    messageSource,
                    with: attachmentReference,
                    newOwnerMessageRowId: priorRevisionRowId,
                    newOwnerThreadRowId: threadRowId,
                    newOwnerIsPastEditRevision: true,
                    tx: tx
                )
            default:
                throw OWSAssertionError("Invalid attachment reference type!")
            }

            // The latest revision stays an owner; just update the timestamp.
            try attachmentStore.update(
                attachmentReference,
                withReceivedAtTimestamp: latestRevision.receivedAtTimestamp,
                tx: tx
            )
        }
    }
}
