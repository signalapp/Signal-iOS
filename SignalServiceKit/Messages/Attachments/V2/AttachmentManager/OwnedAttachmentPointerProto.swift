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
    public let proto: BackupProto_FilePointer
    public let renderingFlag: AttachmentReference.RenderingFlag
    public let clientUUID: UUID?
    public let owner: AttachmentReference.OwnerBuilder

    public init(
        proto: BackupProto_FilePointer,
        renderingFlag: AttachmentReference.RenderingFlag,
        clientUUID: UUID?,
        owner: AttachmentReference.OwnerBuilder
    ) {
        self.proto = proto
        self.renderingFlag = renderingFlag
        self.clientUUID = clientUUID
        self.owner = owner
    }

    public enum CreationError: Error {
        case missingTransitCdnKey
        case missingMediaName
        case missingEncryptionKey
        case missingDigest
        case dbInsertionError(Error)
    }
}
