//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A reference to an attachment.
/// In the legacy world...this is just the attachment itself in disguise.
/// In the v2 world, this is an AttachmentReference, from the join table between Attachments and their owners.
/// We begin the v1->v2 migration by establishing that all callers must get a reference first and then get
/// the full attachment.
public protocol TSResourceReference {

    var resourceId: TSResourceId { get }

    var concreteType: ConcreteTSResourceReference { get }

    /// Filename from the sender, used for rendering as a file attachment.
    /// NOT the same as the file name on disk.
    var sourceFilename: String? { get }

    /// Media size (in pixels) from the sender, used for display size before downloading.
    /// Not necessarily the same as the actual media size (if spoofed by the sender).
    var sourceMediaSizePixels: CGSize? { get }

    /// Hint from the sender telling us how to render the attachment.
    var renderingFlag: AttachmentReference.RenderingFlag { get }

    /// Caption for story message media attachments
    var storyMediaCaption: StyleOnlyMessageBody? { get }

    /// Caption for message body attachments.
    /// Unused in the modern app but may be set for old messages.
    var legacyMessageCaption: String? { get }

    // NOTE: mimeType and contentType are deliberately excluded from
    // this protocol; they have wildly different meanings in v1 and v2
    // and are safe to use in entirely different circumstances.
    // To check these values, fetch the full resource.

    func hasSameOwner(as other: TSResourceReference) -> Bool

    // MARK: Message owner getters

    func fetchOwningMessage(tx: SDSAnyReadTransaction) -> TSMessage?

    func orderInOwningMessage(_ message: TSMessage) -> UInt32?

    func knownIdInOwningMessage(_ message: TSMessage) -> UUID?
}

// MARK: - Convenience fetchers

extension TSResourceReference {

    /// Note: this takes an SDS transaction because its a convenience
    /// method that accesses globals. If you want a testable variant
    /// that lets you override the return value, use TSResourceStore.
    public func fetch(tx: SDSAnyReadTransaction) -> TSResource? {
        // Always re-fetch. Legacy TSAttachmentReferences already have the attachment object,
        // but its better to have the API expectation be that the object you get back from this
        // fetch method is always fresh.
        return DependenciesBridge.shared.tsResourceStore.fetch(self.resourceId, tx: tx.asV2Read)
    }

}

extension Array where Element == TSResourceReference {

    /// Ordering of the return values is not guaranteed.
    ///
    /// Note: this takes an SDS transaction because its a convenience
    /// method that accesses globals. If you want a testable variant
    /// that lets you override the return value, use TSResourceStore.
    public func fetchAll(tx: SDSAnyReadTransaction) -> [TSResource] {
        return DependenciesBridge.shared.tsResourceStore.fetch(self.map(\.resourceId), tx: tx.asV2Read)
    }
}
