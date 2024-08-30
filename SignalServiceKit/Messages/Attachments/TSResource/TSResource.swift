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
    ///
    /// - SeeAlso: ``precomputedPlaintextResourceSha256Digest``
    var encryptedResourceSha256Digest: Data? { get }

    /// A known SHA256 digest of the plaintext content of the resource.
    ///
    /// This property is `O(1)`, and correspondingly will return `nil` if the
    /// plaintext digest has not been precomputed. For example, this value will
    /// be `nil` for all V1 attachments, which have never tracked a plaintext
    /// digest.
    ///
    /// - SeeAlso: ``encryptedResourceSha256Digest``
    var knownPlaintextResourceSha256Hash: Data? { get }

    // f.k.a. contentType
    var mimeType: String { get }

    var isUploadedToTransitTier: Bool { get }

    var hasMediaTierInfo: Bool { get }

    // MARK: - Converters

    var concreteType: ConcreteTSResource { get }

    func asResourceStream() -> TSResourceStream?

    func asResourceBackupThumbnail() -> TSResourceBackupThumbnail?
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
