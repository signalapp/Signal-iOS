//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation

/// Represents an attachment; a file on local disk and/or a pointer to a file on a CDN.
public class Attachment {

    public typealias IDType = Int64

    /// SQLite row id.
    public let id: IDType

    /// Nil for:
    /// * non-visual-media attachments
    /// * undownloaded attachments where the sender didn't include the value.
    /// Otherwise this contains the value from the sender for undownloaded attachments,
    /// and our locally computed blurhash value for downloading attachments.
    public let blurHash: String?

    /// MIME type we get from the attachment's sender, known even before downloading the attachment.
    /// **If undownloaded, unverified (spoofable by the sender) and may not match the type of the actual bytes.**
    /// If downloaded, check ``AttachmentStream/contentType`` for a validated representation of the type..
    public let mimeType: String

    /// Encryption key used for the local file AND media tier.
    /// If from an incoming message, we get this from the proto, and can reuse it for local and media backup encryption.
    /// If outgoing, we generate the key ourselves when we create the attachment.
    public let encryptionKey: Data

    public let streamInfo: StreamInfo?

    /// Information for the latest transit tier upload, if known to be uploaded.
    /// The encryption key may not match the tip-level encryption key used for the local file;
    /// they may differ if the attachment was reuploaded for forwarding.
    public let latestTransitTierInfo: TransitTierInfo?

    /// Information for a transit tier upload using the local encryption key, if known to be uploaded.
    /// Always uses the local encryption key; will be nil if no upload at the same encryption key is known.
    public let originalTransitTierInfo: TransitTierInfo?

    /// Used for quoted reply thumbnail attachments.
    /// The id of the quoted reply's target message's attachment that is to be thumbnail'ed.
    /// Only relevant for non-streams. At "download" time instead of using the transit tier info
    /// as the source we use the original attachment's file. Once this attachment is a stream,
    /// this field should be set to nil (but should just be ignored regardless).
    public let originalAttachmentIdForQuotedReply: Attachment.IDType?

    /// Validated Sha256 hash of the plaintext of the media content. Used to deduplicate incoming media.
    /// Nonnull if downloaded OR possibly if restored from a backup (which we trust to have validated).
    public let sha256ContentHash: Data?

    /// MediaName used for backups (but assigned even if backups disabled).
    /// Nonnull if downloaded OR if restored from a backup.
    public let mediaName: String?

    /// If null, the resource has not been uploaded to the media tier.
    public let mediaTierInfo: MediaTierInfo?

    /// Not to be confused with thumbnails used for rendering, or those created for quoted message replies.
    /// This thumbnail is exclusively used for backup purposes.
    /// If null, the thumbnail resource has not been uploaded to the media tier.
    public let thumbnailMediaTierInfo: ThumbnailMediaTierInfo?

    /// Filepath to the encrypted thumbnail file on local disk.
    /// Not to be confused with thumbnails used for rendering, or those created for quoted message replies.
    /// This thumbnail is exclusively used for backup purposes.
    public let localRelativeFilePathThumbnail: String?

    /// The last time the user viewed this attachment ("fullscreen", which really means "not just scrolling past it
    /// in a conversation"). Set if viewing in the media gallery, story viewer, etc.
    /// Not set when viewing a thread wallpaper.
    /// May not be set for e.g. attachments that were viewed before we started tracking this; do not use
    /// this for anything that would rely on this being historically correct.
    public let lastFullscreenViewTimestamp: UInt64?

    // MARK: - Inner structs

    /// Information supporting "streaming" video, which requires computing an
    /// "incremental" MAC rather than one big HMAC verification on the
    /// fully-downloaded file.
    public struct IncrementalMacInfo: Equatable {
        public let mac: Data
        public let chunkSize: UInt32

        // NOTE: Incremental mac is unsupported on iOS, the columns are
        // vestigial. When we add video streaming support, we can make
        // this init public and start setting it, but we must also
        // validate the incremental mac on every download (streamed or not)
        // and reject the download if it is invalid, thus ensuring the
        // invariant that the incremental mac is valid if set
        // for all downloaded attachments, same as the digest.
        private init(mac: Data, chunkSize: UInt32) {
            self.mac = mac
            self.chunkSize = chunkSize
        }
    }

    /// Information for the "stream" (the attachment downloaded and locally available).
    public struct StreamInfo {
        /// Sha256 hash of the plaintext of the media content. Used to deduplicate incoming media.
        public let sha256ContentHash: Data

        /// MediaName used for backups (but assigned even if backups disabled).
        public let mediaName: String

        /// Byte count of the encrypted fullsize resource
        public let encryptedByteCount: UInt32
        ///  Byte count of the decrypted fullsize resource
        public let unencryptedByteCount: UInt32

        /// For downloaded attachments, the validated type of content in the actual file.
        public let contentType: ContentType

        /// File digest info.
        ///
        /// SHA256Hash(iv + cyphertext + hmac),
        /// (iv + cyphertext + hmac) is the thing we actually upload to the CDN server, which uses
        /// the ``encryptionKey`` field.
        ///
        /// Generated locally for outgoing attachments.
        /// Validated for downloaded attachments.
        public let digestSHA256Ciphertext: Data

        /// Filepath to the encrypted fullsize media file on local disk.
        public let localRelativeFilePath: String
    }

    public struct TransitTierInfo: Equatable {
        /// CDN number for the upload in the transit tier (or nil if not uploaded).
        public let cdnNumber: UInt32

        /// CDN key for the upload in the transit tier (or nil if not uploaded).
        public let cdnKey: String

        /// If outgoing: Local time the attachment was uploaded to the transit tier, or nil if not uploaded.
        /// If incoming: timestamp on the message the attachment came in on.
        /// Used to determine whether reuploading is necessary for e.g. forwarding.
        public let uploadTimestamp: UInt64

        /// Encryption key used on this transit tier upload.
        /// May be the same as the local stream encryption key, or may have been rotated for sending.
        public let encryptionKey: Data

        /// Expected byte count after decrypting the resource off the transit tier (and removing padding).
        /// Provided by the sender of incoming attachments.
        public let unencryptedByteCount: UInt32?

        /// Generated locally for outgoing attachments.
        /// For incoming attachments, taken off the service proto. If validation fails, the download is rejected.
        public let integrityCheck: AttachmentIntegrityCheck

        /// Incremental mac info used for streaming, if available. Only set for streamable types.
        public let incrementalMacInfo: IncrementalMacInfo?

        /// Timestamp we last tried (and failed) to download from the transit tier.
        /// Nil if we have not tried or have successfully downloaded.
        public let lastDownloadAttemptTimestamp: UInt64?
    }

    public struct MediaTierInfo {
        /// CDN number for the fullsize upload in the media tier.
        /// If nil, that means there _might_ be an upload from a prior device that happened after
        /// that device generated the backup this was restored from. The cdn number (and presence
        /// of the upload) can be discovered via the list endpoint.
        public let cdnNumber: UInt32?

        /// Expected byte count after decrypting the resource off the media tier (and removing padding).
        /// Provided by the sender of incoming attachments.
        public let unencryptedByteCount: UInt32

        /// Sha256 hash of the plaintext of the media content.
        ///
        /// Equivalent to `StreamInfo.sha256ContentHash`, but may be available
        /// if the rest of `StreamInfo` is unavailable (e.g. after a restore).
        public let sha256ContentHash: Data

        /// Incremental mac info used for streaming, if available. Only set for streamable mime types.
        public let incrementalMacInfo: IncrementalMacInfo?

        /// If the value in this column doesn’t match the current Backup Subscription Era,
        /// it should also be considered un-uploaded.
        /// Set to the current era when uploaded.
        public let uploadEra: String

        /// Timestamp we last tried (and failed) to download from the media tier.
        /// Nil if we have not tried or have successfully downloaded.
        public let lastDownloadAttemptTimestamp: UInt64?
    }

    public struct ThumbnailMediaTierInfo {
        /// CDN number for the thumbnail upload in the media tier.
        /// If nil, that means there _might_ be an upload from a prior device that happened after
        /// that device generated the backup this was restored from. The cdn number (and presence
        /// of the upload) can be discovered via the list endpoint.
        public let cdnNumber: UInt32?

        /// If the value in this column doesn’t match the current Backup Subscription Era,
        /// it should also be considered un-uploaded.
        /// Set to the current era when uploaded.
        public let uploadEra: String

        /// Timestamp we last tried (and failed) to download the thumbnail from the media tier.
        /// Nil if we have not tried or have successfully downloaded.
        public let lastDownloadAttemptTimestamp: UInt64?
    }

    // MARK: - Init

    init(record: Attachment.Record) throws {
        guard let id = record.sqliteId else {
            throw OWSAssertionError("Attachment is only for inserted records")
        }

        let contentType = try ContentType(
            raw: record.contentType,
            cachedAudioDurationSeconds: record.cachedAudioDurationSeconds,
            cachedMediaHeightPixels: record.cachedMediaHeightPixels,
            cachedMediaWidthPixels: record.cachedMediaWidthPixels,
            cachedVideoDurationSeconds: record.cachedVideoDurationSeconds,
            audioWaveformRelativeFilePath: record.audioWaveformRelativeFilePath,
            videoStillFrameRelativeFilePath: record.videoStillFrameRelativeFilePath,
        )

        self.id = id
        self.blurHash = record.blurHash
        self.mimeType = record.mimeType
        self.encryptionKey = record.encryptionKey
        self.originalAttachmentIdForQuotedReply = record.originalAttachmentIdForQuotedReply
        self.sha256ContentHash = record.sha256ContentHash
        self.mediaName = record.mediaName
        self.localRelativeFilePathThumbnail = record.localRelativeFilePathThumbnail
        self.lastFullscreenViewTimestamp = record.lastFullscreenViewTimestamp

        self.streamInfo = StreamInfo(
            sha256ContentHash: record.sha256ContentHash,
            mediaName: record.mediaName,
            encryptedByteCount: record.encryptedByteCount,
            unencryptedByteCount: record.unencryptedByteCount,
            contentType: contentType,
            digestSHA256Ciphertext: record.digestSHA256Ciphertext,
            localRelativeFilePath: record.localRelativeFilePath,
        )
        let latestTransitTierInfo = TransitTierInfo(
            cdnNumber: record.latestTransitCdnNumber,
            cdnKey: record.latestTransitCdnKey,
            uploadTimestamp: record.latestTransitUploadTimestamp,
            encryptionKey: record.latestTransitEncryptionKey,
            unencryptedByteCount: record.latestTransitUnencryptedByteCount,
            digestSHA256Ciphertext: record.latestTransitDigestSHA256Ciphertext,
            sha256ContentHash: record.sha256ContentHash,
            lastDownloadAttemptTimestamp: record.latestTransitLastDownloadAttemptTimestamp,
            incrementalMac: record.latestTransitTierIncrementalMac,
            incrementalMacChunkSize: record.latestTransitTierIncrementalMacChunkSize,
        )
        self.latestTransitTierInfo = latestTransitTierInfo

        // At read time, we populate "original" transit tier info with _any_ transit
        // tier info we have in the database row that matches the encryption key.
        if
            // If we have a latest transit info on disk
            let latestTransitTierInfo,
            // It uses the primary encryption key
            latestTransitTierInfo.encryptionKey == encryptionKey,
            // And represents the same file (same iv -> same digest,
            // or we have no local digest which means we will use the
            // transit download as the file when its done, or we have
            // only plaintext integrity check which means it always matches.)

            record.latestTransitDigestSHA256Ciphertext == record.digestSHA256Ciphertext
            || record.digestSHA256Ciphertext == nil
            || record.latestTransitDigestSHA256Ciphertext == nil

        {
            self.originalTransitTierInfo = latestTransitTierInfo
        } else {
            self.originalTransitTierInfo = TransitTierInfo(
                cdnNumber: record.originalTransitCdnNumber,
                cdnKey: record.originalTransitCdnKey,
                uploadTimestamp: record.originalTransitUploadTimestamp,
                encryptionKey: record.encryptionKey,
                unencryptedByteCount: record.originalTransitUnencryptedByteCount,
                digestSHA256Ciphertext: record.originalTransitDigestSHA256Ciphertext,
                sha256ContentHash: record.sha256ContentHash,
                lastDownloadAttemptTimestamp: nil,
                incrementalMac: record.originalTransitTierIncrementalMac,
                incrementalMacChunkSize: record.originalTransitTierIncrementalMacChunkSize,
            )
        }
        self.mediaTierInfo = MediaTierInfo(
            cdnNumber: record.mediaTierCdnNumber,
            unencryptedByteCount: record.mediaTierUnencryptedByteCount ?? record.unencryptedByteCount,
            sha256ContentHash: record.sha256ContentHash,
            uploadEra: record.mediaTierUploadEra,
            lastDownloadAttemptTimestamp: record.lastMediaTierDownloadAttemptTimestamp,
            incrementalMac: record.mediaTierIncrementalMac,
            incrementalMacChunkSize: record.mediaTierIncrementalMacChunkSize,
        )
        self.thumbnailMediaTierInfo = ThumbnailMediaTierInfo(
            cdnNumber: record.thumbnailCdnNumber,
            uploadEra: record.thumbnailUploadEra,
            lastDownloadAttemptTimestamp: record.lastThumbnailDownloadAttemptTimestamp,
        )
    }

    public var isUploadedToTransitTier: Bool {
        return latestTransitTierInfo != nil
    }

    public var hasMediaTierInfo: Bool {
        return mediaTierInfo != nil
    }

    public func asStream() -> AttachmentStream? {
        return AttachmentStream(attachment: self)
    }

    public func asTransitTierPointer() -> AttachmentTransitPointer? {
        return AttachmentTransitPointer(attachment: self)
    }

    public func asBackupTierPointer() -> AttachmentBackupPointer? {
        return AttachmentBackupPointer(attachment: self)
    }

    public func asAnyPointer() -> AttachmentPointer? {
        return AttachmentPointer(attachment: self)
    }

    public func asBackupThumbnail() -> AttachmentBackupThumbnail? {
        return AttachmentBackupThumbnail(attachment: self)
    }

    public static func mediaName(sha256ContentHash: Data, encryptionKey: Data) -> String {
        // We use the hexadecimal-encoded [plaintext hash | encryptionKey] as the media name.
        // This ensures media name collisions occur only between the
        // same attachment contents encrypted with the same key.
        var mediaName = Data()
        mediaName.append(sha256ContentHash)
        mediaName.append(encryptionKey)
        return mediaName.hexadecimalString
    }

    /// Unencrypted byte count on CDN of the fullsize attachment _before_ encryption and padding,
    /// as obtained either from the sender or ourselves.
    /// Media and transit tier byte counts should be interchangeable.
    /// Still, we shouldn't rely on this for anything critical; assume the value can be spoofed.
    /// Safe to use for size estimation, UI progress display, etc.
    public var anyPointerFullsizeUnencryptedByteCount: UInt32? {
        return mediaTierInfo?.unencryptedByteCount ?? latestTransitTierInfo?.unencryptedByteCount
    }

    public enum TransitUploadStrategy {
        case reuseExistingUpload(Upload.ReusedUploadMetadata)
        case reuseStreamEncryption(Upload.LocalUploadMetadata)
        case freshUpload(AttachmentStream)
        case cannotUpload
    }

    public func transitUploadStrategy(dateProvider: DateProvider) -> TransitUploadStrategy {
        // We never allow uploads of data we don't have locally.
        guard let stream = self.asStream() else {
            return .cannotUpload
        }

        let metadata = Upload.LocalUploadMetadata(
            fileUrl: stream.fileURL,
            key: encryptionKey,
            digest: stream.info.digestSHA256Ciphertext,
            encryptedDataLength: stream.info.encryptedByteCount,
            plaintextDataLength: stream.info.unencryptedByteCount,
        )

        if
            // We have a prior upload
            let latestTransitTierInfo,
            // That upload includes a digest (if we restore from a backup
            // with no digest, we can't forward that transit tier info
            // even though we know about it and its maybe recent).
            case .digestSHA256Ciphertext(let digest) = latestTransitTierInfo.integrityCheck,
            // And we are still in the window to reuse it
            dateProvider().timeIntervalSince(
                Date(millisecondsSince1970: latestTransitTierInfo.uploadTimestamp),
            ) <= Upload.Constants.uploadReuseWindow
        {
            // We have unexpired transit tier info. Reuse that upload.
            return .reuseExistingUpload(
                .init(
                    cdnKey: latestTransitTierInfo.cdnKey,
                    cdnNumber: latestTransitTierInfo.cdnNumber,
                    key: latestTransitTierInfo.encryptionKey,
                    digest: digest,
                    // Okay to fall back to our local data length even if the original sender
                    // didn't include it; we now know it from the local file.
                    plaintextDataLength: latestTransitTierInfo.unencryptedByteCount ?? metadata.plaintextDataLength,
                    // Encryped length is the same regardless of the key used.
                    encryptedDataLength: metadata.encryptedDataLength,
                ),
            )
        } else if
            // This device has never uploaded
            latestTransitTierInfo == nil,
            // No media tier info either
            mediaTierInfo == nil
        {
            // Reuse our local encryption for sending.
            // Without this, we'd have to reupload all our outgoing attacments
            // in order to copy them to the media tier.
            return .reuseStreamEncryption(metadata)
        } else {
            // Upload from scratch
            return .freshUpload(stream)
        }
    }
}

// MARK: -

private extension Attachment.StreamInfo {
    init?(
        sha256ContentHash: Data?,
        mediaName: String?,
        encryptedByteCount: UInt32?,
        unencryptedByteCount: UInt32?,
        contentType: Attachment.ContentType?,
        digestSHA256Ciphertext: Data?,
        localRelativeFilePath: String?,
    ) {
        guard
            let sha256ContentHash,
            let mediaName,
            let encryptedByteCount,
            let unencryptedByteCount,
            let contentType,
            let digestSHA256Ciphertext,
            let localRelativeFilePath
        else {
            // sha256ContentHash and mediaName might still be set
            // if we don't have a stream. The other columns must either
            // all be set or none set.
            owsAssertDebug(
                encryptedByteCount == nil
                    && unencryptedByteCount == nil
                    && contentType == nil
                    && localRelativeFilePath == nil,
                "Have partial stream info!",
            )
            return nil
        }
        self.sha256ContentHash = sha256ContentHash
        self.mediaName = mediaName
        self.encryptedByteCount = encryptedByteCount
        self.unencryptedByteCount = unencryptedByteCount
        self.contentType = contentType
        self.digestSHA256Ciphertext = digestSHA256Ciphertext
        self.localRelativeFilePath = localRelativeFilePath
    }
}

private extension Attachment.TransitTierInfo {
    init?(
        cdnNumber: UInt32?,
        cdnKey: String?,
        uploadTimestamp: UInt64?,
        encryptionKey: Data?,
        unencryptedByteCount: UInt32?,
        digestSHA256Ciphertext: Data?,
        sha256ContentHash: Data?,
        lastDownloadAttemptTimestamp: UInt64?,
        incrementalMac: Data?,
        incrementalMacChunkSize: UInt32?,
    ) {
        let integrityCheck: AttachmentIntegrityCheck?
        if let digestSHA256Ciphertext {
            // This is slightly load-bearing but we want to use digest if we
            // have it because we can only _send_ attachments with digests.
            // Other mechanisms will ensure we never get to the send flow
            // without first doing a transit tier upload that sets the
            // digest, so we just have to ensure we _read_ that digest here
            // instead of the plaintext hash.
            integrityCheck = .digestSHA256Ciphertext(digestSHA256Ciphertext)
        } else if let sha256ContentHash {
            integrityCheck = .sha256ContentHash(sha256ContentHash)
        } else {
            integrityCheck = nil
        }
        guard
            let cdnNumber,
            let cdnKey,
            let uploadTimestamp,
            let encryptionKey,
            let integrityCheck
        else {
            owsAssertDebug(
                cdnNumber == nil
                    && cdnKey == nil
                    && uploadTimestamp == nil
                    && unencryptedByteCount == nil
                    && digestSHA256Ciphertext == nil,
                "Have partial transit cdn info!",
            )
            return nil
        }
        self.cdnNumber = cdnNumber
        self.cdnKey = cdnKey
        self.uploadTimestamp = uploadTimestamp
        self.lastDownloadAttemptTimestamp = lastDownloadAttemptTimestamp
        self.encryptionKey = encryptionKey
        self.unencryptedByteCount = unencryptedByteCount
        self.integrityCheck = integrityCheck
        if let incrementalMac, let incrementalMacChunkSize {
            self.incrementalMacInfo = .init(mac: incrementalMac, chunkSize: incrementalMacChunkSize)
        } else {
            owsAssertDebug(
                incrementalMac == nil && incrementalMacChunkSize == nil,
                "Have partial transit tier incremental mac info!",
            )
            self.incrementalMacInfo = nil
        }
    }
}

private extension Attachment.MediaTierInfo {
    init?(
        cdnNumber: UInt32?,
        unencryptedByteCount: UInt32?,
        sha256ContentHash: Data?,
        uploadEra: String?,
        lastDownloadAttemptTimestamp: UInt64?,
        incrementalMac: Data?,
        incrementalMacChunkSize: UInt32?,
    ) {
        guard
            let uploadEra,
            let unencryptedByteCount,
            let sha256ContentHash
        else {
            return nil
        }
        self.cdnNumber = cdnNumber
        self.unencryptedByteCount = unencryptedByteCount
        self.sha256ContentHash = sha256ContentHash
        self.uploadEra = uploadEra
        self.lastDownloadAttemptTimestamp = lastDownloadAttemptTimestamp
        if let incrementalMac, let incrementalMacChunkSize {
            self.incrementalMacInfo = .init(mac: incrementalMac, chunkSize: incrementalMacChunkSize)
        } else {
            owsAssertDebug(
                incrementalMac == nil && incrementalMacChunkSize == nil,
                "Have partial media tier incremental mac info!",
            )
            self.incrementalMacInfo = nil
        }
    }
}

private extension Attachment.ThumbnailMediaTierInfo {
    init?(
        cdnNumber: UInt32?,
        uploadEra: String?,
        lastDownloadAttemptTimestamp: UInt64?,
    ) {
        guard
            let uploadEra
        else {
            owsAssertDebug(
                uploadEra == nil,
                "Have partial thumbnail media cdn info!",
            )
            return nil
        }
        self.cdnNumber = cdnNumber
        self.uploadEra = uploadEra
        self.lastDownloadAttemptTimestamp = lastDownloadAttemptTimestamp
    }
}

private extension Attachment.IncrementalMacInfo {
    init?(
        mac: Data?,
        chunkSize: UInt32?,
    ) {
        guard let mac, let chunkSize else { return nil }

        self.mac = mac
        self.chunkSize = chunkSize
    }
}
