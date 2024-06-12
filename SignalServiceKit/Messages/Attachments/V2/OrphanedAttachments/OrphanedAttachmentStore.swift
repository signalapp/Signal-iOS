//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Wrapper around OrphanedAttachmentRecord table for reads/writes.
public protocol OrphanedAttachmentStore {

    func orphanAttachmentExists(
        with id: OrphanedAttachmentRecord.IDType,
        tx: DBReadTransaction
    ) -> Bool
}

public class OrphanedAttachmentStoreImpl: OrphanedAttachmentStore {

    public init() {}

    public func orphanAttachmentExists(
        with id: OrphanedAttachmentRecord.IDType,
        tx: DBReadTransaction
    ) -> Bool {
        return (try? OrphanedAttachmentRecord.exists(
            SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database,
            key: id
        )) ?? false
    }
}

#if TESTABLE_BUILD

open class MockOrphanedAttachmentStore: OrphanedAttachmentStore {

    public init() {}

    public var ids = [OrphanedAttachmentRecord.IDType]()

    open func orphanAttachmentExists(
        with id: OrphanedAttachmentRecord.IDType,
        tx: DBReadTransaction
    ) -> Bool {
        ids.contains(id)
    }
}

#endif
