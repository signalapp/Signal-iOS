//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

class AuthCredentialStore {
    private let dateProvider: DateProvider

    private let callLinkAuthCredentialStore: KeyValueStore
    private let groupAuthCredentialStore: KeyValueStore
    private let backupMessagesAuthCredentialStore: KeyValueStore
    private let backupMediaAuthCredentialStore: KeyValueStore
    private let svr🐝AuthCredentialStore: KeyValueStore

    init(dateProvider: @escaping DateProvider) {
        self.dateProvider = dateProvider
        self.callLinkAuthCredentialStore = KeyValueStore(collection: "CallLinkAuthCredential")
        self.groupAuthCredentialStore = KeyValueStore(collection: "GroupsV2Impl.authCredentialStoreStore")
        self.backupMessagesAuthCredentialStore = KeyValueStore(collection: "BackupAuthCredential")
        self.backupMediaAuthCredentialStore = KeyValueStore(collection: "MediaAuthCredential")
        self.svr🐝AuthCredentialStore = KeyValueStore(collection: "SVR🐝AuthCredential")
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

    // MARK: -

    func callLinkAuthCredential(
        for redemptionTime: UInt64,
        tx: DBReadTransaction
    ) throws -> LibSignalClient.CallLinkAuthCredential? {
        return try callLinkAuthCredentialStore.getData(
            Self.callLinkAuthCredentialKey(for: redemptionTime),
            transaction: tx
        ).map {
            return try LibSignalClient.CallLinkAuthCredential(contents: $0)
        }
    }

    func setCallLinkAuthCredential(
        _ credential: LibSignalClient.CallLinkAuthCredential,
        for redemptionTime: UInt64,
        tx: DBWriteTransaction
    ) {
        callLinkAuthCredentialStore.setData(
            credential.serialize(),
            key: Self.callLinkAuthCredentialKey(for: redemptionTime),
            transaction: tx
        )
    }

    func removeAllCallLinkAuthCredentials(tx: DBWriteTransaction) {
        callLinkAuthCredentialStore.removeAll(transaction: tx)
    }

    // MARK: -

    func groupAuthCredential(
        for redemptionTime: UInt64,
        tx: DBReadTransaction
    ) throws -> AuthCredentialWithPni? {
        return try groupAuthCredentialStore.getData(
            Self.groupAuthCredentialKey(for: redemptionTime),
            transaction: tx
        ).map {
            return try AuthCredentialWithPni.init(contents: $0)
        }
    }

    func setGroupAuthCredential(
        _ credential: AuthCredentialWithPni,
        for redemptionTime: UInt64,
        tx: DBWriteTransaction
    ) {
        groupAuthCredentialStore.setData(
            credential.serialize(),
            key: Self.groupAuthCredentialKey(for: redemptionTime),
            transaction: tx
        )
    }

    func removeAllGroupAuthCredentials(tx: DBWriteTransaction) {
        groupAuthCredentialStore.removeAll(transaction: tx)
    }

    // MARK: -

    func backupAuthCredential(
        for credentialType: BackupAuthCredentialType,
        redemptionTime: UInt64,
        tx: DBReadTransaction
    ) -> BackupAuthCredential? {
        let store: KeyValueStore = switch credentialType {
        case .media: backupMediaAuthCredentialStore
        case .messages: backupMessagesAuthCredentialStore
        }

        do {
            return try store.getData(
                Self.backupAuthCredentialKey(for: redemptionTime),
                transaction: tx
            ).map {
                return try BackupAuthCredential.init(contents: $0)
            }
        } catch {
            Logger.warn("Invalid backup credential format")
            return nil
        }
    }

    func setBackupAuthCredential(
        _ credential: BackupAuthCredential,
        for credentialType: BackupAuthCredentialType,
        redemptionTime: UInt64,
        tx: DBWriteTransaction
    ) {
        let store: KeyValueStore = switch credentialType {
        case .media: backupMediaAuthCredentialStore
        case .messages: backupMessagesAuthCredentialStore
        }

        store.setData(
            credential.serialize(),
            key: Self.backupAuthCredentialKey(for: redemptionTime),
            transaction: tx
        )
    }

    static let svr🐝AuthCredentialExpirationTime: TimeInterval = .day - .hour
    static let svr🐝AuthCredentialExpiryDateKey = "svr🐝AuthCredentialTimestampKey"
    static let svr🐝AuthCredentialUsernameKey = "svr🐝AuthCredentialUsernameKey"
    static let svr🐝AuthCredentialPasswordKey = "svr🐝AuthCredentialPasswordKey"

    func svr🐝AuthCredential(tx: DBReadTransaction) -> LibSignalClient.Auth? {
        guard
            let username = svr🐝AuthCredentialStore.getString(Self.svr🐝AuthCredentialUsernameKey, transaction: tx),
            let password = svr🐝AuthCredentialStore.getString(Self.svr🐝AuthCredentialPasswordKey, transaction: tx),
            let expiryDate = svr🐝AuthCredentialStore.getDate(Self.svr🐝AuthCredentialExpiryDateKey, transaction: tx)
        else {
            return nil
        }
        guard expiryDate > dateProvider() else {
            return nil
        }
        return Auth(
            username: username,
            password: password
        )
    }

    func setSvr🐝AuthCredential(
        _ credential: LibSignalClient.Auth?,
        tx: DBWriteTransaction
    ) {
        guard let credential else {
            svr🐝AuthCredentialStore.removeAll(transaction: tx)
            return
        }
        svr🐝AuthCredentialStore.setString(credential.username, key: Self.svr🐝AuthCredentialUsernameKey, transaction: tx)
        svr🐝AuthCredentialStore.setString(credential.password, key: Self.svr🐝AuthCredentialPasswordKey, transaction: tx)
        svr🐝AuthCredentialStore.setDate(
            dateProvider().addingTimeInterval(Self.svr🐝AuthCredentialExpirationTime),
            key: Self.svr🐝AuthCredentialExpiryDateKey,
            transaction: tx
        )
    }

    func removeAllBackupAuthCredentials(ofType credentialType: BackupAuthCredentialType, tx: DBWriteTransaction) {
        let store: KeyValueStore = switch credentialType {
        case .media: backupMediaAuthCredentialStore
        case .messages: backupMessagesAuthCredentialStore
        }

        store.removeAll(transaction: tx)

        switch credentialType {
        case .media:
            break
        case .messages:
            svr🐝AuthCredentialStore.removeAll(transaction: tx)
        }
    }

    func removeAllBackupAuthCredentials(tx: DBWriteTransaction) {
        for credentialType in BackupAuthCredentialType.allCases {
            removeAllBackupAuthCredentials(ofType: credentialType, tx: tx)
        }
    }
}
