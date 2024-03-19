//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class TSResourceManagerMock: TSResourceManager {

    public init() {}

    public func createBodyAttachmentPointers(from protos: [SSKProtoAttachmentPointer], message: TSMessage, tx: DBWriteTransaction) {
        // Do nothing
    }

    public func createBodyAttachmentStreams(
        consumingDataSourcesOf unsavedAttachmentInfos: [OutgoingAttachmentInfo],
        message: TSOutgoingMessage,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    public func createAttachmentBuilder(
        from proto: SSKProtoAttachmentPointer,
        tx: DBWriteTransaction
    ) throws -> OwnedAttachmentBuilder<TSResourceRetrievalInfo> {
        return .withoutFinalizer(.legacy(uniqueId: ""))
    }

    public func buildProtoForSending(
        from reference: TSResourceReference,
        pointer: TSResourcePointer
    ) -> SSKProtoAttachmentPointer? {
        return nil
    }

    public func removeBodyAttachment(_ attachment: TSResource, from message: TSMessage, tx: DBWriteTransaction) {
        // Do nothing
    }

    public func removeAttachments(
        from message: TSMessage,
        with types: TSMessageAttachmentReferenceType,
        tx: DBWriteTransaction
    ) {
        // Do nothing
    }

    public func createThumbnailAndUpdateMessageIfNecessary(
        quotedMessage: TSQuotedMessage,
        parentMessage: TSMessage,
        tx: DBWriteTransaction
    ) -> TSResourceStream? {
        return nil
    }

    public func newQuotedReplyMessageThumbnailBuilder(
        originalMessage: TSMessage,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<OWSAttachmentInfo>? {
        return nil
    }

    public func thumbnailImage(
        thumbnail: TSQuotedMessageResourceReference.Thumbnail,
        attachment: TSResource,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) -> UIImage? {
        return nil
    }
}

#endif
