//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Just a simple wrapper around a TSAttachment.
/// In a v2 world, some metadata lives on AttachmentReferences; this conforms legacy
/// TSAttachment to that same 2-step pattern, although really its just a 1-step fetch.
public struct TSAttachmentReference: TSResourceReference {

    private let attachment: TSAttachment

    internal init(_ attachment: TSAttachment) {
        self.attachment = attachment
    }

    public var resourceId: TSResourceId { .legacy(uniqueId: attachment.uniqueId) }

    public var sourceFilename: String? { attachment.sourceFilename }
}
