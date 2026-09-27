//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class AuthCredentialStore {
    private let callLinkAuthCredentialStore: NewKeyValueStore
    private let groupAuthCredentialStore: NewKeyValueStore
    private let backupMessagesAuthCredentialStore: NewKeyValueStore
    private let backupMediaAuthCredentialStore: NewKeyValueStore

    public init() {
        self.callLinkAuthCredentialStore = NewKeyValueStore(collection: "CallLinkAuthCredentialV2")
        self.groupAuthCredentialStore = NewKeyValueStore(collection: "GroupsV2Impl.authCredentialStoreStore")
        self.backupMessagesAuthCredentialStore = NewKeyValueStore(collection: "BackupAuthCredential")
        self.backupMediaAuthCredentialStore = NewKeyValueStore(collection: "MediaAuthCredential")
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
        tx: DBReadTransaction,
    ) throws -> LibSignalClient.CallLinkAuthCredential? {
        return try callLinkAuthCredentialStore.fetchValue(
            Data.self,
            forKey: Self.callLinkAuthCredentialKey(for: redemptionTime),
            tx: tx,
        ).map {
            return try LibSignalClient.CallLinkAuthCredential(contents: $0)
        }
    }

    func setCallLinkAuthCredential(
        _ credential: LibSignalClient.CallLinkAuthCredential,
        for redemptionTime: UInt64,
        tx: DBWriteTransaction,
    ) {
        callLinkAuthCredentialStore.writeValue(
            credential.serialize(),
            forKey: Self.callLinkAuthCredentialKey(for: redemptionTime),
            tx: tx,
        )
    }

    func removeAllCallLinkAuthCredentials(tx: DBWriteTransaction) {
        callLinkAuthCredentialStore.removeAll(tx: tx)
    }

    // MARK: -

    func groupAuthCredential(
        for redemptionTime: UInt64,
        tx: DBReadTransaction,
    ) throws -> AuthCredentialWithPni? {
        return try groupAuthCredentialStore.fetchValue(
            Data.self,
            forKey: Self.groupAuthCredentialKey(for: redemptionTime),
            tx: tx,
        ).map {
            return try AuthCredentialWithPni(contents: $0)
        }
    }

    func setGroupAuthCredential(
        _ credential: AuthCredentialWithPni,
        for redemptionTime: UInt64,
        tx: DBWriteTransaction,
    ) {
        groupAuthCredentialStore.writeValue(
            credential.serialize(),
            forKey: Self.groupAuthCredentialKey(for: redemptionTime),
            tx: tx,
        )
    }

    func removeAllGroupAuthCredentials(tx: DBWriteTransaction) {
        groupAuthCredentialStore.removeAll(tx: tx)
    }

    // MARK: -

    func backupAuthCredential(
        for credentialType: BackupAuthCredentialType,
        redemptionTime: UInt64,
        tx: DBReadTransaction,
    ) -> BackupAuthCredential? {
        let store: NewKeyValueStore = switch credentialType {
        case .media: backupMediaAuthCredentialStore
        case .messages: backupMessagesAuthCredentialStore
        }

        do {
            return try store.fetchValue(
                Data.self,
                forKey: Self.backupAuthCredentialKey(for: redemptionTime),
                tx: tx,
            ).map {
                return try BackupAuthCredential(contents: $0)
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
        tx: DBWriteTransaction,
    ) {
        let store: NewKeyValueStore = switch credentialType {
        case .media: backupMediaAuthCredentialStore
        case .messages: backupMessagesAuthCredentialStore
        }

        store.writeValue(
            credential.serialize(),
            forKey: Self.backupAuthCredentialKey(for: redemptionTime),
            tx: tx,
        )
    }

    func removeAllBackupAuthCredentials(ofType credentialType: BackupAuthCredentialType, tx: DBWriteTransaction) {
        let store: NewKeyValueStore = switch credentialType {
        case .media: backupMediaAuthCredentialStore
        case .messages: backupMessagesAuthCredentialStore
        }

        store.removeAll(tx: tx)
    }

    public func removeAllBackupAuthCredentials(tx: DBWriteTransaction) {
        for credentialType in BackupAuthCredentialType.allCases {
            removeAllBackupAuthCredentials(ofType: credentialType, tx: tx)
        }
    }
}
