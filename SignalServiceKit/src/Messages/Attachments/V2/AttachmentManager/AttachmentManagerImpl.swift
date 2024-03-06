//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AttachmentManagerImpl: AttachmentManager {

    private let attachmentStore: AttachmentStore

    public init(attachmentStore: AttachmentStore) {
        self.attachmentStore = attachmentStore
    }

    public func createAttachmentPointers(
        from protos: [SSKProtoAttachmentPointer],
        owner: AttachmentReference.OwnerType,
        tx: DBWriteTransaction
    ) {
        fatalError("Unimplemented")
    }

    public func createAttachmentStreams(
        consumingDataSourcesOf unsavedAttachmentInfos: [OutgoingAttachmentInfo],
        owner: AttachmentReference.OwnerType,
        tx: DBWriteTransaction
    ) throws {
        fatalError("Unimplemented")
    }

    public func removeAttachment(
        _ attachment: TSResource,
        from owner: AttachmentReference.OwnerType,
        tx: DBWriteTransaction
    ) {
        fatalError("Unimplemented")
    }

    public func removeAllAttachments(
        from owners: [AttachmentReference.OwnerType],
        tx: DBWriteTransaction
    ) {
        fatalError("Unimplemented")
    }
}
