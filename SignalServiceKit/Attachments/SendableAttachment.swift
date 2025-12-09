//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Represents an attachment that's fully valid and ready to send.
///
/// See also ``PreviewableAttachment``.
///
/// These are attachments that have been fully processed and are ready to
/// send as-is. The bytes representing these attachments meet the criteria
/// for sending via Signal.
public struct SendableAttachment {
    public let rawValue: SignalAttachment

    public init(rawValue: SignalAttachment) {
        self.rawValue = rawValue
    }

    public var mimeType: String { self.rawValue.mimeType }
    public var renderingFlag: AttachmentReference.RenderingFlag { self.rawValue.renderingFlag }
    public var sourceFilename: FilteredFilename? {
        return self.rawValue.dataSource.sourceFilename.map(FilteredFilename.init(rawValue:))
    }
}
