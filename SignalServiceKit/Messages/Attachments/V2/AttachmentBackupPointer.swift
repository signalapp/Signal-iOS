//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Represents an attachment that exists (or existed) on the media tier.
/// May be downloaded as well, independent of its presence on the transit tier.
public class AttachmentBackupPointer {

    public let attachment: Attachment

    public let info: Attachment.MediaTierInfo

    public var id: Attachment.IDType { attachment.id }
    /// Nil if we have not yet learned the cdn number; the client that exported
    /// the backup had not yet uploaded at backup time.
    public var cdnNumber: UInt32? { info.cdnNumber }
    public var uploadEra: String { info.uploadEra }
    public var lastDownloadAttemptTimestamp: UInt64? { info.lastDownloadAttemptTimestamp }
    public var unencryptedByteCount: UInt32 { info.unencryptedByteCount }

    private init(
        attachment: Attachment,
        info: Attachment.MediaTierInfo,
    ) {
        self.attachment = attachment
        self.info = info
    }

    public convenience init?(attachment: Attachment) {
        guard
            let info = attachment.mediaTierInfo
        else {
            return nil
        }
        self.init(
            attachment: attachment,
            info: info,
        )
    }

    var asAnyPointer: AttachmentPointer {
        return AttachmentPointer(
            attachment: attachment,
            source: .mediaTier(self),
        )
    }
}
