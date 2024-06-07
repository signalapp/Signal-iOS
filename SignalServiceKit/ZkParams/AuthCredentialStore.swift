//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

class AuthCredentialStore {
    private let callLinkAuthCredentialStore: any KeyValueStore
    private let groupAuthCredentialStore: any KeyValueStore
    private let backupAuthCredentialStore: any KeyValueStore

    init(keyValueStoreFactory: any KeyValueStoreFactory) {
        self.callLinkAuthCredentialStore = keyValueStoreFactory.keyValueStore(collection: "CallLinkAuthCredential")
        self.groupAuthCredentialStore = keyValueStoreFactory.keyValueStore(collection: "GroupsV2Impl.authCredentialStoreStore")
        self.backupAuthCredentialStore = keyValueStoreFactory.keyValueStore(collection: "BackupAuthCredential")
    }

    private static func callLinkAuthCredentialKey(for redemptionTime: UInt64) -> String {
        return "\(redemptionTime)"
    }

    private static func groupAuthCredentialKey(for redemptionTime: UInt64) -> String {
        return "ACWP_\(redemptionTime)"
    }

    private static func backupAuthCredentialKey(for redemptionTime: UInt64) -> String {
        return "\(redemptionTime)"
    }

    func callLinkAuthCredential(
        for redemptionTime: UInt64,
        tx: DBReadTransaction
    ) throws -> LibSignalClient.CallLinkAuthCredential? {
        return try callLinkAuthCredentialStore.getData(
            Self.callLinkAuthCredentialKey(for: redemptionTime),
            transaction: tx
        ).map {
            return try LibSignalClient.CallLinkAuthCredential(contents: [UInt8]($0))
        }
    }

    func setCallLinkAuthCredential(
        _ credential: LibSignalClient.CallLinkAuthCredential,
        for redemptionTime: UInt64,
        tx: DBWriteTransaction
    ) {
        callLinkAuthCredentialStore.setData(
            credential.serialize().asData,
            key: Self.callLinkAuthCredentialKey(for: redemptionTime),
            transaction: tx
        )
    }

    func removeAllCallLinkAuthCredentials(tx: DBWriteTransaction) {
        callLinkAuthCredentialStore.removeAll(transaction: tx)
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

    func backupAuthCredential(
        for redemptionTime: UInt64,
        tx: DBReadTransaction
    ) -> BackupAuthCredential? {
        do {
            return try backupAuthCredentialStore.getData(
                Self.backupAuthCredentialKey(for: redemptionTime),
                transaction: tx
            ).map {
                return try BackupAuthCredential.init(contents: [UInt8]($0))
            }
        } catch {
            Logger.warn("Invalid backup credential format")
            return nil
        }
    }

    func setBackupAuthCredential(
        _ credential: BackupAuthCredential,
        for redemptionTime: UInt64,
        tx: DBWriteTransaction
    ) {
        backupAuthCredentialStore.setData(
            credential.serialize().asData,
            key: Self.backupAuthCredentialKey(for: redemptionTime),
            transaction: tx
        )
    }

    func removeAllBackupAuthCredentials(tx: DBWriteTransaction) {
        backupAuthCredentialStore.removeAll(transaction: tx)
    }
}
