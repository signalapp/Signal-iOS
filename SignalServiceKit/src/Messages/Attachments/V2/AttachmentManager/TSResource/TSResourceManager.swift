//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct TSMessageAttachmentReferenceType: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let bodyAttachment = TSMessageAttachmentReferenceType(rawValue: 1 << 0)
    static let oversizeText = TSMessageAttachmentReferenceType(rawValue: 1 << 1)
    static let linkPreview = TSMessageAttachmentReferenceType(rawValue: 1 << 2)
    static let quotedReply = TSMessageAttachmentReferenceType(rawValue: 1 << 3)
    static let sticker = TSMessageAttachmentReferenceType(rawValue: 1 << 4)
    static let contactAvatar = TSMessageAttachmentReferenceType(rawValue: 1 << 5)

    static let allTypes: TSMessageAttachmentReferenceType = [
        .bodyAttachment,
        .oversizeText,
        .linkPreview,
        .quotedReply,
        .sticker,
        .contactAvatar
    ]
}

public protocol TSResourceManager {

    // MARK: - Protos

    func createBodyAttachmentPointers(
        from protos: [SSKProtoAttachmentPointer],
        message: TSMessage,
        tx: DBWriteTransaction
    )

    func createBodyAttachmentStreams(
        consumingDataSourcesOf unsavedAttachmentInfos: [OutgoingAttachmentInfo],
        message: TSOutgoingMessage,
        tx: DBWriteTransaction
    ) throws

    func buildProtoForSending(
        from reference: TSResourceReference,
        pointer: TSResourcePointer
    ) -> SSKProtoAttachmentPointer?

    // MARK: - Removes and deletes

    func removeBodyAttachment(
        _ attachment: TSResource,
        from message: TSMessage,
        tx: DBWriteTransaction
    )

    /// Deletes references to the attachment(s) from the provided message, potentially
    /// deleting the attachment in the db and on disk if not referenced from anywhere else.
    ///
    /// Does _not_ update the attachment's container; e.g. will not touch the OWSLinkPreview
    /// object on the message to update its attachment identifier reference.
    /// Callsites are assumed to delete the container (e.g. TSMessage.linkPreview)
    /// immediately after calling this method, thus pruning those stale attachment references.
    ///
    /// Strictly speaking, this method _should_ do that pruning, but TSMessage doesn't expose
    /// a setter for these object (rightly so) and the concept is moot in a v2 world since references
    /// are stored separately. So in the meantime we rely on all callsites always deleting them anyway.
    func removeAttachments(
        from message: TSMessage,
        with types: TSMessageAttachmentReferenceType,
        tx: DBWriteTransaction
    )

    // MARK: - Quoted reply thumbnails

    /// If the currently referenced quoted attachment is
    /// [not a thumbnail] OR ([is legacy attachment] AND [not owned by the quote])
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
        quotedMessage: TSQuotedMessage,
        parentMessage: TSMessage,
        tx: DBWriteTransaction
    ) -> TSResourceStream?

    func thumbnailImage(
        thumbnail: TSQuotedMessageResourceReference.Thumbnail,
        attachment: TSResource,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) -> UIImage?
}
