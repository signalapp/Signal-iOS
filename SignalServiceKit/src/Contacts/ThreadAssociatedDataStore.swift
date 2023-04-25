//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

protocol ThreadAssociatedDataStore {
    func fetch(for threadUniqueId: String, tx: DBReadTransaction) -> ThreadAssociatedData?
}

class ThreadAssociatedDataStoreImpl: ThreadAssociatedDataStore {
    func fetch(for threadUniqueId: String, tx: DBReadTransaction) -> ThreadAssociatedData? {
        let db = SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database
        do {
            return try ThreadAssociatedData.filter(Column("threadUniqueId") == threadUniqueId).fetchOne(db)
        } catch {
            owsFailDebug("Failed to read thread associated data \(error)")
            return nil
        }
    }
}

extension ThreadAssociatedDataStore {
    func fetchOrDefault(
        for thread: TSThread,
        ignoreMissing: Bool = false,
        tx: DBReadTransaction
    ) -> ThreadAssociatedData {
        fetchOrDefault(for: thread.uniqueId, ignoreMissing: ignoreMissing, tx: tx)
    }

    func fetchOrDefault(
        for threadUniqueId: String,
        ignoreMissing: Bool = false,
        tx: DBReadTransaction
    ) -> ThreadAssociatedData {
        if let result = fetch(for: threadUniqueId, tx: tx) {
            return result
        }
        owsAssertDebug(ignoreMissing, "Unexpectedly missing associated data for thread")
        return ThreadAssociatedData(threadUniqueId: threadUniqueId)
    }
}

#if TESTABLE_BUILD

class MockThreadAssociatedDataStore: ThreadAssociatedDataStore {
    var values = [String: ThreadAssociatedData]()
    func fetch(for threadUniqueId: String, tx: DBReadTransaction) -> ThreadAssociatedData? { values[threadUniqueId] }
}

#endif
