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

    public var resourceEncryptionKey: Data? { streamInfo?.encryptionKey }
    public var unenecryptedResourceByteCount: UInt32? { streamInfo?.unenecryptedByteCount }
    public var encryptedResourceByteCount: UInt32? { streamInfo?.encryptedByteCount }
    public var encryptedResourceSha256Digest: Data? { streamInfo?.encryptedFileSha256Digest }
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

    public func attachmentType(forContainingMessage: TSMessage, tx: DBReadTransaction) -> TSAttachmentType {
        fatalError("Unimplemented!")
    }

    public func caption(forContainingMessage: TSMessage, tx: DBReadTransaction) -> String? {
        fatalError("Unimplemented!")
    }
}

// MARK: - Attachment Stream

extension AttachmentStream: TSResourceStream {
    public func fileURLForDeletion() throws -> URL {
        fatalError("Unimplemented!")
    }

    public func decryptedLongText() -> String? {
        fatalError("Unimplemented!")
    }

    public func decryptedRawData() async throws -> Data {
        fatalError("Unimplemented!")
    }

    public func decryptedRawDataSync() throws -> Data {
        fatalError("Unimplemented!")
    }

    public func decryptedImage() async throws -> UIImage {
        fatalError("Unimplemented!")
    }

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

    public var unenecryptedResourceByteCount: UInt32? { unenecryptedByteCount }

    public var encryptedResourceByteCount: UInt32? { encryptedByteCount }

    public var encryptedResourceSha256Digest: Data? { encryptedFileSha256Digest }

    public var isUploadedToTransitTier: Bool { attachment.isUploadedToTransitTier }

    public var mimeType: String { attachment.mimeType }

    public var concreteType: ConcreteTSResource { attachment.concreteType }

    public func asResourceStream() -> TSResourceStream? { self }

    public func attachmentType(forContainingMessage: TSMessage, tx: DBReadTransaction) -> TSAttachmentType {
        return attachment.attachmentType(forContainingMessage: forContainingMessage, tx: tx)
    }

    public func caption(forContainingMessage: TSMessage, tx: DBReadTransaction) -> String? {
        return attachment.caption(forContainingMessage: forContainingMessage, tx: tx)
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
        }
    }
}
