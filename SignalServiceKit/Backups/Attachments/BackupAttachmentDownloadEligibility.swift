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
        attachmentTimestamp: UInt64?,
        dateProvider: DateProvider,
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        remoteConfigProvider: RemoteConfigProvider,
        tx: DBReadTransaction
    ) -> Self {
        return forAttachment(
            attachment,
            attachmentTimestamp: attachmentTimestamp,
            now: dateProvider(),
            shouldStoreAllMediaLocally: backupAttachmentDownloadStore.getShouldStoreAllMediaLocally(tx: tx),
            remoteConfig: remoteConfigProvider.currentConfig()
        )
    }

    static func forAttachment(
        _ attachment: Attachment,
        attachmentTimestamp: UInt64?,
        now: Date,
        shouldStoreAllMediaLocally: Bool,
        remoteConfig: RemoteConfig
    ) -> Self {
        if attachment.asStream() != nil {
            // If we have a stream already, no need to download anything.
            return Self(
                canDownloadTransitTierFullsize: false,
                canDownloadMediaTierFullsize: false,
                canDownloadThumbnail: false,
                downloadPriority: .default /* irrelevant */
            )
        }

        let isRecent: Bool
        if let attachmentTimestamp {
            // We're "recent" if our newest owning message wouldn't have expired off the queue.
            isRecent = now.ows_millisecondsSince1970 - attachmentTimestamp <= remoteConfig.messageQueueTimeMs
        } else {
            // If we don't have a timestamp, its a wallpaper and we should always pass
            // the recency check.
            isRecent = true
        }

        let canDownloadMediaTierFullsize =
            FeatureFlags.Backups.fileAlpha
            && attachment.mediaTierInfo != nil
            && (isRecent || shouldStoreAllMediaLocally)

        let canDownloadTransitTierFullsize: Bool
        if let transitTierInfo = attachment.transitTierInfo {
            let timestampForComparison = max(transitTierInfo.uploadTimestamp, attachmentTimestamp ?? 0)
            // Download if the upload was < 45 days old,
            // otherwise don't bother trying automatically.
            // (The user could still try a manual download later).
            canDownloadTransitTierFullsize = Date(millisecondsSince1970: timestampForComparison).addingTimeInterval(45 * .day) > now
        } else {
            canDownloadTransitTierFullsize = false
        }

        let canDownloadThumbnail =
            FeatureFlags.Backups.fileAlpha
            && AttachmentBackupThumbnail.canBeThumbnailed(attachment)
            && attachment.thumbnailMediaTierInfo != nil

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
