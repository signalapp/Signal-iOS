//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

protocol ThreadStore {
    func fetchThread(uniqueId: String, tx: DBReadTransaction) -> TSThread?
    func fetchThread(serviceId: ServiceId, tx: DBReadTransaction) -> TSContactThread?
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
}

class ThreadStoreImpl: ThreadStore {
    func fetchThread(uniqueId: String, tx: DBReadTransaction) -> TSThread? {
        TSThread.anyFetch(uniqueId: uniqueId, transaction: SDSDB.shimOnlyBridge(tx))
    }

    func fetchThread(serviceId: ServiceId, tx: DBReadTransaction) -> TSContactThread? {
        TSContactThread.getWithContactAddress(SignalServiceAddress(serviceId), transaction: SDSDB.shimOnlyBridge(tx))
    }
}

#if TESTABLE_BUILD

class MockThreadStore: ThreadStore {
    var threads = [TSThread]()

    func fetchThread(uniqueId: String, tx: DBReadTransaction) -> TSThread? {
        threads.first(where: { $0.uniqueId == uniqueId })
    }

    func fetchThread(serviceId: ServiceId, tx: DBReadTransaction) -> TSContactThread? {
        threads.lazy.compactMap({ $0 as? TSContactThread }).first(where: { ServiceId(uuidString: $0.contactUUID) == serviceId })
    }
}

#endif
