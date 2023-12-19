//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol AttachmentStore {

    func anyInsert(
        _ attachment: TSAttachment,
        tx: DBWriteTransaction
    )
}

public class AttachmentStoreImpl: AttachmentStore {

    public init() {}

    public func anyInsert(_ attachment: TSAttachment, tx: DBWriteTransaction) {
        attachment.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }
}

#if TESTABLE_BUILD

open class AttachmentStoreMock: AttachmentStore {

    public init() {}

    public var attachments = [TSAttachment]()

    public func anyInsert(_ attachment: TSAttachment, tx: DBWriteTransaction) {
        self.attachments.append(attachment)
    }
}

#endif
