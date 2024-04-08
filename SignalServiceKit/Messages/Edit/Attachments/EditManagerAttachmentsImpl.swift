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
        // This copy of the message has no edits applied.
        let quotedReplyPriorToEdit = editTarget.message.quotedMessage

        let attachmentReferencePriorToEdit: AttachmentReference? = FeatureFlags.readV2Attachments
            ? attachmentStore.quotedThumbnailAttachment(
                for: editTarget.message,
                tx: tx
            )
            : nil

        if let quotedReplyPriorToEdit {
            // If we had a quoted reply, always keep it on the prior revision.
            tsMessageStore.update(priorRevision, with: quotedReplyPriorToEdit, tx: tx)
        }
        if let attachmentReferencePriorToEdit {
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
            // No need to touch ownership edges, the latest revision message is already an owner
            // because it maintained the original's row id.
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
        // This copy of the message has no edits applied.
        let linkPreviewPriorToEdit = editTarget.message.linkPreview

        let attachmentReferencePriorToEdit: AttachmentReference? = FeatureFlags.readV2Attachments
            ? attachmentStore.fetchFirstReference(
                owner: .messageLinkPreview(messageRowId: editTarget.message.sqliteRowId!),
                tx: tx
            )
            : nil

        if let linkPreviewPriorToEdit {
            // If we had a link preview, always keep it on the prior revision.
            tsMessageStore.update(priorRevision, with: linkPreviewPriorToEdit, tx: tx)
        }
        if let attachmentReferencePriorToEdit {
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
        switch newLinkPreview {
        case .none:
            break
        case .draft(let draft):
            let builder = try linkPreviewManager.validateAndBuildLinkPreview(from: draft, tx: tx)
            tsMessageStore.update(latestRevision, with: builder.info, tx: tx)
            try builder.finalize(
                owner: .messageLinkPreview(messageRowId: latestRevisionRowId),
                tx: tx
            )
        case .proto(let preview, let dataMessage):
            let builder = try linkPreviewManager.validateAndBuildLinkPreview(
                from: preview,
                dataMessage: dataMessage,
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
        let oversizeTextReferencePriorToEdit = tsResourceStore.oversizeTextAttachment(
            for: editTarget.message,
            tx: tx
        )

        if let oversizeTextReferencePriorToEdit {
            // If we had oversize text, always keep it on the prior revision.
            switch oversizeTextReferencePriorToEdit.concreteType {
            case .legacy(let legacyReference):
                // For legacy references, we update the message's attachment id array.
                if let oversizeTextAttachmentId = legacyReference.attachment?.uniqueId {
                    var priorRevisionAttachmentIds = priorRevision.attachmentIds
                    if !priorRevisionAttachmentIds.contains(oversizeTextAttachmentId) {
                        // oversize text goes first
                        priorRevisionAttachmentIds.insert(oversizeTextAttachmentId, at: 0)
                    }
                    tsMessageStore.update(
                        priorRevision,
                        withLegacyBodyAttachmentIds: priorRevisionAttachmentIds,
                        tx: tx
                    )

                    var latestRevisionAttachmentIds = latestRevision.attachmentIds
                    if latestRevisionAttachmentIds.removeFirst(where: { $0 == oversizeTextAttachmentId}) != nil {
                        // Remove it from the latest revision since we always
                        // either drop the oversize text or create a new one.
                        tsMessageStore.update(
                            latestRevision,
                            withLegacyBodyAttachmentIds: latestRevisionAttachmentIds,
                            tx: tx
                        )
                    }
                }
            case .v2(let attachmentReference):
                // Always assign the prior revision as an owner of the existing attachment.
                try attachmentStore.addOwner(
                    duplicating: attachmentReference,
                    withNewOwner: .messageOversizeText(messageRowId: priorRevisionRowId),
                    tx: tx
                )

                // Break the owner edge from the latest revision since we always
                // either drop the oversize text or create a new one.
                attachmentStore.removeOwner(
                    .messageOversizeText(messageRowId: latestRevisionRowId),
                    for: attachmentReference.attachmentRowId,
                    tx: tx
                )
            }
        }

        // Create and assign the new oversize text.
        switch newOversizeText {
        case .none:
            break
        case .dataSource(let dataSource):
            guard let latestRevisionOutgoing = latestRevision as? TSOutgoingMessage else {
                throw OWSAssertionError("Can only set local data source oversize text on outgoing edits")
            }
            try tsResourceManager.createOversizeTextAttachmentStream(
                consuming: dataSource,
                message: latestRevisionOutgoing,
                tx: tx
            )
        case .proto(let protoPointer):
            try tsResourceManager.createOversizeTextAttachmentPointer(
                from: protoPointer,
                message: latestRevision,
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
        let attachmentReferencesPriorToEdit = tsResourceStore.bodyMediaAttachments(
            for: editTarget.message,
            tx: tx
        )

        var priorRevisionLegacyAttachmentIds = priorRevision.attachmentIds
        var latestRevisionLegacyAttachmentIds = latestRevision.attachmentIds
        for attachmentReferencePriorToEdit in attachmentReferencesPriorToEdit {
            // If we had a body attachment, always keep it on the prior revision.
            switch attachmentReferencePriorToEdit.concreteType {
            case .legacy(let legacyReference):
                // Keep every legacy id on both the old and new revision.
                if let attachmentId = legacyReference.attachment?.uniqueId {
                    if !priorRevisionLegacyAttachmentIds.contains(attachmentId) {
                        priorRevisionLegacyAttachmentIds.append(attachmentId)
                    }
                    if !latestRevisionLegacyAttachmentIds.contains(attachmentId) {
                        latestRevisionLegacyAttachmentIds.append(attachmentId)
                    }
                }
            case .v2(let attachmentReference):
                // Always assign the prior revision as a new owner of the existing attachment.
                // The latest revision stays an owner; no change needed as its row id is already the owner.
                try attachmentStore.addOwner(
                    duplicating: attachmentReference,
                    withNewOwner: .messageBodyAttachment(messageRowId: priorRevisionRowId),
                    tx: tx
                )
            }
        }
        tsMessageStore.update(
            priorRevision,
            withLegacyBodyAttachmentIds: priorRevisionLegacyAttachmentIds,
            tx: tx
        )
        tsMessageStore.update(
            latestRevision,
            withLegacyBodyAttachmentIds: latestRevisionLegacyAttachmentIds,
            tx: tx
        )
    }
}
