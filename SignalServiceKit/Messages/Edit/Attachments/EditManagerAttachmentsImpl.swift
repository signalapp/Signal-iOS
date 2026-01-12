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

    public init(
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        attachmentValidator: AttachmentContentValidator,
        linkPreviewManager: LinkPreviewManager,
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.attachmentValidator = attachmentValidator
        self.linkPreviewManager = linkPreviewManager
    }

    public func reconcileAttachments(
        uneditedTargetMessage: TSMessage,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        threadRowId: Int64,
        newOversizeText: MessageEdits.OversizeTextSource?,
        newLinkPreview: MessageEdits.LinkPreviewSource?,
        quotedReplyEdit: MessageEdits.Edit<Void>,
        tx: DBWriteTransaction,
    ) throws {
        try reconcileQuotedReply(
            uneditedTargetMessage: uneditedTargetMessage,
            latestRevision: latestRevision,
            latestRevisionRowId: latestRevisionRowId,
            priorRevision: priorRevision,
            priorRevisionRowId: priorRevisionRowId,
            threadRowId: threadRowId,
            quotedReplyEdit: quotedReplyEdit,
            tx: tx,
        )
        try reconcileLinkPreview(
            uneditedTargetMessage: uneditedTargetMessage,
            latestRevision: latestRevision,
            latestRevisionRowId: latestRevisionRowId,
            priorRevision: priorRevision,
            priorRevisionRowId: priorRevisionRowId,
            threadRowId: threadRowId,
            newLinkPreview: newLinkPreview,
            tx: tx,
        )
        try reconcileOversizeText(
            uneditedTargetMessage: uneditedTargetMessage,
            latestRevision: latestRevision,
            latestRevisionRowId: latestRevisionRowId,
            priorRevision: priorRevision,
            priorRevisionRowId: priorRevisionRowId,
            threadRowId: threadRowId,
            newOversizeText: newOversizeText,
            tx: tx,
        )
        try reconcileBodyMediaAttachments(
            uneditedTargetMessage: uneditedTargetMessage,
            latestRevision: latestRevision,
            latestRevisionRowId: latestRevisionRowId,
            priorRevision: priorRevision,
            priorRevisionRowId: priorRevisionRowId,
            threadRowId: threadRowId,
            tx: tx,
        )
    }

    // MARK: - Attachments

    private func reconcileQuotedReply(
        uneditedTargetMessage: TSMessage,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        threadRowId: Int64,
        quotedReplyEdit: MessageEdits.Edit<Void>,
        tx: DBWriteTransaction,
    ) throws {
        if let quotedReplyPriorToEdit = uneditedTargetMessage.quotedMessage {
            // If we had a quoted reply, always keep it on the prior revision.
            priorRevision.update(with: quotedReplyPriorToEdit, transaction: tx)

            switch quotedReplyEdit {
            case .keep:
                latestRevision.update(with: quotedReplyPriorToEdit, transaction: tx)
            case .change:
                break
            }
        }

        // The latest revision owns all the pre-edit attachments, because it
        // claimed the edit target's row ID.
        if
            let latestRevisionAttachmentReference = attachmentStore.fetchAnyReference(
                owner: .quotedReplyAttachment(messageRowId: latestRevisionRowId),
                tx: tx,
            )
        {
            let messageSource: AttachmentReference.Owner.MessageSource
            switch latestRevisionAttachmentReference.owner {
            case .message(let _messageSource):
                messageSource = _messageSource
            case .storyMessage, .thread:
                throw OWSAssertionError("Invalid attachment reference type!")
            }

            // Add the prior revision as an owner of the attachment. This must
            // happen before we potentially remove the reference from the latest
            // revision, to ensure the attachment refcount never hits zero.
            attachmentStore.cloneMessageOwnerForNewPastEditRevision(
                existingReference: latestRevisionAttachmentReference,
                existingOwnerSource: messageSource,
                newPastRevisionRowId: priorRevisionRowId,
                tx: tx,
            )

            switch quotedReplyEdit {
            case .keep:
                // Update the reference's timestamp to match the latest revision.
                try attachmentStore.update(
                    latestRevisionAttachmentReference,
                    withReceivedAtTimestamp: latestRevision.receivedAtTimestamp,
                    tx: tx,
                )
            case .change:
                // Drop the reference.
                try attachmentStore.removeReference(
                    reference: latestRevisionAttachmentReference,
                    tx: tx,
                )
            }
        }
    }

    private func reconcileLinkPreview(
        uneditedTargetMessage: TSMessage,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        threadRowId: Int64,
        newLinkPreview: MessageEdits.LinkPreviewSource?,
        tx: DBWriteTransaction,
    ) throws {
        if let linkPreviewPriorToEdit = uneditedTargetMessage.linkPreview {
            // If we had a link preview, always keep it on the prior revision.
            priorRevision.update(with: linkPreviewPriorToEdit, transaction: tx)
        }

        // The latest revision owns all the pre-edit attachments, because it
        // claimed the edit target's row ID.
        if
            let latestRevisionAttachmentReference = attachmentStore.fetchAnyReference(
                owner: .messageLinkPreview(messageRowId: latestRevisionRowId),
                tx: tx,
            )
        {
            let messageSource: AttachmentReference.Owner.MessageSource
            switch latestRevisionAttachmentReference.owner {
            case .message(let _messageSource):
                messageSource = _messageSource
            case .storyMessage, .thread:
                throw OWSAssertionError("Invalid attachment reference type!")
            }

            // Add the prior revision as an owner of the attachment. This must
            // happen before we potentially remove the reference from the latest
            // revision, to ensure the attachment refcount never hits zero.
            attachmentStore.cloneMessageOwnerForNewPastEditRevision(
                existingReference: latestRevisionAttachmentReference,
                existingOwnerSource: messageSource,
                newPastRevisionRowId: priorRevisionRowId,
                tx: tx,
            )

            // Remove the latest revision reference, since it's either been
            // edited out or we'll create a new one below.
            try attachmentStore.removeReference(
                reference: latestRevisionAttachmentReference,
                tx: tx,
            )
        }

        // Create and assign the new link preview.
        switch newLinkPreview {
        case .none:
            break
        case .draft(let draft):
            let validatedLinkPreview = try linkPreviewManager.validateDataSource(
                dataSource: draft,
                tx: tx,
            )

            latestRevision.update(with: validatedLinkPreview.preview, transaction: tx)

            if let imageDataSource = validatedLinkPreview.imageDataSource {
                try attachmentManager.createAttachmentStream(
                    from: OwnedAttachmentDataSource(
                        dataSource: imageDataSource,
                        owner: .messageLinkPreview(.init(
                            messageRowId: latestRevisionRowId,
                            receivedAtTimestamp: latestRevision.receivedAtTimestamp,
                            threadRowId: threadRowId,
                            isPastEditRevision: latestRevision.isPastEditRevision(),
                        )),
                    ),
                    tx: tx,
                )
            }
        case .proto(let preview, let dataMessage):
            do {
                let validatedLinkPreview = try linkPreviewManager.validateAndBuildLinkPreview(
                    from: preview,
                    dataMessage: dataMessage,
                )

                latestRevision.update(with: validatedLinkPreview.preview, transaction: tx)

                if let linkPreviewImageProto = validatedLinkPreview.imageProto {
                    try attachmentManager.createAttachmentPointer(
                        from: OwnedAttachmentPointerProto(
                            proto: linkPreviewImageProto,
                            owner: .messageLinkPreview(.init(
                                messageRowId: latestRevisionRowId,
                                receivedAtTimestamp: latestRevision.receivedAtTimestamp,
                                threadRowId: threadRowId,
                                isPastEditRevision: latestRevision.isPastEditRevision(),
                            )),
                        ),
                        tx: tx,
                    )
                }
            } catch LinkPreviewError.invalidPreview {
                // Just drop the link preview, but keep the message
                Logger.warn("Dropping invalid link preview; keeping message edit")
            }
        }
    }

    private func reconcileOversizeText(
        uneditedTargetMessage: TSMessage,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        threadRowId: Int64,
        newOversizeText: MessageEdits.OversizeTextSource?,
        tx: DBWriteTransaction,
    ) throws {
        // The latest revision owns all the pre-edit attachments, because it
        // claimed the edit target's row ID.
        if
            let latestRevisionAttachmentReference = attachmentStore.fetchAnyReference(
                owner: .messageOversizeText(messageRowId: latestRevisionRowId),
                tx: tx,
            )
        {
            let messageSource: AttachmentReference.Owner.MessageSource
            switch latestRevisionAttachmentReference.owner {
            case .message(let _messageSource):
                messageSource = _messageSource
            case .storyMessage, .thread:
                throw OWSAssertionError("Invalid attachment reference type!")
            }

            // Add the prior revision as an owner of the attachment. This must
            // happen before we potentially remove the reference from the latest
            // revision, to ensure the attachment refcount never hits zero.
            attachmentStore.cloneMessageOwnerForNewPastEditRevision(
                existingReference: latestRevisionAttachmentReference,
                existingOwnerSource: messageSource,
                newPastRevisionRowId: priorRevisionRowId,
                tx: tx,
            )

            // Remove the latest revision reference, since it's either been
            // edited out or we'll create a new one below.
            try attachmentStore.removeReference(
                reference: latestRevisionAttachmentReference,
                tx: tx,
            )
        }

        // Create and assign the new oversize text.
        switch newOversizeText {
        case .none:
            break
        case .dataSource(let dataSource):
            let attachmentDataSource = dataSource
            try attachmentManager.createAttachmentStream(
                from: OwnedAttachmentDataSource(
                    dataSource: attachmentDataSource,
                    owner: .messageOversizeText(.init(
                        messageRowId: latestRevisionRowId,
                        receivedAtTimestamp: latestRevision.receivedAtTimestamp,
                        threadRowId: threadRowId,
                        isPastEditRevision: latestRevision.isPastEditRevision(),
                    )),
                ),
                tx: tx,
            )
        case .proto(let protoPointer):
            try attachmentManager.createAttachmentPointer(
                from: OwnedAttachmentPointerProto(
                    proto: protoPointer,
                    owner: .messageOversizeText(.init(
                        messageRowId: latestRevisionRowId,
                        receivedAtTimestamp: latestRevision.receivedAtTimestamp,
                        threadRowId: threadRowId,
                        isPastEditRevision: latestRevision.isPastEditRevision(),
                    )),
                ),
                tx: tx,
            )
        }
    }

    private func reconcileBodyMediaAttachments(
        uneditedTargetMessage: TSMessage,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        threadRowId: Int64,
        tx: DBWriteTransaction,
    ) throws {
        // The latest revision owns all the pre-edit attachments, because it
        // claimed the edit target's row ID.
        let latestRevisionAttachmentReferences = attachmentStore.fetchReferences(
            owners: [.messageBodyAttachment(messageRowId: latestRevisionRowId)],
            tx: tx,
        )

        for latestRevisionAttachmentReference in latestRevisionAttachmentReferences {
            let messageSource: AttachmentReference.Owner.MessageSource
            switch latestRevisionAttachmentReference.owner {
            case .message(let _messageSource):
                messageSource = _messageSource
            case .storyMessage, .thread:
                throw OWSAssertionError("Invalid attachment reference type!")
            }

            // Add the prior revision as an owner of the attachment. This must
            // happen before we potentially remove the reference from the latest
            // revision, to ensure the attachment refcount never hits zero.
            attachmentStore.cloneMessageOwnerForNewPastEditRevision(
                existingReference: latestRevisionAttachmentReference,
                existingOwnerSource: messageSource,
                newPastRevisionRowId: priorRevisionRowId,
                tx: tx,
            )

            // Body attachments can't be edited, so the latest revision remains
            // an owner. Update the reference's timestamp to match the latest
            // revision.
            try attachmentStore.update(
                latestRevisionAttachmentReference,
                withReceivedAtTimestamp: latestRevision.receivedAtTimestamp,
                tx: tx,
            )
        }
    }
}
