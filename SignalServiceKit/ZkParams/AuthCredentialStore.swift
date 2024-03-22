//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

class AuthCredentialStore {
    private let groupAuthCredentialStore: any KeyValueStore

    init(keyValueStoreFactory: any KeyValueStoreFactory) {
        self.groupAuthCredentialStore = keyValueStoreFactory.keyValueStore(collection: "GroupsV2Impl.authCredentialStoreStore")
    }

    private static func groupAuthCredentialKey(for redemptionTime: UInt64) -> String {
        return "ACWP_\(redemptionTime)"
    }

    func groupAuthCredential(
        for redemptionTime: UInt64,
        tx: DBReadTransaction
    ) throws -> AuthCredentialWithPni? {
        return try groupAuthCredentialStore.getData(
            Self.groupAuthCredentialKey(for: redemptionTime),
            transaction: tx
        ).map {
            return try AuthCredentialWithPni.init(contents: [UInt8]($0))
        }
    }

    func setGroupAuthCredential(
        _ credential: AuthCredentialWithPni,
        for redemptionTime: UInt64,
        tx: DBWriteTransaction
    ) {
        groupAuthCredentialStore.setData(
            credential.serialize().asData,
            key: Self.groupAuthCredentialKey(for: redemptionTime),
            transaction: tx
        )
    }

    func removeAllGroupAuthCredentials(tx: DBWriteTransaction) {
        groupAuthCredentialStore.removeAll(transaction: tx)
    }
}
