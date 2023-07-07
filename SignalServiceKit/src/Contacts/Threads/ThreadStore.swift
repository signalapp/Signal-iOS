//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

protocol ThreadStore {
    func fetchThread(uniqueId: String, tx: DBReadTransaction) -> TSThread?
    func fetchContactThreads(serviceId: ServiceId, tx: DBReadTransaction) -> [TSContactThread]
    func fetchContactThreads(phoneNumber: String, tx: DBReadTransaction) -> [TSContactThread]
    func removeThread(_ thread: TSThread, tx: DBWriteTransaction)
    func updateThread(_ thread: TSThread, tx: DBWriteTransaction)
}

extension ThreadStore {
    func fetchGroupThread(uniqueId: String, tx: DBReadTransaction) -> TSGroupThread? {
        guard let thread = fetchThread(uniqueId: uniqueId, tx: tx) else {
            return nil
        }
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Object has unexpected type: \(type(of: thread))")
            return nil
        }
        return groupThread
    }

    func fetchThread(serviceId: ServiceId, tx: DBReadTransaction) -> TSContactThread? {
        return fetchContactThreads(serviceId: serviceId, tx: tx).first
    }
}

class ThreadStoreImpl: ThreadStore {
    func fetchThread(uniqueId: String, tx: DBReadTransaction) -> TSThread? {
        TSThread.anyFetch(uniqueId: uniqueId, transaction: SDSDB.shimOnlyBridge(tx))
    }

    func fetchContactThreads(serviceId: ServiceId, tx: DBReadTransaction) -> [TSContactThread] {
        AnyContactThreadFinder().contactThreads(for: serviceId, tx: SDSDB.shimOnlyBridge(tx))
    }

    func fetchContactThreads(phoneNumber: String, tx: DBReadTransaction) -> [TSContactThread] {
        AnyContactThreadFinder().contactThreads(for: phoneNumber, tx: SDSDB.shimOnlyBridge(tx))
    }

    func removeThread(_ thread: TSThread, tx: DBWriteTransaction) {
        let tx = SDSDB.shimOnlyBridge(tx)

        // TODO: If we ever use transaction finalizations for more than
        // de-bouncing thread touches, we should promote this to TSYapDatabaseObject
        // (or at least include it in the "will remove" hook for any relevant models.
        tx.addRemovedFinalizationKey(thread.transactionFinalizationKey)

        let sql = "DELETE FROM \(thread.sdsTableName) WHERE uniqueId = ?"
        tx.unwrapGrdbWrite.executeAndCacheStatement(sql: sql, arguments: [thread.uniqueId])
    }

    func updateThread(_ thread: TSThread, tx: DBWriteTransaction) {
        thread.anyOverwritingUpdate(transaction: SDSDB.shimOnlyBridge(tx))
    }
}

#if TESTABLE_BUILD

class MockThreadStore: ThreadStore {
    var threads = [TSThread]()

    func fetchThread(uniqueId: String, tx: DBReadTransaction) -> TSThread? {
        threads.first(where: { $0.uniqueId == uniqueId })
    }

    func fetchContactThreads(serviceId: ServiceId, tx: DBReadTransaction) -> [TSContactThread] {
        threads.lazy.compactMap { $0 as? TSContactThread }.filter { ServiceId(uuidString: $0.contactUUID) == serviceId }
    }

    func fetchContactThreads(phoneNumber: String, tx: DBReadTransaction) -> [TSContactThread] {
        threads.lazy.compactMap { $0 as? TSContactThread }.filter { $0.contactPhoneNumber == phoneNumber }
    }

    func removeThread(_ thread: TSThread, tx: DBWriteTransaction) {
        threads.removeAll(where: { $0.uniqueId == thread.uniqueId })
    }

    func updateThread(_ thread: TSThread, tx: DBWriteTransaction) {
        let threadIndex = threads.firstIndex(where: { $0.uniqueId == thread.uniqueId })!
        threads[threadIndex] = thread
    }
}

#endif
