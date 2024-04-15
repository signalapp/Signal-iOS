//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Uniquely and stably identifies an item for the all media view
/// (either a MediaGalleryRecord or an AttachmentReference).
public enum MediaGalleryItemId: Equatable, Hashable {
    /// Row Id for a ``MediaGalleryRecord``
    case legacy(mediaGalleryRecordId: Int64)
    case v2(AttachmentReferenceId)
}

/// Id for the underlying "resource" of a media item.
///
/// In v2-attachment-land, this is the same as ``MediaGalleryItemId``;
/// the table we use for the all media view is the AttachmentReferences table
/// so there is no separate id.
///
/// In v1-land, this is _different_ than a ``MediaGalleryItemId``;
/// the item id tracks the rowId of the MediaGalleryRecord,
/// this tracks the id of the TSAttachment.
public enum MediaGalleryResourceId: Equatable, Hashable {
    case legacy(attachmentUniqueId: String)
    case v2(AttachmentReferenceId)
}

extension TSResourceReference {

    public var mediaGalleryResourceId: MediaGalleryResourceId {
        switch self.concreteType {
        case .legacy(let tsAttachmentReference):
            return .legacy(attachmentUniqueId: tsAttachmentReference.uniqueId)
        case .v2(let attachmentReference):
            return .v2(attachmentReference.referenceId)
        }
    }
}
