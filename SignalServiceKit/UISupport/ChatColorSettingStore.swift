//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Stores the `ChatColorSetting` for each thread and the global scope. The
/// setting may be a pointer to a `CustomChatColor`.
///
/// The keys in this store are thread unique ids _OR_ "defaultKey". The
/// values are either `PaletteChatColor.rawValue` or `CustomChatColor.Key`.
public class ChatColorSettingStore {
    private let settingStore: KeyValueStore

    public init(keyValueStoreFactory: KeyValueStoreFactory) {
        self.settingStore = keyValueStoreFactory.keyValueStore(collection: "chatColorSettingStore")
    }

    public func fetchAllScopeKeys(tx: DBReadTransaction) -> [String] {
        return settingStore.allKeys(transaction: tx)
    }

    public func fetchRawSetting(for scopeKey: String, tx: DBReadTransaction) -> String? {
        return settingStore.getString(scopeKey, transaction: tx)
    }

    public func setRawSetting(_ rawValue: String?, for scopeKey: String, tx: DBWriteTransaction) {
        settingStore.setString(rawValue, key: scopeKey, transaction: tx)
    }

    public func resetAllSettings(tx: DBWriteTransaction) {
        settingStore.removeAll(transaction: tx)
    }
}
