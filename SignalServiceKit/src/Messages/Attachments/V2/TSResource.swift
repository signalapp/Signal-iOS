//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Bridging protocol between v1 attachments (TSAttachment) and v2 attachments (Attachment, coming soon).
public protocol TSResource {

    // TODO: this will become non-optional
    var blurHash: String? { get }

    /// Filename from the sender, used for rendering as a file attachment.
    /// NOT the same as the file name on disk.
    var sourceFilename: String? { get }

    var transitCdnNumber: UInt32? { get }
    var transitCdnKey: String? { get }

    var transitUploadTimestamp: UInt64? { get }

    // TODO: this will become non-optional
    var encryptionKey: Data? { get }

    var unenecryptedByteCount: UInt32? { get }
    var encryptedByteCount: UInt32? { get }

    /// Digest info from the attachment sender; used for optional validation
    /// if available, but not neccessary in general.
    var protoDigest: Data? { get }

    // f.k.a. contentType
    var mimeType: String { get }

    // MARK: - Converters

    func asStream() -> TSResourceStream?

    // MARK: - Table Join Getters

    func attachmentType(forContainingMessage: TSMessage, tx: DBReadTransaction) -> TSAttachmentType

    func transitTierDownloadState(tx: DBReadTransaction) -> TSAttachmentPointerState?

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
    var bridge: TSAttachment { self as! TSAttachment }
}
