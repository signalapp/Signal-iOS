//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class SVRAuthCredentialStorageImpl: SVRAuthCredentialStorage {

    private let keyValueStoreFactory: KeyValueStoreFactory

    public init(
        keyValueStoreFactory: KeyValueStoreFactory
    ) {
        self.keyValueStoreFactory = keyValueStoreFactory
    }

    // MARK: SVR2

    public func storeAuthCredentialForCurrentUsername(_ credential: SVR2AuthCredential, _ transaction: DBWriteTransaction) {
        let credential = AuthCredential.from(credential)
        updateCredentials(for: .svr2, transaction) {
            // Sorting is handled by updateCredentials
            $0.append(credential)
        }
        setCurrentUsername(credential.username, for: .svr2, transaction)
    }

    public func getAuthCredentials(_ transaction: DBReadTransaction) -> [SVR2AuthCredential] {
        return consolidateLocalAndiCloud(for: .svr2, transaction).map { $0.toSVR2Credential() }
    }

    public func getAuthCredentialForCurrentUser(_ transaction: DBReadTransaction) -> SVR2AuthCredential? {
        return consolidateLocalAndiCloud(for: .svr2, transaction).first(where: {
            return $0.username == currentUsername(for: .svr2, transaction)
        })?.toSVR2Credential()
    }

    public func deleteInvalidCredentials(_ invalidCredentials: [SVR2AuthCredential], _ transaction: DBWriteTransaction) {
        updateCredentials(for: .svr2, transaction) {
            $0.removeAll(where: { existingCredential in
                invalidCredentials.contains(where: { invalidCredential in
                    existingCredential.isEqual(to: invalidCredential)
                })
            })
        }
    }

    // MARK: - KBS (SVR1)

    public func storeAuthCredentialForCurrentUsername(_ credential: KBSAuthCredential, _ transaction: DBWriteTransaction) {
        let credential = AuthCredential.from(credential)
        updateCredentials(for: .kbs, transaction) {
            // Sorting is handled by updateCredentials
            $0.append(credential)
        }
        setCurrentUsername(credential.username, for: .kbs, transaction)
    }

    public func getAuthCredentials(_ transaction: DBReadTransaction) -> [KBSAuthCredential] {
        return consolidateLocalAndiCloud(for: .kbs, transaction).map { $0.toKBSCredential() }
    }

    public func getAuthCredentialForCurrentUser(_ transaction: DBReadTransaction) -> KBSAuthCredential? {
        return consolidateLocalAndiCloud(for: .kbs, transaction).first(where: {
            return $0.username == currentUsername(for: .kbs, transaction)
        })?.toKBSCredential()
    }

    public func deleteInvalidCredentials(_ invalidCredentials: [KBSAuthCredential], _ transaction: DBWriteTransaction) {
        updateCredentials(for: .kbs, transaction) {
            $0.removeAll(where: { existingCredential in
                invalidCredentials.contains(where: { invalidCredential in
                    existingCredential.isEqual(to: invalidCredential)
                })
            })
        }
    }

    // MARK: - Local Storage

    // Also write any KBS auth credentials we know about to local, encrypted database storage,
    // so we can reuse them locally even if iCloud is disabled or fails for any reason.

    private var kvStores = [CredentialType: KeyValueStore]()

    private func kvStore(for type: CredentialType) -> KeyValueStore {
        if let existing = kvStores[type] {
            return existing
        }
        let new = keyValueStoreFactory.keyValueStore(collection: type.kvStoreCollectionName)
        kvStores[type] = new
        return new
    }

    private static let usernameKey = "username"

    private func currentUsername(
        for type: CredentialType,
        _ transaction: DBReadTransaction
    ) -> String? {
        return kvStore(for: type).getString(Self.usernameKey, transaction: transaction)
    }

    private func setCurrentUsername(_ newValue: String?, for type: CredentialType, _ transaction: DBWriteTransaction) {
        kvStore(for: type).setString(newValue, key: Self.usernameKey, transaction: transaction)
    }

    private static let localCredentialsKey = "credentials"

    private func localCredentials(for type: CredentialType, _ transaction: DBReadTransaction) -> [AuthCredential] {
        guard let rawData = kvStore(for: type).getData(Self.localCredentialsKey, transaction: transaction) else {
            return []
        }
        let decoder = JSONDecoder()
        guard let credentials = try? decoder.decode([AuthCredential].self, from: rawData) else {
            owsFailBeta("Unable to decode kbs auth credential(s)")
            return []
        }
        return credentials
    }

    private func setLocalCredentials(_ newValue: [AuthCredential], for type: CredentialType, _ transaction: DBWriteTransaction) {
        let encoder = JSONEncoder()
        guard let encoded = try? encoder.encode(newValue) else {
            owsFailBeta("Unable to encode kbs auth credential(s)")
            return
        }
        kvStore(for: type).setData(encoded, key: Self.localCredentialsKey, transaction: transaction)
    }

    // MARK: - iCloud Re-registration Support

    // We write KBS auth credentials we know about to iCloud's key value store to be synced
    // between a user's devices. (encrypted, as per apple's documentation)
    // Having this credential lets us skip phone number verification during registation,
    // for example if the user loses their phone and gets a new one and re-registers with the same number.

    // The user still **MUST** know their PIN to access their account data (and to get in at all, if
    // reglock is enabled). The credential on its own does not grant any account information;
    // only the ability to make PIN guesses.
    // Normally, phone number verification (SMS code) is required to fetch one of these
    // credentials first, before proceeding to attempt to enter the PIN code.

    private func getiCloudCredentials(for type: CredentialType) -> [AuthCredential] {
        guard let rawData = NSUbiquitousKeyValueStore.default.data(forKey: type.iCloudCredentialsKey) else {
            return []
        }
        let decoder = JSONDecoder()
        guard let credentials = try? decoder.decode([AuthCredential].self, from: rawData) else {
            owsFailBeta("Unable to decode kbs auth credential(s) from iCloud")
            return []
        }
        return credentials
    }

    private func setiCloudCredentials(_ newValue: [AuthCredential], for type: CredentialType) {
        let encoder = JSONEncoder()
        guard let encoded = try? encoder.encode(newValue) else {
            owsFailBeta("Unable to encode kbs auth credential(s) to iCloud")
            return
        }
        NSUbiquitousKeyValueStore.default.set(encoded, forKey: type.iCloudCredentialsKey)
    }

    // MARK: - Helpers

    private func updateCredentials(
        for type: CredentialType,
        _ transaction: DBWriteTransaction,
        _ block: (inout [AuthCredential]) -> Void
    ) {
        var credentials = consolidateLocalAndiCloud(for: type, transaction)
        block(&credentials)
        setLocalCredentials(credentials, for: type, transaction)
        // Consolidate again so that we sort and truncate.
        credentials = consolidateLocalAndiCloud(for: type, transaction)
        setLocalCredentials(credentials, for: type, transaction)
        setiCloudCredentials(credentials, for: type)
    }

    private func consolidateLocalAndiCloud(for type: CredentialType, _ transaction: DBReadTransaction) -> [AuthCredential] {
        return Self.consolidateCredentials(
            allUnsortedCredentials: localCredentials(for: type, transaction) + getiCloudCredentials(for: type)
        )
    }

    // Exposed for testing.
    internal static func consolidateCredentials(
        allUnsortedCredentials: [AuthCredential]
    ) -> [AuthCredential] {
        let groupedByUsername = Dictionary(grouping: allUnsortedCredentials, by: \.username).values

        let sort: (AuthCredential, AuthCredential) -> Bool = {
            // newer ones first
            return $0.insertionTime > $1.insertionTime
        }

        // The size limit is small; just merge and sort even though
        // this could be done in O(n).
        let consolidated =
        groupedByUsername.compactMap {
            // First group by password; two with the same password are identical
            // and we should use the *oldest* one so we don't update the timestamp
            // if it is re-inserted.
            return Dictionary(grouping: $0, by: \.password)
                .values
                .compactMap {
                    // max when sorted newest to oldest = oldest
                    return $0.max(by: sort)
                }
            // min when sorted newest to oldest = newest
                .min(by: sort)
        }
        // Sort by time, which is set locally and subject to
        // clock shenanigans, but this is all best effort anyway.
        .sorted(by: sort)
        // Take the first N up to the limit
        .prefix(SVR.maxSVRAuthCredentialsBackedUp)
        return Array(consolidated)
    }

    internal enum CredentialType: Hashable {
        case kbs
        case svr2

        var iCloudCredentialsKey: String {
            switch self {
            case .kbs:
                return "signal_kbs_credentials"
            case .svr2:
                return "signal_svr2_credentials"
            }
        }

        var kvStoreCollectionName: String {
            switch self {
            case .kbs:
                return "KBSAuthCredential"
            case .svr2:
                return "SVR2AuthCredential"
            }
        }
    }

    internal struct AuthCredential: Codable, Equatable {
        let username: String
        let password: String
        let insertionTime: Date

        static func from(_ credential: SVR2AuthCredential) -> Self {
            return AuthCredential(
                username: credential.credential.username,
                password: credential.credential.password,
                insertionTime: Date()
            )
        }

        static func from(_ credential: KBSAuthCredential) -> Self {
            return AuthCredential(
                username: credential.credential.username,
                password: credential.credential.password,
                insertionTime: Date()
            )
        }

        private var credential: RemoteAttestation.Auth {
            return RemoteAttestation.Auth(username: username, password: password)
        }

        func toSVR2Credential() -> SVR2AuthCredential {
            return SVR2AuthCredential(credential: credential)
        }

        func toKBSCredential() -> KBSAuthCredential {
            return KBSAuthCredential(credential: credential)
        }

        func isEqual(to credential: KBSAuthCredential) -> Bool {
            // Compare everything but the insertion time, make that equal.
            return AuthCredential(
                username: credential.credential.username,
                password: credential.credential.password,
                insertionTime: self.insertionTime
            ) == self
        }

        func isEqual(to credential: SVR2AuthCredential) -> Bool {
            // Compare everything but the insertion time, make that equal.
            return AuthCredential(
                username: credential.credential.username,
                password: credential.credential.password,
                insertionTime: self.insertionTime
            ) == self
        }
    }
}
