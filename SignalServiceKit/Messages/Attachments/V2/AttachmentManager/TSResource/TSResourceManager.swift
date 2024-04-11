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

    // MARK: - Creating Attachments from source

    // MARK: Body Attachments (special treatment)

    func createOversizeTextAttachmentPointer(
        from proto: SSKProtoAttachmentPointer,
        message: TSMessage,
        tx: DBWriteTransaction
    ) throws

    func createBodyAttachmentPointers(
        from protos: [SSKProtoAttachmentPointer],
        message: TSMessage,
        tx: DBWriteTransaction
    ) throws

    func createOversizeTextAttachmentStream(
        consuming dataSource: DataSource,
        message: TSMessage,
        tx: DBWriteTransaction
    ) throws

    func createBodyMediaAttachmentStreams(
        consuming dataSources: [TSResourceDataSource],
        message: TSMessage,
        tx: DBWriteTransaction
    ) throws

    // MARK: Other Attachments

    /// Given an attachment proto from its sender,
    /// returns a builder for creating the attachment stream.
    ///
    /// The attachment info needed to construct the owner
    /// is available immediately, but the caller _must_ finalize
    /// the builder to guarantee the attachment is created.
    ///
    /// Legacy attachments are created synchronously,
    /// v2 attachments are created at finalization time.
    /// Callers should only assume the attachment (if any) exists
    /// after finalizing.
    ///
    /// Throws an error if the provided proto is invalid.
    func createAttachmentPointerBuilder(
        from proto: SSKProtoAttachmentPointer,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<TSResourceRetrievalInfo>

    /// Given locally sourced attachmentData,
    /// returns a builder for creating the attachment stream.
    ///
    /// The attachment info needed to construct the owner
    /// is available immediately, but the caller _must_ finalize
    /// the builder to guarantee the attachment is created.
    ///
    /// Legacy attachments are created synchronously,
    /// v2 attachments are created at finalization time.
    /// Callers should only assume the attachment (if any) exists
    /// after finalizing.
    ///
    /// Throws an error if the provided data/mimeType is invalid.
    func createAttachmentStreamBuilder(
        from dataSource: TSResourceDataSource,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<TSResourceRetrievalInfo>

    // MARK: - Outgoing Proto Creation

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

    /// Deletes references to the attachment(s) from the provided StoryMessage, potentially
    /// deleting the attachment in the db and on disk if not referenced from anywhere else.
    ///
    /// Does _not_ update the story message.
    func removeAttachments(
        from storyMessage: StoryMessage,
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

    /// Given an original message available locally, reurns a builder
    /// for creating a thumbnail attachment for quoted replies.
    ///
    /// If the original lacks an attachment, returns nil. If the original has an
    /// attachment that can't be thumbnailed, returns an appropriate
    /// info without creating a new attachment.
    ///
    /// The attachment info needed to construct the reply message
    /// is available immediately, but the caller _must_ finalize
    /// the builder to guarantee the attachment is created.
    ///
    /// Legacy attachments are created synchronously,
    /// v2 attachments are created at finalization time.
    /// Callers should only assume the attachment (if any) exists
    /// after finalizing.
    func newQuotedReplyMessageThumbnailBuilder(
        originalMessage: TSMessage,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<OWSAttachmentInfo>?

    func thumbnailImage(
        attachment: TSResource,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) -> UIImage?
}
