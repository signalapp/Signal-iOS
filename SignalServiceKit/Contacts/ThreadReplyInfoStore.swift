//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class ThreadReplyInfoStore {
    private let keyValueStore: NewKeyValueStore
    init() {
        self.keyValueStore = NewKeyValueStore(collection: "TSThreadReplyInfo")
    }

    public func fetch(for threadUniqueId: String, tx: DBReadTransaction) -> ThreadReplyInfo? {
        guard let dataValue = keyValueStore.fetchValue(Data.self, forKey: threadUniqueId, tx: tx) else {
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
        keyValueStore.writeValue(dataValue, forKey: threadUniqueId, tx: tx)
    }

    public func remove(for threadUniqueId: String, tx: DBWriteTransaction) {
        keyValueStore.removeValue(forKey: threadUniqueId, tx: tx)
    }
}
