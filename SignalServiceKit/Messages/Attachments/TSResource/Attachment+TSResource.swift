//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - Attachment

extension Attachment: TSResource {

    public var resourceBlurHash: String? {
        blurHash
    }

    public var resourceEncryptionKey: Data? { self.encryptionKey }
    public var unencryptedResourceByteCount: UInt32? { streamInfo?.unencryptedByteCount }
    public var encryptedResourceByteCount: UInt32? { streamInfo?.encryptedByteCount }
    public var encryptedResourceSha256Digest: Data? { streamInfo?.digestSHA256Ciphertext }
    public var knownPlaintextResourceSha256Hash: Data? { streamInfo?.sha256ContentHash }
    public var transitCdnKey: String? { transitTierInfo?.cdnKey }
    public var transitCdnNumber: UInt32? { transitTierInfo?.cdnNumber }
    public var transitUploadTimestamp: UInt64? { transitTierInfo?.uploadTimestamp }

    public var resourceId: TSResourceId {
        .v2(rowId: id)
    }

    public var concreteType: ConcreteTSResource {
        return .v2(self)
    }

    public func asResourceStream() -> TSResourceStream? {
        return AttachmentStream(attachment: self)
    }

    public func asResourceBackupThumbnail() -> TSResourceBackupThumbnail? {
        return asBackupThumbnail()
    }
}

extension AttachmentBackupThumbnail: TSResourceBackupThumbnail {
    public var originalMimeType: String {
        attachment.mimeType
    }

    public var estimatedOriginalSizeInBytes: UInt32 {
        guard let unencryptedByteCount = attachment.mediaTierInfo?.unencryptedByteCount else {
            return 0
        }

        let encryptionOverheadByteLength: UInt32 = /* iv */ 16 + /* hmac */ 32
        let paddedSize = UInt32(Cryptography.paddedSize(unpaddedSize: UInt(unencryptedByteCount)))
        let pkcs7PaddingLength = 16 - (paddedSize % 16)
        return paddedSize + pkcs7PaddingLength + encryptionOverheadByteLength
    }

    public var image: UIImage? {
        return try? UIImage.from(self)
    }
    public var resource: TSResource {
        return attachment
    }
}

// MARK: - Attachment Stream

extension AttachmentStream: TSResourceStream {

    public var concreteStreamType: ConcreteTSResourceStream {
        return .v2(self)
    }

    public var cachedContentType: TSResourceContentType? {
        return contentType.resourceType
    }

    public func computeContentType() -> TSResourceContentType {
        return contentType.resourceType
    }

    public func computeIsValidVisualMedia() -> Bool {
        return contentType.isVisualMedia
    }
}

extension AttachmentStream: TSResource {
    public var resourceId: TSResourceId { attachment.resourceId }

    public var resourceBlurHash: String? { attachment.resourceBlurHash }

    public var transitCdnNumber: UInt32? { attachment.transitCdnNumber }

    public var transitCdnKey: String? { attachment.transitCdnKey }

    public var transitUploadTimestamp: UInt64? { attachment.transitUploadTimestamp }

    public var resourceEncryptionKey: Data? { attachment.resourceEncryptionKey }

    public var unencryptedResourceByteCount: UInt32? { unencryptedByteCount }

    public var encryptedResourceByteCount: UInt32? { encryptedByteCount }

    public var encryptedResourceSha256Digest: Data? { encryptedFileSha256Digest }

    public var knownPlaintextResourceSha256Hash: Data? { info.sha256ContentHash }

    public var isUploadedToTransitTier: Bool { attachment.isUploadedToTransitTier }

    public var hasMediaTierInfo: Bool { attachment.hasMediaTierInfo }

    public var mimeType: String { attachment.mimeType }

    public var concreteType: ConcreteTSResource { attachment.concreteType }

    public func asResourceStream() -> TSResourceStream? { self }

    public func asResourceBackupThumbnail() -> TSResourceBackupThumbnail? {
        return self.attachment.asResourceBackupThumbnail()
    }
}

// MARK: - AttachmentTransitPointer

extension AttachmentTransitPointer {

    var asResourcePointer: TSResourcePointer {
        return TSResourcePointer(resource: attachment, cdnNumber: cdnNumber, cdnKey: cdnKey)
    }
}

// MARK: - AttachmentThumbnailQuality

extension AttachmentThumbnailQuality {

    var tsQuality: TSAttachmentThumbnailQuality {
        switch self {
        case .small:
            return .small
        case .medium:
            return .medium
        case .mediumLarge:
            return .mediumLarge
        case .large:
            return .large
        case .backupThumbnail:
            // legacy attachments don't use backup thumbnail size,
            // but small is close enough.
            owsFailDebug("Shouldn't use backup size for tsAttachments")
            return .small
        }
    }
}
