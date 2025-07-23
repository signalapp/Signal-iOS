//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Convenience container for computing metadata about a given attachment's eligibility
/// to be downloaded when sourced from a backup.
///
/// For any given attachment, it may be eligibile to download from the media tier (backup),
/// transit tier, only eligibile to download its thumbnail, or not eligible at all.
public struct BackupAttachmentDownloadEligibility {

    /// nil = isn't on transit tier at all, can't be downloaded.
    let thumbnailMediaTierState: QueuedBackupAttachmentDownload.State?

    /// nil = isn't on transit tier at all, can't be downloaded.
    let fullsizeTransitTierState: QueuedBackupAttachmentDownload.State?

    /// nil = isn't on media tier at all, can't be downloaded.
    let fullsizeMediaTierState: QueuedBackupAttachmentDownload.State?

    var fullsizeState: QueuedBackupAttachmentDownload.State? {
        switch (fullsizeMediaTierState, fullsizeTransitTierState) {
        case (_, .done), (.done, _):
            // "Done" means downloaded, so either does it.
            return .done
        case (_, .ready), (.ready, _):
            // If either is ready, the whole thing is ready.
            return .ready
        case (.ineligible, nil), (nil, .ineligible), (.ineligible, .ineligible):
            // If only one is available and is ineligible, or both are ineligible,
            // then the whole thing is ineligible.
            return .ineligible
        case (nil, nil):
            // If neither is available, we can't download.
            return nil
        }
    }

    var canDownloadMediaTierFullsize: Bool {
        switch fullsizeMediaTierState {
        case .ineligible, .ready:
            return true
        case .done:
            return false
        case nil:
            return false
        }
    }

    static func forAttachment(
        _ attachment: Attachment,
        downloadRecord: QueuedBackupAttachmentDownload,
        currentTimestamp: UInt64,
        backupPlan: BackupPlan,
        remoteConfig: RemoteConfig,
        isPrimaryDevice: Bool
    ) -> Self {
        return forAttachment(
            attachment,
            attachmentTimestamp: downloadRecord.maxOwnerTimestamp,
            currentTimestamp: currentTimestamp,
            backupPlan: backupPlan,
            remoteConfig: remoteConfig,
            isPrimaryDevice: isPrimaryDevice
        )
    }

    static func forAttachment(
        _ attachment: Attachment,
        reference: @autoclosure () throws -> AttachmentReference,
        currentTimestamp: UInt64,
        backupPlan: BackupPlan,
        remoteConfig: RemoteConfig,
        isPrimaryDevice: Bool
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
            backupPlan: backupPlan,
            remoteConfig: remoteConfig,
            isPrimaryDevice: isPrimaryDevice
        )
    }

    private static func forAttachment(
        _ attachment: Attachment,
        attachmentTimestamp getAttachmentTimestamp: @autoclosure () throws -> UInt64?,
        currentTimestamp: UInt64,
        backupPlan: BackupPlan,
        remoteConfig: RemoteConfig,
        isPrimaryDevice: Bool
    ) rethrows -> Self {
        if attachment.asStream() != nil {
            // If we have a stream already, no need to download anything.
            return Self(
                thumbnailMediaTierState: .done,
                fullsizeTransitTierState: .done,
                fullsizeMediaTierState: .done
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

        return Self(
            thumbnailMediaTierState: Self.mediaTierThumbnailState(
                attachment: attachment,
                backupPlan: backupPlan
            ),
            fullsizeTransitTierState: try Self.transitTierFullsizeState(
                attachment: attachment,
                attachmentTimestamp: { try cached(getAttachmentTimestamp) }(),
                currentTimestamp: currentTimestamp,
                remoteConfig: remoteConfig,
                backupPlan: backupPlan,
                isPrimaryDevice: isPrimaryDevice
            ),
            fullsizeMediaTierState: try Self.mediaTierFullsizeState(
                attachment: attachment,
                attachmentTimestamp: { try cached(getAttachmentTimestamp) }(),
                currentTimestamp: currentTimestamp,
                backupPlan: backupPlan
            )
        )
    }

    /// Returns nil if cannot be downloaded at all.
    /// (As opposed to ineligible, which just means the current backup plan prevents download).
    static func mediaTierFullsizeState(
        attachment: Attachment,
        attachmentTimestamp getAttachmentTimestamp: @autoclosure () throws -> UInt64?,
        currentTimestamp: UInt64,
        backupPlan: BackupPlan
    ) rethrows -> QueuedBackupAttachmentDownload.State? {
        guard FeatureFlags.Backups.supported else {
            return nil
        }
        guard attachment.asStream() == nil else {
            return .done
        }
        guard
            attachment.mediaName != nil,
            // Note: we dont check uploadEra because thats only used to tell if we need to
            // reupload. We should attempt downloads as long as we have media tier info at
            // all, because even if the era changed the upload may not have expired.
            attachment.mediaTierInfo != nil
        else {
            return nil
        }
        switch backupPlan {
        case .disabled:
            // Never do media tier downloads when disabled.
            return .ineligible
        case .disabling:
            // Everything is eligible for download if we're currently trying to
            // disable.
            return .ready
        case .free:
            // While free, we consider all attachments for which we have some media tier info
            // as eligible for downloading. Elsewhere we may choose not to _enqueue_ the download,
            // but for eligibility purposes "free" is the same as paid with optimize off.
            return .ready
        case
                .paid(optimizeLocalStorage: false),
                .paidExpiringSoon(optimizeLocalStorage: false),
                .paidAsTester(optimizeLocalStorage: false):
            // Everything is eligible for download when optimize is off.
            return .ready

        case
                .paid(optimizeLocalStorage: true),
                .paidExpiringSoon(optimizeLocalStorage: true),
                .paidAsTester(optimizeLocalStorage: true):
            guard let attachmentTimestamp = try getAttachmentTimestamp() else {
                // Nil timestamps are used for thread wallpapers, which we never offload.
                return .ready
            }
            // Note that we don't use `Attachment.shouldBeOffloaded` because this check is subtly different.
            // shouldBeOffloaded is concerned with whether to offload a stream we already downloaded so it
            // returns false for non-streams and it checks last viewed time.
            // This is by definition a pointer, not a stream, and therefore can't be viewed. The only
            // criteria we care about is the age of the attachment.
            let wouldBeOffloaded = attachmentTimestamp + Attachment.offloadingThresholdMs < currentTimestamp
            if wouldBeOffloaded {
                return .ineligible
            } else {
                return .ready
            }
        }
    }

    /// Returns nil if cannot be downloaded at all.
    /// (As opposed to ineligible, which just means the current backup plan prevents download).
    static func mediaTierThumbnailState(
        attachment: Attachment,
        backupPlan: BackupPlan,
    ) -> QueuedBackupAttachmentDownload.State? {
        guard FeatureFlags.Backups.supported else {
            return nil
        }
        switch backupPlan {
        case .disabled:
            return .ineligible
        case .disabling, .free, .paid, .paidExpiringSoon, .paidAsTester:
            if attachment.mediaName == nil {
                return nil
            }
            guard
                // If we have the fullsize stream, we don't need the thumbnail at all.
                attachment.asStream() == nil,
                // Also check if we already have the thumbnail.
                attachment.localRelativeFilePathThumbnail == nil
            else {
                return .done
            }
            if
                AttachmentBackupThumbnail.canBeThumbnailed(attachment)
                || attachment.thumbnailMediaTierInfo != nil
            {
                return .ready
            } else {
                return nil
            }
        }
    }

    /// Returns nil if cannot be downloaded at all.
    /// (As opposed to ineligible, which just means the current backup plan prevents download).
    static func transitTierFullsizeState(
        attachment: Attachment,
        attachmentTimestamp getAttachmentTimestamp: @autoclosure () throws -> UInt64?,
        currentTimestamp: UInt64,
        remoteConfig: RemoteConfig,
        backupPlan: BackupPlan,
        isPrimaryDevice: Bool
    ) rethrows -> QueuedBackupAttachmentDownload.State? {
        guard attachment.asStream() == nil else {
            return .done
        }
        guard let transitTierInfo = attachment.transitTierInfo else {
            return nil
        }

        switch backupPlan {
        case .disabled:
            // Linked device can link'n'sync is backups are disabled
            // and should still restore from transit tier if so.
            if isPrimaryDevice {
                return .ineligible
            } else {
                fallthrough
            }
        case .disabling, .free, .paid, .paidExpiringSoon, .paidAsTester:
            if Self.disableTransitTierDownloadsOverride {
                return nil
            }

            // Download if the upload was < 45 days old,
            // otherwise don't bother trying automatically.
            // (The user could still try a manual download later).
            // First try the upload timestamp, if that doesn't pass the check
            // try the received timestamp.
            if transitTierInfo.uploadTimestamp + remoteConfig.messageQueueTimeMs > currentTimestamp {
                return .ready
            } else if try getAttachmentTimestamp() ?? 0 + remoteConfig.messageQueueTimeMs > currentTimestamp {
                return .ready
            } else {
                return nil
            }
        }
    }

    public static var disableTransitTierDownloadsOverride: Bool {
        get { DebugFlags.internalSettings && UserDefaults.standard.bool(forKey: "disableTransitTierDownloadsOverride") }
        set {
            guard DebugFlags.internalSettings else { return }
            UserDefaults.standard.set(newValue, forKey: "disableTransitTierDownloadsOverride")
        }
    }
}
