//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class EditManagerTSResourcesImpl: EditManagerTSResources {

    private let editManagerAttachments: EditManagerAttachments
    private let linkPreviewManager: LinkPreviewManager
    private let tsMessageStore: EditManagerAttachmentsImpl.Shims.TSMessageStore

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
    }
}
