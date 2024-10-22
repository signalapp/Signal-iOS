//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Corresponds to an AttachmentReference, but things get complicated.
///
/// In the v2 world, AttachmentReference(s) come from their own table, and require
/// a db read if you start from their owner (e.g. a TSMessage).
/// In the legacy TSAttachment world, this doesn't exist; the "reference" is a
/// TSAttachment.uniqueId that lives on the owner (e.g. TSMessage).
///
/// Great, so a TSAttachmentReference should just be unique id!
///
/// But an AttachmentReference, and therefore TSResourceReference, is more than
/// just an identifier. It contains other medata, like sourceFilename, that in the legacy
/// world is found _on_ TSAttachment.
///
/// Great, so a TSAttachmentReference can just hold the TSAttachment!
///
/// ...Not right either. Because sometimes, e.g. when doing OrphanDataCleaner or
/// when queing a download, we want just the uniqueId reference even if the actual
/// attachment has been deleted. So if our TSAttachmentReference _required_ a
/// TSAttachment, we'd get nil in those cases, which is dangerous/bad.
///
/// So a TSAttachmentReference is actually a required unique id (the reference),
/// _plus_ an optional attachment, if we found it, that we use for metadata that
/// in v2-land exists on the AttachmentReferences table.
public class TSAttachmentReference: TSResourceReference {

    public let uniqueId: String
    public let attachment: TSAttachment?

    internal init(uniqueId: String, attachment: TSAttachment?) {
        self.uniqueId = uniqueId
        self.attachment = attachment
    }

    public var resourceId: TSResourceId { .legacy(uniqueId: uniqueId) }

    public var concreteType: ConcreteTSResourceReference { .legacy(self) }

    public var sourceFilename: String? { attachment?.sourceFilename }

    public var sourceMediaSizePixels: CGSize? {
        if
            let attachmentPointer = attachment as? TSAttachmentPointer,
            attachmentPointer.mediaSize.isNonEmpty
        {
            return attachmentPointer.mediaSize
        } else {
            return nil
        }
    }

    public var storyMediaCaption: StyleOnlyMessageBody? { nil }

    public var legacyMessageCaption: String? { attachment?.caption }

    public var renderingFlag: AttachmentReference.RenderingFlag {
        switch attachment?.attachmentType {
        case .voiceMessage:
            return .voiceMessage
        case .borderless:
            return .borderless
        case .GIF:
            return .shouldLoop
        case .default, nil:
            fallthrough
        @unknown default:
            return .default
        }
    }

    public func hasSameOwner(as other: TSResourceReference) -> Bool {
        guard let other = other as? TSAttachmentReference else {
            return false
        }
        return uniqueId == other.uniqueId
    }

    public func fetchOwningMessage(tx: SDSAnyReadTransaction) -> TSMessage? {
        return attachment?.fetchAlbumMessage(transaction: tx)
    }

    public func orderInOwningMessage(_ message: TSMessage) -> UInt32? {
        return message.attachmentIds?.firstIndex(of: uniqueId).map(UInt32.init(_:))
    }

    public func knownIdInOwningMessage(_ message: TSMessage) -> UUID? {
        return attachment?.clientUuid.flatMap { UUID(uuidString: $0) }
    }
}

extension TSAttachmentType {

    var asRenderingFlag: AttachmentReference.RenderingFlag {
        switch self {
        case .default:
            return .default
        case .voiceMessage:
            return .voiceMessage
        case .borderless:
            return .borderless
        case .GIF:
            return .shouldLoop
        @unknown default:
            return .default
        }
    }
}
