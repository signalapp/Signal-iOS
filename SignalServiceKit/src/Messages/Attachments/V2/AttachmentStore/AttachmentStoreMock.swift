//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class AttachmentStoreMock: AttachmentStore {

    public var attachmentReferences = [AttachmentReference]()
    public var attachments = [Attachment]()

    open func fetchReferences(owners: [AttachmentReference.OwnerType], tx: DBReadTransaction) -> [AttachmentReference] {
        return attachmentReferences.filter { ref in
            return owners.contains(ref.owner.type)
        }
    }

    open func fetch(ids: [Attachment.IDType], tx: DBReadTransaction) -> [Attachment] {
        return attachments.filter { attachment in
            return ids.contains(attachment.id)
        }
    }
}

#endif
