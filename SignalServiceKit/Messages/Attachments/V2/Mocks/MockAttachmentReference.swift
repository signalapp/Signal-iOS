//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

extension AttachmentReference.ConstructionParams {

    public static func mock(
        owner: AttachmentReference.Owner,
        sourceFilename: String? = UUID().uuidString,
        sourceUnencryptedByteCount: UInt32? = .random(in: 0...100),
        sourceMediaSizePixels: CGSize? = CGSize(width: .random(in: 0...100), height: .random(in: 0...100))
    ) -> AttachmentReference.ConstructionParams {
        return AttachmentReference.ConstructionParams(
            owner: owner,
            sourceFilename: sourceFilename,
            sourceUnencryptedByteCount: sourceUnencryptedByteCount,
            sourceMediaSizePixels: sourceMediaSizePixels
        )
    }

    public static func mockMessageBodyAttachmentReference(
        messageRowId: Int64,
        threadRowId: Int64,
        receivedAtTimestamp: UInt64 = Date().ows_millisecondsSince1970,
        contentType: Attachment.ContentTypeRaw? = .image,
        caption: String? = nil,
        renderingFlag: AttachmentReference.RenderingFlag = .default,
        isViewOnce: Bool = false,
        isPastEditRevision: Bool = false,
        orderInOwner: UInt32 = 0,
        idInOwner: UUID? = nil,
        sourceFilename: String? = UUID().uuidString,
        sourceUnencryptedByteCount: UInt32? = .random(in: 0...100),
        sourceMediaSizePixels: CGSize? = CGSize(width: .random(in: 0...100), height: .random(in: 0...100))
    ) -> AttachmentReference.ConstructionParams {
        return .mock(
            owner: .message(.bodyAttachment(.init(
                messageRowId: messageRowId,
                receivedAtTimestamp: receivedAtTimestamp,
                threadRowId: threadRowId,
                contentType: contentType,
                isPastEditRevision: isPastEditRevision,
                caption: caption,
                renderingFlag: renderingFlag,
                orderInOwner: orderInOwner,
                idInOwner: idInOwner,
                isViewOnce: isViewOnce
            ))),
            sourceFilename: sourceFilename,
            sourceUnencryptedByteCount: sourceUnencryptedByteCount,
            sourceMediaSizePixels: sourceMediaSizePixels
        )
    }
}

#endif
