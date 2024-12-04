//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension MessageEdits {

    public enum OversizeTextSource {
        case dataSource(AttachmentDataSource)
        case proto(SSKProtoAttachmentPointer)
    }

    public enum LinkPreviewSource {
        case draft(LinkPreviewDataSource)
        case proto(SSKProtoPreview, SSKProtoDataMessage)
    }
}

public protocol EditManagerAttachments {

    /// Given...
    /// 1. an edit target (the state of the edited message prior to the current round of edits)
    /// 2. the latest revision
    ///   * assumed to have the same row id as the edit target
    ///   * assumed to have empty fields for attachment-releated objects, e.g. ``TSMessage.quotedReply``.
    /// 3. the prior revision
    ///   * assumed to be a copy with a new row id
    ///   * assumed to have empty fields for attachment-releated objects, e.g. ``TSMessage.quotedReply``.
    /// 4. the attachment-related new values to apply
    ///
    /// ...applies the changes appropriately to both the prior and latest revision.
    func reconcileAttachments<EditTarget: EditMessageWrapper>(
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
    ) throws
}
