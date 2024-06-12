//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A DataSource for an attachment to be created locally, with
/// additional required metadata.
public struct QuotedReplyTSResourceDataSource {

    /// The row id of the original message being quoted, if found locally.
    public let originalMessageRowId: Int64?
    public let source: Source

    public enum Source {
        /// A TSAttachment on the original message to use as the source
        /// for the thumbnail of the new attachment.
        case originalLegacyAttachment(uniqueId: String)

        /// A v2 source that can _only_ be used to create v2 quoted replies.
        /// Note that v1->v2 is one-way. Given a v1 attachment we can _try_
        /// and quote it as a v2 attachment, but cannot quote a v2 as a v1.
        /// This is because once we start creating v2 attachments, we should
        /// stop creating v1 attachments; the backwards path is unsupported.
        case v2Source(QuotedReplyAttachmentDataSource.Source)
    }

    fileprivate init(originalMessageRowId: Int64?, source: Source) {
        self.originalMessageRowId = originalMessageRowId
        self.source = source
    }

    public static func fromLegacyOriginalAttachment(
        _ originalAttachment: TSAttachment,
        originalMessageRowId: Int64
    ) -> Self {
        return .init(
            originalMessageRowId: originalMessageRowId,
            source: .originalLegacyAttachment(uniqueId: originalAttachment.uniqueId)
        )
    }
}

extension QuotedReplyAttachmentDataSource {

    public var tsDataSource: QuotedReplyTSResourceDataSource {
        return .init(originalMessageRowId: originalMessageRowId, source: .v2Source(source))
    }
}
