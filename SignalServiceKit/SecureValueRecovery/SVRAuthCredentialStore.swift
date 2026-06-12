//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

protocol SVRAuthCredentialStore {
    func getCredentialData(tx: DBReadTransaction) -> Data?
    func setCredentialData(_ encodedValue: Data?, tx: DBWriteTransaction)
}

struct SVRAuthCredentialCloudStore: SVRAuthCredentialStore {
    private let credentialsKey: String

    init(credentialsKey: String) {
        self.credentialsKey = credentialsKey
    }

    func getCredentialData(tx: DBReadTransaction) -> Data? {
        return NSUbiquitousKeyValueStore.default.data(forKey: self.credentialsKey)
    }

    func setCredentialData(_ encodedValue: Data?, tx: DBWriteTransaction) {
        NSUbiquitousKeyValueStore.default.set(encodedValue, forKey: self.credentialsKey)
    }
}

struct SVRAuthCredentialLocalStore: SVRAuthCredentialStore {
    private let kvStore: KeyValueStore

    init(kvStore: KeyValueStore) {
        self.kvStore = kvStore
    }

    private static let credentialsKey = "credentials"

    func getCredentialData(tx: DBReadTransaction) -> Data? {
        return kvStore.getData(Self.credentialsKey, transaction: tx)
    }

    func setCredentialData(_ encodedValue: Data?, tx: DBWriteTransaction) {
        kvStore.setData(encodedValue, key: Self.credentialsKey, transaction: tx)
    }
}
