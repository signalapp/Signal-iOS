//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Bridging protocol between v1 attachments (TSAttachment) and v2 attachments (Attachment, coming soon).
public protocol TSResource {

    var resourceId: TSResourceId { get }

    var resourceBlurHash: String? { get }

    var transitCdnNumber: UInt32? { get }
    var transitCdnKey: String? { get }

    var transitUploadTimestamp: UInt64? { get }

    /// Optional for legacy attachments; for v2 attachments this is non-optional.
    var resourceEncryptionKey: Data? { get }

    var unencryptedResourceByteCount: UInt32? { get }
    var encryptedResourceByteCount: UInt32? { get }

    /// File digest info.
    /// SHA256Hash(iv + cyphertext + hmac)
    ///
    /// May be null if restored from a backup, or for legacy attachments. In this case, validation
    /// should be ignored.
    var encryptedResourceSha256Digest: Data? { get }

    // f.k.a. contentType
    var mimeType: String { get }

    var isUploadedToTransitTier: Bool { get }

    // MARK: - Converters

    var concreteType: ConcreteTSResource { get }

    func asResourceStream() -> TSResourceStream?

    // MARK: - Table Join Getters

    func attachmentType(forContainingMessage: TSMessage, tx: DBReadTransaction) -> TSAttachmentType

    func caption(forContainingMessage: TSMessage, tx: DBReadTransaction) -> String?
}

extension TSResource {

    /// Returns a pointer to the file on transit tier cdn if we can construct it.
    /// Can still return a value even if the media is downloaded.
    public func asTransitTierPointer() -> TSResourcePointer? {
        guard let transitCdnKey, let transitCdnNumber else {
            return nil
        }
        return TSResourcePointer(
            resource: self,
            cdnNumber: transitCdnNumber,
            cdnKey: transitCdnKey
        )
    }
}

extension TSResource {

    // TODO: this is just to help with bridging while all TSResources are actually TSAttachments,
    // and we are migrating code to TSResource that hands an instance to unmigrated code.
    // Remove once all references to TSAttachment are replaced with TSResource.
    public var bridge: TSAttachment { self as! TSAttachment }
}
