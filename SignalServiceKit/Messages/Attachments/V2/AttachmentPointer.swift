//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Some attachment whose full-sized contents can be downloaded from a remote CDN.
///
/// In other words, either an ``AttachmentTransitPointer`` or an ``AttachmentBackupPointer`` (or both).
public class AttachmentPointer {

    // Required to have at least one but both download sources could be present.
    public enum Source {
        case transitTier(AttachmentTransitPointer)
        case mediaTier(AttachmentBackupPointer)
    }

    public let attachment: Attachment

    public let source: Source

    public var id: Attachment.IDType { attachment.id }

    init(
        attachment: Attachment,
        source: Source,
    ) {
        self.attachment = attachment
        self.source = source
    }

    public convenience init?(attachment: Attachment) {
        // It doesn't matter which we pick first if we have both
        // transit and media tier, as we can always recover
        if let mediaTier = AttachmentBackupPointer(attachment: attachment) {
            self.init(attachment: attachment, source: .mediaTier(mediaTier))
            return
        }
        if let transitTier = AttachmentTransitPointer(attachment: attachment) {
            self.init(attachment: attachment, source: .transitTier(transitTier))
            return
        }
        return nil
    }

    // MARK: - Convenience

    public var lastDownloadAttemptTimestamp: UInt64? {
        return [
            AttachmentTransitPointer(attachment: attachment)?.lastDownloadAttemptTimestamp,
            AttachmentBackupPointer(attachment: attachment)?.lastDownloadAttemptTimestamp,
        ].compacted().max()
    }

    public var unencryptedByteCount: UInt32? {
        switch source {
        case .mediaTier(let mediaTier):
            return mediaTier.unencryptedByteCount
        case .transitTier(let transitTier):
            return transitTier.unencryptedByteCount
                ?? AttachmentBackupPointer(attachment: attachment)?.unencryptedByteCount
        }
    }

    // MARK: - Download state

    public func downloadState(tx: DBReadTransaction) -> AttachmentDownloadState {
        if attachment.asStream() != nil {
            owsFailDebug("Checking download state of stream")
            return .enqueuedOrDownloading
        }
        do {
            if
                let record = try DependenciesBridge.shared.attachmentDownloadStore.enqueuedDownload(
                    for: attachment.id,
                    tx: tx,
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
