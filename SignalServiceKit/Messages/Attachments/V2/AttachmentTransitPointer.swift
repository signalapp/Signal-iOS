//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Represents an attachment that exists (or existed) on the transit tier,
/// and therefore can be sent.
/// May be downloaded as well, independent of its presence on the transit tier.
final public class AttachmentTransitPointer {

    public let attachment: Attachment

    public let info: Attachment.TransitTierInfo

    public var id: Attachment.IDType { attachment.id }
    public var cdnNumber: UInt32 { info.cdnNumber }
    public var cdnKey: String { info.cdnKey }
    public var uploadTimestamp: UInt64 { info.uploadTimestamp }
    public var lastDownloadAttemptTimestamp: UInt64? { info.lastDownloadAttemptTimestamp }
    public var unencryptedByteCount: UInt32? { info.unencryptedByteCount }

    private init(
        attachment: Attachment,
        info: Attachment.TransitTierInfo
    ) {
        self.attachment = attachment
        self.info = info
    }

    public convenience init?(attachment: Attachment) {
        guard
            // Note: we only use the latest transit tier info
            // for pointers to download.
            let info = attachment.latestTransitTierInfo
        else {
            return nil
        }
        self.init(
            attachment: attachment,
            info: info
        )
    }

    var asAnyPointer: AttachmentPointer {
        return AttachmentPointer(
            attachment: attachment,
            source: .transitTier(self)
        )
    }
}
