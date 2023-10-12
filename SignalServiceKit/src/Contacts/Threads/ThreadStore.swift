//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit

protocol ThreadStore {
    func fetchThread(rowId threadRowId: Int64, tx: DBReadTransaction) -> TSThread?
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

    /// Fetch a contact thread for the given recipient.
    ///
    /// There may be multiple threads for a given service ID, but there is only
    /// one canonical thread for a recipient. This gets that thread.
    ///
    /// If you simply want a thread, and don't want to think about thread
    /// merges, ACIs, PNIs, etc. – this is the method for you.
    func fetchContactThread(recipient: SignalRecipient, tx: DBReadTransaction) -> TSContactThread? {
        return UniqueRecipientObjectMerger.fetchAndExpunge(
            for: recipient,
            serviceIdField: \.contactUUID,
            phoneNumberField: \.contactPhoneNumber,
            uniqueIdField: \.uniqueId,
            fetchObjectsForServiceId: { fetchContactThreads(serviceId: $0, tx: tx) },
            fetchObjectsForPhoneNumber: { fetchContactThreads(phoneNumber: $0.stringValue, tx: tx) },
            updateObject: { _ in }
        ).first
    }
}

class ThreadStoreImpl: ThreadStore {
    func fetchThread(rowId threadRowId: Int64, tx: DBReadTransaction) -> TSThread? {
        return ThreadFinder().fetch(rowId: threadRowId, tx: SDSDB.shimOnlyBridge(tx))
    }

    func fetchThread(uniqueId: String, tx: DBReadTransaction) -> TSThread? {
        TSThread.anyFetch(uniqueId: uniqueId, transaction: SDSDB.shimOnlyBridge(tx))
    }

    func fetchContactThreads(serviceId: ServiceId, tx: DBReadTransaction) -> [TSContactThread] {
        ContactThreadFinder().contactThreads(for: serviceId, tx: SDSDB.shimOnlyBridge(tx))
    }

    func fetchContactThreads(phoneNumber: String, tx: DBReadTransaction) -> [TSContactThread] {
        ContactThreadFinder().contactThreads(for: phoneNumber, tx: SDSDB.shimOnlyBridge(tx))
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

    func fetchThread(rowId threadRowId: Int64, tx: DBReadTransaction) -> TSThread? {
        threads.first(where: { $0.grdbId?.int64Value == threadRowId })
    }

    func fetchThread(uniqueId: String, tx: DBReadTransaction) -> TSThread? {
        threads.first(where: { $0.uniqueId == uniqueId })
    }

    func fetchContactThreads(serviceId: ServiceId, tx: DBReadTransaction) -> [TSContactThread] {
        threads.lazy.compactMap { $0 as? TSContactThread }
            .filter { contactThread in
                guard
                    let contactServiceIdString = contactThread.contactUUID,
                    let contactServiceId = try? ServiceId.parseFrom(serviceIdString: contactServiceIdString)
                else {
                    return false
                }

                return contactServiceId == serviceId
            }
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
