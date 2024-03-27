//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Represents an attachment that exists (or existed) on the transit tier,
/// and therefore can be sent.
/// May be downloaded as well, independent of its presence on the transit tier.
public class AttachmentTransitPointer {

    public let attachment: Attachment

    public let cdnNumber: UInt32
    public let cdnKey: String

    public var uploadTimestamp: UInt64? {
        attachment.transitUploadTimestamp
    }

    public var lastDownloadAttemptTimestamp: UInt64? {
        attachment.lastTransitDownloadAttemptTimestamp
    }

    private init(
        attachment: Attachment,
        transitCdnNumber: UInt32,
        transitCdnKey: String
    ) {
        self.attachment = attachment
        self.cdnNumber = transitCdnNumber
        self.cdnKey = transitCdnKey
    }

    public convenience init?(attachment: Attachment) {
        guard
            let transitCdnNumber = attachment.transitCdnNumber,
            let transitCdnKey = attachment.transitCdnKey
        else {
            return nil
        }
        self.init(
            attachment: attachment,
            transitCdnNumber: transitCdnNumber,
            transitCdnKey: transitCdnKey
        )
    }
}
