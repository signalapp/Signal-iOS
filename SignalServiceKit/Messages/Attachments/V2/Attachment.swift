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

    /// Information for the transit tier upload, if known to be uploaded.
    public let transitTierInfo: TransitTierInfo?

    /// Used for quoted reply thumbnail attachments.
    /// The id of the quoted reply's target message's attachment that is to be thumbnail'ed.
    /// Only relevant for non-streams. At "download" time instead of using the transit tier info
    /// as the source we use the original attachment's file. Once this attachment is a stream,
    /// this field should be set to nil (but should just be ignored regardless).
    public let originalAttachmentIdForQuotedReply: Attachment.IDType?

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

    // MARK: - Inner structs

    /// Information supporting "streaming" video, which requires computing an
    /// "incremental" MAC rather than one big HMAC verification on the
    /// fully-downloaded file.
    public struct IncrementalMacInfo: Equatable {
        public let mac: Data
        public let chunkSize: UInt32
    }

    /// Information for the "stream" (the attachment downloaded and locally available).
    public struct StreamInfo {
        /// Sha256 hash of the plaintext of the media content. Used to deduplicate incoming media.
        public let sha256ContentHash: Data

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

        /// SHA256Hash(iv + cyphertext + hmac),
        /// (iv + cyphertext + hmac) is the thing we actually upload to the CDN server, which uses
        /// the ``TransitTierInfo.encryptionKey`` field.
        ///
        /// Generated locally for outgoing attachments.
        /// For incoming attachments, taken off the service proto. If validation fails, the download is rejected.
        public let digestSHA256Ciphertext: Data

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

        /// SHA256Hash(iv + cyphertext + hmac),
        /// (iv + cyphertext + hmac) is the thing we actually upload to the CDN server, which uses
        /// the ``TransitTierInfo.encryptionKey`` field.
        ///
        /// Equivalent to `StreamInfo.digestSHA256Ciphertext`, but may be available
        /// if the rest of `StreamInfo` is unavailable (e.g. after a restore).
        public let digestSHA256Ciphertext: Data

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

    internal init(record: Attachment.Record) throws {
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
            videoStillFrameRelativeFilePath: record.videoStillFrameRelativeFilePath
        )

        self.id = id
        self.blurHash = record.blurHash
        self.mimeType = record.mimeType
        self.encryptionKey = record.encryptionKey
        self.originalAttachmentIdForQuotedReply = record.originalAttachmentIdForQuotedReply
        self.mediaName = record.mediaName
        self.localRelativeFilePathThumbnail = record.localRelativeFilePathThumbnail

        self.streamInfo = StreamInfo(
            sha256ContentHash: record.sha256ContentHash,
            encryptedByteCount: record.encryptedByteCount,
            unencryptedByteCount: record.unencryptedByteCount,
            contentType: contentType,
            digestSHA256Ciphertext: record.digestSHA256Ciphertext,
            localRelativeFilePath: record.localRelativeFilePath
        )
        self.transitTierInfo = TransitTierInfo(
            cdnNumber: record.transitCdnNumber,
            cdnKey: record.transitCdnKey,
            uploadTimestamp: record.transitUploadTimestamp,
            encryptionKey: record.transitEncryptionKey,
            unencryptedByteCount: record.transitUnencryptedByteCount,
            digestSHA256Ciphertext: record.transitDigestSHA256Ciphertext,
            lastDownloadAttemptTimestamp: record.lastTransitDownloadAttemptTimestamp,
            incrementalMac: record.transitTierIncrementalMac,
            incrementalMacChunkSize: record.transitTierIncrementalMacChunkSize
        )
        self.mediaTierInfo = MediaTierInfo(
            cdnNumber: record.mediaTierCdnNumber,
            unencryptedByteCount: record.mediaTierUnencryptedByteCount ?? record.unencryptedByteCount,
            digestSHA256Ciphertext: record.mediaTierDigestSHA256Ciphertext ?? record.digestSHA256Ciphertext,
            uploadEra: record.mediaTierUploadEra,
            lastDownloadAttemptTimestamp: record.lastMediaTierDownloadAttemptTimestamp,
            incrementalMac: record.mediaTierIncrementalMac,
            incrementalMacChunkSize: record.mediaTierIncrementalMacChunkSize
        )
        self.thumbnailMediaTierInfo = ThumbnailMediaTierInfo(
            cdnNumber: record.thumbnailCdnNumber,
            uploadEra: record.thumbnailUploadEra,
            lastDownloadAttemptTimestamp: record.lastThumbnailDownloadAttemptTimestamp
        )
    }

    public var isUploadedToTransitTier: Bool {
        return transitTierInfo != nil
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

    public func asBackupThumbnail() -> AttachmentBackupThumbnail? {
        return AttachmentBackupThumbnail(attachment: self)
    }

    public static func mediaName(digestSHA256Ciphertext: Data) -> String {
        // We use the hexadecimal-encoded digest as the media name.
        // This ensures media name collisions occur only between the
        // same attachment contents encrypted with the same key.
        return digestSHA256Ciphertext.hexadecimalString
    }

    public static func uploadEra(backupSubscriptionId: Data) throws -> String {
        // We just hash and base64 encode the subscription id as the "upload era".
        // All the "era" means is if it changes, all existing uploads to the backup
        // tier should be considered invalid and needing reupload.
        // Hash so as to avoid putting the unsafe-to-log subscription id in more places.
        var hasher = SHA256()
        hasher.update(data: backupSubscriptionId)
        return Data(hasher.finalize()).base64EncodedString()
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
            plaintextDataLength: stream.info.unencryptedByteCount
        )

        if
            // We have a prior upload
            let transitTierInfo,
            // And we are still in the window to reuse it
            dateProvider().timeIntervalSince(
                Date(millisecondsSince1970: transitTierInfo.uploadTimestamp)
            ) <= Upload.Constants.uploadReuseWindow
        {
            // We have unexpired transit tier info. Reuse that upload.
            return .reuseExistingUpload(
                .init(
                    cdnKey: transitTierInfo.cdnKey,
                    cdnNumber: transitTierInfo.cdnNumber,
                    key: transitTierInfo.encryptionKey,
                    digest: transitTierInfo.digestSHA256Ciphertext,
                    // Okay to fall back to our local data length even if the original sender
                    // didn't include it; we now know it from the local file.
                    plaintextDataLength: transitTierInfo.unencryptedByteCount ?? metadata.plaintextDataLength,
                    // Encryped length is the same regardless of the key used.
                    encryptedDataLength: metadata.encryptedDataLength
                )
            )
        } else if
            // This device has never uploaded
            transitTierInfo == nil,
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
        encryptedByteCount: UInt32?,
        unencryptedByteCount: UInt32?,
        contentType: Attachment.ContentType?,
        digestSHA256Ciphertext: Data?,
        localRelativeFilePath: String?
    ) {
        guard
            let sha256ContentHash,
            let encryptedByteCount,
            let unencryptedByteCount,
            let contentType,
            let digestSHA256Ciphertext,
            let localRelativeFilePath
        else {
            owsAssertDebug(
                sha256ContentHash == nil
                && encryptedByteCount == nil
                && unencryptedByteCount == nil
                && contentType == nil
                && localRelativeFilePath == nil,
                "Have partial stream info!"
            )
            return nil
        }
        self.sha256ContentHash = sha256ContentHash
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
        lastDownloadAttemptTimestamp: UInt64?,
        incrementalMac: Data?,
        incrementalMacChunkSize: UInt32?
    ) {
        guard
            let cdnNumber,
            let cdnKey,
            let uploadTimestamp,
            let encryptionKey,
            let unencryptedByteCount,
            let digestSHA256Ciphertext
        else {
            owsAssertDebug(
                cdnNumber == nil
                && cdnKey == nil
                && uploadTimestamp == nil
                && encryptionKey == nil
                && unencryptedByteCount == nil
                && digestSHA256Ciphertext == nil,
                "Have partial transit cdn info!"
            )
            return nil
        }
        self.cdnNumber = cdnNumber
        self.cdnKey = cdnKey
        self.uploadTimestamp = uploadTimestamp
        self.lastDownloadAttemptTimestamp = lastDownloadAttemptTimestamp
        self.encryptionKey = encryptionKey
        self.unencryptedByteCount = unencryptedByteCount
        self.digestSHA256Ciphertext = digestSHA256Ciphertext
        if let incrementalMac, let incrementalMacChunkSize {
            self.incrementalMacInfo = .init(mac: incrementalMac, chunkSize: incrementalMacChunkSize)
        } else {
            owsAssertDebug(
                incrementalMac == nil && incrementalMacChunkSize == nil,
                "Have partial transit tier incremental mac info!"
            )
            self.incrementalMacInfo = nil
        }
    }
}

private extension Attachment.MediaTierInfo {
    init?(
        cdnNumber: UInt32?,
        unencryptedByteCount: UInt32?,
        digestSHA256Ciphertext: Data?,
        uploadEra: String?,
        lastDownloadAttemptTimestamp: UInt64?,
        incrementalMac: Data?,
        incrementalMacChunkSize: UInt32?
    ) {
        guard
            let uploadEra,
            let unencryptedByteCount,
            let digestSHA256Ciphertext
        else {
            owsAssertDebug(
                uploadEra == nil,
                "Have partial media cdn info!"
            )
            return nil
        }
        self.cdnNumber = cdnNumber
        self.unencryptedByteCount = unencryptedByteCount
        self.digestSHA256Ciphertext = digestSHA256Ciphertext
        self.uploadEra = uploadEra
        self.lastDownloadAttemptTimestamp = lastDownloadAttemptTimestamp
        if let incrementalMac, let incrementalMacChunkSize {
            self.incrementalMacInfo = .init(mac: incrementalMac, chunkSize: incrementalMacChunkSize)
        } else {
            owsAssertDebug(
                incrementalMac == nil && incrementalMacChunkSize == nil,
                "Have partial media tier incremental mac info!"
            )
            self.incrementalMacInfo = nil
        }
    }
}

private extension Attachment.ThumbnailMediaTierInfo {
    init?(
        cdnNumber: UInt32?,
        uploadEra: String?,
        lastDownloadAttemptTimestamp: UInt64?
    ) {
        guard
            let uploadEra
        else {
            owsAssertDebug(
                uploadEra == nil,
                "Have partial thumbnail media cdn info!"
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
        chunkSize: UInt32?
    ) {
        guard let mac, let chunkSize else { return nil }

        self.mac = mac
        self.chunkSize = chunkSize
    }
}
