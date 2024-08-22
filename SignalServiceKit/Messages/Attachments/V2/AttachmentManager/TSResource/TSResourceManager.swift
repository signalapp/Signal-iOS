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

public enum TSResourceOwnerType {
    case message
    case story
    case thread
}

public protocol TSResourceManager {

    // MARK: - Migration

    /// True after we have finished migrating _all_ TSAttachments to v2 Attachments.
    ///
    /// Once this is true, no TSAttachments exist on disk and never will exist again.
    /// It is therefore safe to remove the TSAttachment table as well as attachment unique id
    /// fields everywhere they are referenced from legacy owners.
    ///
    /// More relevantly, and the reason this is exposed at runtime, it means _at runtime_ it is
    /// safe to start using the AttachmentReferences table instead of the MediaGalleryRecord
    /// table to drive the media gallery.
    func didFinishTSAttachmentToAttachmentMigration(tx: DBReadTransaction) -> Bool

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
        consuming dataSource: OversizeTextDataSource,
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
        ownerType: TSResourceOwnerType,
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
    ) throws

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
    ) throws

    /// Deletes references to the attachment(s) from the provided StoryMessage, potentially
    /// deleting the attachment in the db and on disk if not referenced from anywhere else.
    ///
    /// Does _not_ update the story message.
    func removeAttachments(
        from storyMessage: StoryMessage,
        tx: DBWriteTransaction
    ) throws

    // MARK: - Edits

    /// Marks a pointer as undownloaded and pending manual download.
    /// For v2 attachments, this does nothing, as its the default state of affairs.
    func markPointerAsPendingManualDownload(
        _ pointer: TSResourcePointer,
        tx: DBWriteTransaction
    )

    // MARK: - Quoted reply thumbnails

    /// Given a data source for the thumbnail, returns a builder for creating
    /// a thumbnail attachment for quoted replies.
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
        from dataSource: QuotedReplyTSResourceDataSource,
        fallbackQuoteProto: SSKProtoDataMessageQuote?,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<QuotedAttachmentInfo>?

    func thumbnailImage(
        attachment: TSResource,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) -> UIImage?
}

extension TSResourceManager {

    public func newQuotedReplyMessageThumbnailBuilder(
        originalAttachment: TSResource,
        originalReference: TSResourceReference,
        fallbackQuoteProto: SSKProtoDataMessageQuote,
        originalMessageRowId: Int64,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<QuotedAttachmentInfo>? {
        switch (originalReference.concreteType, originalAttachment.concreteType) {

        case (.legacy(_), .legacy(let tsAttachment)):
            return self.newQuotedReplyMessageThumbnailBuilder(
                from: .fromLegacyOriginalAttachment(tsAttachment, originalMessageRowId: originalMessageRowId),
                fallbackQuoteProto: fallbackQuoteProto,
                tx: tx
            )
        case (.v2(let attachmentReference), .v2(let attachment)):
            return self.newQuotedReplyMessageThumbnailBuilder(
                from: QuotedReplyAttachmentDataSource.fromOriginalAttachment(
                    attachment,
                    originalReference: attachmentReference,
                    thumbnailPointerFromSender: fallbackQuoteProto.attachments.first?.thumbnail
                ).tsDataSource,
                fallbackQuoteProto: fallbackQuoteProto,
                tx: tx
            )

        case (.v2, .legacy), (.legacy, .v2):
            owsFailDebug("Invalid combination!")
            return nil
        }
    }
}
