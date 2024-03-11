//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// This differs from OWSAttachmentInfo; that object is persisted to disk and represents the legacy storage
/// of attachment metadata _on_ the TSQuotedMessage.
/// This is an abstraction that only exists in memory and can come from either source: an OWSAttachmentInfo
/// OR the AttachmentReferences table.
///
/// TODO: we will eventually define an AttachmentReference object, which might replace this one
/// or might be mappable _to_ this object, because this one needs to be objc compatible and we
/// probably don't want to enforce that on AttachmentReference.
@objcMembers
public class QuotedThumbnailAttachmentMetadata: NSObject {

    internal let attachmentReferenceType: OWSAttachmentInfoReference

    /// For attachments with a thumbnail, the id for that attachment.
    /// Other types (e.g. audio file) might have mimeType and sourceFileName set but no id.
    public let thumbnailAttachmentId: String?
    public let mimeType: String?
    public let sourceFilename: String?
    // For internal use only.
    internal let attachmentType: TSAttachmentType?

    internal init(
        attachmentReferenceType: OWSAttachmentInfoReference,
        thumbnailAttachmentId: String?,
        mimeType: String?,
        sourceFilename: String?,
        attachmentType: TSAttachmentType?
    ) {
        self.attachmentReferenceType = attachmentReferenceType
        self.thumbnailAttachmentId = thumbnailAttachmentId
        self.mimeType = mimeType
        self.sourceFilename = sourceFilename
        self.attachmentType = attachmentType
        super.init()
    }
}

@objc
public class DisplayableQuotedThumbnailAttachment: NSObject {
    public let attachmentType: TSAttachmentType?
    public let thumbnailImage: UIImage?
    public let failedAttachmentPointer: TSAttachmentPointer?

    internal init(
        attachmentType: TSAttachmentType?,
        thumbnailImage: UIImage?,
        failedAttachmentPointer: TSAttachmentPointer?
    ) {
        self.attachmentType = attachmentType
        self.thumbnailImage = thumbnailImage
        self.failedAttachmentPointer = failedAttachmentPointer
    }
}

/// Helper for TSQuotedMessage attachment fetching, creating, copying, etc.
///
/// Used to abstract away differences between v1 and v2 attachment behavior.
@objc
internal protocol QuotedMessageAttachmentHelper: AnyObject {

    @objc
    func thumbnailAttachmentMetadata(
        parentMessage: TSMessage,
        tx: SDSAnyReadTransaction
    ) -> QuotedThumbnailAttachmentMetadata?

    func displayableThumbnailAttachment(
        metadata: QuotedThumbnailAttachmentMetadata,
        parentMessage: TSMessage,
        tx: SDSAnyReadTransaction
    ) -> DisplayableQuotedThumbnailAttachment?

    /// Returns nil if the attachment is already downloaded or should not
    /// be downloaded. The ID is guaranteed to be for an attachment pointer.
    func attachmentPointerIdForDownloading(
        parentMessage: TSMessage,
        tx: SDSAnyReadTransaction
    ) -> OWSAttachmentDownloads.AttachmentId?

    func setDownloadedAttachmentStream(
        attachmentStream: TSAttachmentStream,
        parentMessage: TSMessage,
        tx: SDSAnyWriteTransaction
    )

    /// If the currently referenced quoted attachment is
    /// 1. not a thumbnail
    /// OR
    /// 2. not owned by the quote (for legacy attachments)
    /// creates a new attachment that is a thumbnailed-clone of the original,
    /// updates references to it on the parent message in memory and on disk,
    /// and returns it.
    ///
    /// If there was already a thumbnail attachment stream on the message, returns
    /// it with no changes.
    ///
    /// If the attachment is an undownloaded pointer or could not be cloned as
    /// a thumbnail, returns nil.
    func createThumbnailAndUpdateMessageIfNecessary(
        parentMessage: TSMessage,
        tx: SDSAnyWriteTransaction
    ) -> TSAttachmentStream?
}

@objc
internal class QuotedMessageAttachmentHelperFactory: NSObject {

    private override init() {}

    @objc
    static func helper(for info: OWSAttachmentInfo) -> QuotedMessageAttachmentHelper {
        switch info.attachmentType {
        case .V2:
            return QuotedMessageAttachmentHelperImpl(info)
        case
                .unset,
                .originalForSend,
                .original,
                .thumbnail,
                .untrustedPointer:
            fallthrough
        @unknown default:
            return LegacyQuotedMessageAttachmentHelper(info)
        }
    }
}
