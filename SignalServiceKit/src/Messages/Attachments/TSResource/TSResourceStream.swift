//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A TSResource for which we have the fullsize data on local disk.
public protocol TSResourceStream: TSResource {

    func fileURLForDeletion() throws -> URL

    /// Interprets the data on disk as a string with standard encoding (utf-8, but thats an implementation detail).
    func decryptedLongText() -> String?

    func decryptedImage() async throws -> UIImage

    var concreteStreamType: ConcreteTSResourceStream { get }

    // MARK: - Cached media properties

    /// The validated content type from the content itself, not just the one declared by the
    /// mimeType (which comes from the sender and therefore can be spoofed).
    ///
    /// Only returns a value if we have it cached; will not compute a value on the fly.
    /// V2 attachments will always have a cached value.
    var cachedContentType: TSResourceContentType? { get }

    /// The validated content type from the content itself, not just the one declared by the
    /// mimeType (which comes from the sender and therefore can be spoofed).
    ///
    /// Potentially performs an expensive validation by reading the contents from disk, or uses the
    /// cached value if available.
    /// V2 attachments will always have a cached value.
    func computeContentType() -> TSResourceContentType
}

extension TSResourceStream {

    // TODO: this is just to help with bridging while all TSResources are actually TSAttachments,
    // and we are migrating code to TSResource that hands an instance to unmigrated code.
    // Remove once all references to TSAttachment are replaced with TSResource.
    public var bridgeStream: TSAttachmentStream { self as! TSAttachmentStream }
}
