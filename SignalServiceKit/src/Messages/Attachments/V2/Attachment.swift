//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// TODO: actually define this class; just a placeholder for now.
/// Represents an attachment stored on disk.
public class Attachment {

    public typealias IDType = Int64

    /// SQLite row id.
    public private(set) var id: IDType!

    /// Nil for:
    /// * non-visual-media attachments
    /// * undownloaded attachments where the sender didn't include the value.
    /// Otherwise this contains the value from the sender for undownloaded attachments,
    /// and our locally computed blurhash value for downloading attachments.
    public let blurHash: String?

    /// Sha256 hash of the plaintext of the media content. Used to deduplicate incoming media.
    public let contentHash: String?

    /// Byte count of the encrypted fullsize resource
    public let encryptedByteCount: UInt32?
    ///  Byte count of the decrypted fullsize resource
    public let unenecryptedByteCount: UInt32?

    /// MIME type we get from the attachment's sender, known
    /// even before downloading the attachment.
    /// **May not match the actual type of the file on disk.**
    public let mimeType: String

    /// For downloaded attachments, the type of content in the actual file.
    /// If a case is set it means the file contents have been validated.
    public let contentType: ContentType?

    /// Encryption key used for transit tier AND media tier.
    /// If from an incoming message, we get this from the proto, and can reuse it for local and media backup encryption.
    /// If outgoing, we generate the key ourselves when we create the attachment, and again can reuse it for everything.
    public let encryptionKey: Data

    /// CDN number for the upload in the transit tier (or nil if not uploaded).
    public let transitCdnNumber: UInt32?
    /// CDN key for the upload in the transit tier (or nil if not uploaded).
    public let transitCdnKey: String?
    /// If outgoing: Local time the attachment was uploaded to the transit tier, or nil if not uploaded.
    /// If incoming: timestamp on the message the attachment came in on.
    /// Used to determine whether reuploading is necessary for e.g. forwarding.
    public let transitUploadTimestamp: UInt64?
    /// Timestamp we last tried (and failed) to download from the transit tier.
    /// Nil if we have not tried or have successfully downloaded.
    public let lastTransitDownloadAttemptTimestamp: UInt64?

    /// MediaName used for backups (but assigned even if backups disabled).
    public let mediaName: String

    /// CDN number for the fullsize upload in the media tier (or nil if not uploaded).
    public let mediaCdnNumber: UInt32?
    /// If null, the resource has not been uploaded to the media tier.
    /// If the value in this column doesn’t match the current Backup Subscription Era,
    /// it should also be considered un-uploaded.
    /// Set to the current era when uploaded.
    public let mediaTierUploadEra: UInt64?
    /// Timestamp we last tried (and failed) to download from the media tier.
    /// Nil if we have not tried or have successfully downloaded.
    public let lastMediaDownloadAttemptTimestamp: UInt64?

    /// CDN number for the thumbnail upload in the media tier (or nil if not uploaded).
    /// Not to be confused with thumbnails used for rendering, or those created for quoted message replies.
    /// This thumbnail is exclusively used for backup purposes.
    public let thumbnailCdnNumber: UInt32?
    /// If null, the thumbnail resource has not been uploaded to the media tier.
    /// If the value in this column doesn’t match the current Backup Subscription Era,
    /// it should also be considered un-uploaded.
    /// Set to the current era when uploaded.
    public let thumbnailUploadEra: UInt64?
    /// Timestamp we last tried (and failed) to download the thumbnail from the media tier.
    /// Nil if we have not tried or have successfully downloaded.
    public let lastThumbnailDownloadAttemptTimestamp: UInt64?

    /// Filepath to the encrypted fullsize media file on local disk.
    public let localRelativeFilePath: String?
    /// Filepath to the encrypted thumbnail file on local disk.
    /// Not to be confused with thumbnails used for rendering, or those created for quoted message replies.
    /// This thumbnail is exclusively used for backup purposes.
    public let localRelativeFilePathThumbnail: String?

    /// File digest info.
    /// Generated locally for outgoing attachments, included in message payload for incoming.
    /// May be null if restored from a backup, or for legacy outgoing attachments.
    public let protoDigest: Data?

    private init(
        id: Int64!,
        blurHash: String,
        contentHash: String?,
        encryptedByteCount: UInt32?,
        unenecryptedByteCount: UInt32?,
        mimeType: String,
        contentType: ContentType?,
        encryptionKey: Data,
        transitCdnNumber: UInt32?,
        transitCdnKey: String?,
        transitUploadTimestamp: UInt64?,
        lastTransitDownloadAttemptTimestamp: UInt64?,
        mediaName: String,
        mediaCdnNumber: UInt32?,
        mediaTierUploadEra: UInt64?,
        lastMediaDownloadAttemptTimestamp: UInt64?,
        thumbnailCdnNumber: UInt32?,
        thumbnailUploadEra: UInt64?,
        lastThumbnailDownloadAttemptTimestamp: UInt64?,
        localRelativeFilePath: String?,
        localRelativeFilePathThumbnail: String?,
        protoDigest: Data?
    ) {
        fatalError("No instances should exist yet!")
    }

    func asStream() -> AttachmentStream? {
        return AttachmentStream(attachment: self)
    }
}
