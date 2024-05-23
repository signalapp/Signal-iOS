//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct DatedAttachmentReferenceId {
    public let id: AttachmentReferenceId
    // timestamp of the owning message.
    public let receivedAtTimestamp: UInt64

    public var date: Date {
        return Date(millisecondsSince1970: receivedAtTimestamp)
    }

    public init(id: AttachmentReferenceId, receivedAtTimestamp: UInt64) {
        self.id = id
        self.receivedAtTimestamp = receivedAtTimestamp
    }
}

extension AttachmentReference {

    var datedId: DatedAttachmentReferenceId {
        let receivedAtTimestamp: UInt64
        switch owner {
        case .message(.bodyAttachment(let metadata)):
            receivedAtTimestamp = metadata.receivedAtTimestamp
        case .message(.oversizeText(let metadata)):
            receivedAtTimestamp = metadata.receivedAtTimestamp
        case .message(.linkPreview(let metadata)):
            receivedAtTimestamp = metadata.receivedAtTimestamp
        case .message(.quotedReply(let metadata)):
            receivedAtTimestamp = metadata.receivedAtTimestamp
        case .message(.sticker(let metadata)):
            receivedAtTimestamp = metadata.receivedAtTimestamp
        case .message(.contactAvatar(let metadata)):
            receivedAtTimestamp = metadata.receivedAtTimestamp
        case .storyMessage, .thread:
            owsFailDebug("Should not be indexing non-message attachments in gallery")
            receivedAtTimestamp = Date().ows_millisecondsSince1970
        }
        return .init(id: self.referenceId, receivedAtTimestamp: receivedAtTimestamp)
    }
}
