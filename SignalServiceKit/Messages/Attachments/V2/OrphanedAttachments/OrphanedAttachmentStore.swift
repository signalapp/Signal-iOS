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

    func insert(
        _ record: inout OrphanedAttachmentRecord,
        tx: DBWriteTransaction
    ) throws
}

public class OrphanedAttachmentStoreImpl: OrphanedAttachmentStore {

    public init() {}

    public func orphanAttachmentExists(
        with id: OrphanedAttachmentRecord.IDType,
        tx: DBReadTransaction
    ) -> Bool {
        return (try? OrphanedAttachmentRecord.exists(
            databaseConnection(tx),
            key: id
        )) ?? false
    }

    public func insert(
        _ record: inout OrphanedAttachmentRecord,
        tx: DBWriteTransaction
    ) throws {
        try record.insert(databaseConnection(tx))
    }
}

#if TESTABLE_BUILD

open class MockOrphanedAttachmentStore: OrphanedAttachmentStore {

    public init() {}

    public var nextId: OrphanedAttachmentRecord.IDType = 1
    public var ids = [OrphanedAttachmentRecord.IDType]()

    open func orphanAttachmentExists(
        with id: OrphanedAttachmentRecord.IDType,
        tx: DBReadTransaction
    ) -> Bool {
        ids.contains(id)
    }

    open func insert(
        _ record: inout OrphanedAttachmentRecord,
        tx: DBWriteTransaction
    ) throws {
        ids.append(nextId)
        record.sqliteId = nextId
        nextId += 1
    }
}

#endif
