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

    public let info: Attachment.TransitTierInfo

    public var id: Attachment.IDType { attachment.id }
    public var cdnNumber: UInt32 { info.cdnNumber }
    public var cdnKey: String { info.cdnKey }
    public var uploadTimestamp: UInt64 { info.uploadTimestamp }
    public var lastDownloadAttemptTimestamp: UInt64? { info.lastDownloadAttemptTimestamp }

    private init(
        attachment: Attachment,
        info: Attachment.TransitTierInfo
    ) {
        self.attachment = attachment
        self.info = info
    }

    public convenience init?(attachment: Attachment) {
        guard
            let info = attachment.transitTierInfo
        else {
            return nil
        }
        self.init(
            attachment: attachment,
            info: info
        )
    }

    public func downloadState(tx: DBReadTransaction) -> AttachmentDownloadState {
        if attachment.asStream() != nil {
            owsFailDebug("Checking download state of stream")
            return .enqueuedOrDownloading
        }
        do {
            if
                let record = try DependenciesBridge.shared.attachmentDownloadStore.enqueuedDownload(
                    for: attachment.id,
                    tx: tx
                ),
                record.minRetryTimestamp ?? 0 <= Date().ows_millisecondsSince1970
            {
                return .enqueuedOrDownloading
            }
        } catch {
            owsFailDebug("Failed to look up download queue")
            return .none
        }
        if lastDownloadAttemptTimestamp != nil {
            return .failed
        }
        return .none
    }
}
