//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A reference to an attachment held by a quoted message reply.
public enum TSQuotedMessageResourceReference {
    /// The quoted message had a thumbnail-able attachment, so
    /// we created a thumbnail and reference it here.
    case thumbnail(TSResourceReference)

    /// The quoted message had an attachment, but it couldn't be captured
    /// as a thumbnail (e.g. it was a generic file). We don't actually reference
    /// an attachment; instead we just keep some metadata from the original
    /// we use to render a stub at display time.
    case stub(Stub)

    public typealias Stub = QuotedMessageAttachmentReference.Stub
}
