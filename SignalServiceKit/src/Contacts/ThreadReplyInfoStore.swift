//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public class ThreadReplyInfoStore {
    private let keyValueStore: KeyValueStore
    init(keyValueStoreFactory: KeyValueStoreFactory) {
        self.keyValueStore = keyValueStoreFactory.keyValueStore(collection: "TSThreadReplyInfo")
    }

    public func fetch(for threadUniqueId: String, tx: DBReadTransaction) -> ThreadReplyInfo? {
        guard let dataValue = keyValueStore.getData(threadUniqueId, transaction: tx) else {
            return nil
        }
        return try? JSONDecoder().decode(ThreadReplyInfo.self, from: dataValue)
    }

    public func save(_ value: ThreadReplyInfo, for threadUniqueId: String, tx: DBWriteTransaction) {
        let dataValue: Data
        do {
            dataValue = try JSONEncoder().encode(value)
        } catch {
            owsFailDebug("Can't encode ThreadReplyInfo")
            return
        }
        keyValueStore.setData(dataValue, key: threadUniqueId, transaction: tx)
    }

    public func remove(for threadUniqueId: String, tx: DBWriteTransaction) {
        keyValueStore.removeValue(forKey: threadUniqueId, transaction: tx)
    }
}
