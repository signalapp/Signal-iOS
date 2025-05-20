//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Convenience container for computing metadata about a given attachment's eligibility
/// to be downloaded when sourced from a backup.
///
/// For any given attachment, it may be eligibile to download from the media tier (backup),
/// transit tier, only eligibile to download its thumbnail, or not eligible at all.
internal struct BackupAttachmentDownloadEligibility {

    let canDownloadTransitTierFullsize: Bool
    let canDownloadMediaTierFullsize: Bool
    let canDownloadThumbnail: Bool
    let downloadPriority: AttachmentDownloadPriority

    var canBeDownloadedAtAll: Bool {
        canDownloadTransitTierFullsize || canDownloadMediaTierFullsize || canDownloadThumbnail
    }

    static func forAttachment(
        _ attachment: Attachment,
        downloadRecord: QueuedBackupAttachmentDownload,
        currentTimestamp: UInt64,
        shouldOptimizeLocalStorage: Bool,
        remoteConfig: RemoteConfig,
    ) -> Self {
        return forAttachment(
            attachment,
            attachmentTimestamp: downloadRecord.timestamp,
            currentTimestamp: currentTimestamp,
            shouldOptimizeLocalStorage: shouldOptimizeLocalStorage,
            remoteConfig: remoteConfig
        )
    }

    static func forAttachment(
        _ attachment: Attachment,
        reference: @autoclosure () throws -> AttachmentReference,
        currentTimestamp: UInt64,
        shouldOptimizeLocalStorage: Bool,
        remoteConfig: RemoteConfig
    ) rethrows -> Self {
        return try forAttachment(
            attachment,
            attachmentTimestamp: try {
                switch try reference().owner {
                case .message(let messageSource):
                    return messageSource.receivedAtTimestamp
                case .thread, .storyMessage:
                    return nil
                }
            }(),
            currentTimestamp: currentTimestamp,
            shouldOptimizeLocalStorage: shouldOptimizeLocalStorage,
            remoteConfig: remoteConfig
        )
    }

    private static func forAttachment(
        _ attachment: Attachment,
        attachmentTimestamp getAttachmentTimestamp: @autoclosure () throws -> UInt64?,
        currentTimestamp: UInt64,
        shouldOptimizeLocalStorage: Bool,
        remoteConfig: RemoteConfig
    ) rethrows -> Self {
        if attachment.asStream() != nil {
            // If we have a stream already, no need to download anything.
            return Self(
                canDownloadTransitTierFullsize: false,
                canDownloadMediaTierFullsize: false,
                canDownloadThumbnail: false,
                downloadPriority: .default /* irrelevant */
            )
        }

        var cachedAttachmentTimestamp: UInt64?? = .none
        func cached(_ block: () throws -> UInt64?) rethrows -> UInt64? {
            switch cachedAttachmentTimestamp {
            case .none:
                let value = try block()
                cachedAttachmentTimestamp = value
                return value
            case .some(let value):
                return value
            }
        }

        let canDownloadMediaTierFullsize: Bool
        if
            FeatureFlags.Backups.remoteExportAlpha,
            // Note: we dont check uploadEra because thats only used to tell if we need to
            // reupload. We should attempt downloads as long as we have media tier info at
            // all, because even if the era changed the upload may not have expired.
            attachment.mediaTierInfo != nil
        {
            let canBeOffloaded: Bool
            if
                shouldOptimizeLocalStorage,
                let attachmentTimestamp = try cached(getAttachmentTimestamp)
            {
                canBeOffloaded = attachmentTimestamp + Attachment.offloadingThresholdMs > currentTimestamp
            } else {
                canBeOffloaded = false
            }
            canDownloadMediaTierFullsize = !canBeOffloaded
        } else {
            canDownloadMediaTierFullsize = false
        }

        let canDownloadTransitTierFullsize: Bool
        if let transitTierInfo = attachment.transitTierInfo {
            // Download if the upload was < 45 days old,
            // otherwise don't bother trying automatically.
            // (The user could still try a manual download later).
            // First try the upload timestamp, if that doesn't pass the check
            // try the received timestamp.
            if transitTierInfo.uploadTimestamp + remoteConfig.messageQueueTimeMs > currentTimestamp {
                canDownloadTransitTierFullsize = true
            } else if try cached(getAttachmentTimestamp) ?? 0 + remoteConfig.messageQueueTimeMs > currentTimestamp {
                canDownloadTransitTierFullsize = true
            } else {
                canDownloadTransitTierFullsize = false
            }
        } else {
            canDownloadTransitTierFullsize = false
        }

        let canDownloadThumbnail =
            FeatureFlags.Backups.fileAlpha
            && AttachmentBackupThumbnail.canBeThumbnailed(attachment)
            && attachment.thumbnailMediaTierInfo != nil

        guard
            canDownloadMediaTierFullsize
            || canDownloadTransitTierFullsize
            || canDownloadThumbnail
        else {
            // If we can't download anything, don't bother computing priority.
            return Self(
                canDownloadTransitTierFullsize: false,
                canDownloadMediaTierFullsize: false,
                canDownloadThumbnail: false,
                downloadPriority: .default /* irrelevant */
            )
        }

        let isRecent: Bool
        if let attachmentTimestamp = try cached(getAttachmentTimestamp) {
            // We're "recent" if our newest owning message wouldn't have expired off the queue.
            isRecent = currentTimestamp - attachmentTimestamp <= remoteConfig.messageQueueTimeMs
        } else {
            // If we don't have a timestamp, its a wallpaper and we should always pass
            // the recency check.
            isRecent = true
        }

        let downloadPriority: AttachmentDownloadPriority =
            isRecent ? .backupRestoreHigh : .backupRestoreLow

        return Self(
            canDownloadTransitTierFullsize: canDownloadTransitTierFullsize,
            canDownloadMediaTierFullsize: canDownloadMediaTierFullsize,
            canDownloadThumbnail: canDownloadThumbnail,
            downloadPriority: downloadPriority
        )
    }
}
