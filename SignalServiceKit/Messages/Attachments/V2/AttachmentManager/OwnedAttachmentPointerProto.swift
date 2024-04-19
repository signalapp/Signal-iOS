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
