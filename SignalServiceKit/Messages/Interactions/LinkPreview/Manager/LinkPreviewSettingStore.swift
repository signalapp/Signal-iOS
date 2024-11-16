//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class LinkPreviewSettingStore {
    private enum Constants {
        static let areLinkPreviewsEnabledKey = "areLinkPreviewsEnabled"
    }

    private let keyValueStore: KeyValueStore

    init(keyValueStore: KeyValueStore) {
        self.keyValueStore = keyValueStore
    }

    public func areLinkPreviewsEnabled(tx: DBReadTransaction) -> Bool {
        return keyValueStore.getBool(Constants.areLinkPreviewsEnabledKey, defaultValue: true, transaction: tx)
    }

    func setAreLinkPreviewsEnabled(_ newValue: Bool, tx: DBWriteTransaction) {
        keyValueStore.setBool(newValue, key: Constants.areLinkPreviewsEnabledKey, transaction: tx)
    }

    #if TESTABLE_BUILD
    static func mock() -> LinkPreviewSettingStore {
        return LinkPreviewSettingStore(keyValueStore: KeyValueStore(collection: "blorp"))
    }
    #endif
}
