//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct OwnedAttachmentPointerProto {
    public let proto: SSKProtoAttachmentPointer
    public let owner: AttachmentReference.OwnerBuilder

    public init(proto: SSKProtoAttachmentPointer, owner: AttachmentReference.OwnerBuilder) {
        self.proto = proto
        self.owner = owner
    }
}

public struct OwnedAttachmentBackupPointerProto {
    public enum CreationError: Error {
        case dbInsertionError(Error)
    }

    public let proto: BackupProto_FilePointer
    public let renderingFlag: AttachmentReference.RenderingFlag
    public let clientUUID: UUID?
    public let owner: AttachmentReference.OwnerBuilder

    public init(
        proto: BackupProto_FilePointer,
        renderingFlag: AttachmentReference.RenderingFlag,
        clientUUID: UUID?,
        owner: AttachmentReference.OwnerBuilder,
    ) {
        self.proto = proto
        self.renderingFlag = renderingFlag
        self.clientUUID = clientUUID
        self.owner = owner
    }

    /// The `receivedAt` timestamp of the owning message, or `nil` if the owner
    /// is not a message.
    public var owningMessageReceivedAtTimestamp: UInt64? {
        switch owner {
        case .messageBodyAttachment(let messageBodyAttachmentBuilder):
            return messageBodyAttachmentBuilder.receivedAtTimestamp
        case .messageOversizeText(let messageAttachmentBuilder):
            return messageAttachmentBuilder.receivedAtTimestamp
        case .messageLinkPreview(let messageAttachmentBuilder):
            return messageAttachmentBuilder.receivedAtTimestamp
        case .quotedReplyAttachment(let messageAttachmentBuilder):
            return messageAttachmentBuilder.receivedAtTimestamp
        case .messageSticker(let messageStickerBuilder):
            return messageStickerBuilder.receivedAtTimestamp
        case .messageContactAvatar(let messageAttachmentBuilder):
            return messageAttachmentBuilder.receivedAtTimestamp
        case .threadWallpaperImage, .globalThreadWallpaperImage:
            return nil
        case .storyMessageMedia, .storyMessageLinkPreview:
            owsFailDebug("Backups never contain Stories file pointers!")
            return nil
        }
    }
}
