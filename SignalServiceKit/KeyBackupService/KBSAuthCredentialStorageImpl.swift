//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class KBSAuthCredentialStorageImpl: KBSAuthCredentialStorage {

    private let keyValueStoreFactory: KeyValueStoreFactory

    public init(
        keyValueStoreFactory: KeyValueStoreFactory
    ) {
        self.keyValueStoreFactory = keyValueStoreFactory
    }

    public func storeAuthCredentialForCurrentUsername(_ credential: KBSAuthCredential, _ transaction: DBWriteTransaction) {
        let serializableCredential = AuthCredential.from(credential)
        updateCredentials(transaction) {
            // Sorting is handled by updateCredentials
            $0.append(serializableCredential)
        }
        setCurrentUsername(credential.username, transaction)
    }

    public func getAuthCredentials(_ transaction: DBReadTransaction) -> [KBSAuthCredential] {
        return consolidateLocalAndiCloud(transaction).map { $0.toCredential() }
    }

    public func getAuthCredentialForCurrentUser(_ transaction: DBReadTransaction) -> KBSAuthCredential? {
        return consolidateLocalAndiCloud(transaction).first(where: { $0.username == currentUsername(transaction) })?.toCredential()
    }

    public func deleteInvalidCredentials(_ invalidCredentials: [KBSAuthCredential], _ transaction: DBWriteTransaction) {
        updateCredentials(transaction) {
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

    private lazy var kvStore = keyValueStoreFactory.keyValueStore(collection: "KBSAuthCredential")

    private static let usernameKey = "username"

    private func currentUsername(_ transaction: DBReadTransaction) -> String? {
        return kvStore.getString(Self.usernameKey, transaction: transaction)
    }

    private func setCurrentUsername(_ newValue: String?, _ transaction: DBWriteTransaction) {
        kvStore.setString(newValue, key: Self.usernameKey, transaction: transaction)
    }

    private static let localCredentialsKey = "credentials"

    private func localCredentials(_ transaction: DBReadTransaction) -> [AuthCredential] {
        guard let rawData = kvStore.getData(Self.localCredentialsKey, transaction: transaction) else {
            return []
        }
        let decoder = JSONDecoder()
        guard let credentials = try? decoder.decode([AuthCredential].self, from: rawData) else {
            owsFailBeta("Unable to decode kbs auth credential(s)")
            return []
        }
        return credentials
    }

    private func setLocalCredentials(_ newValue: [AuthCredential], _ transaction: DBWriteTransaction) {
        let encoder = JSONEncoder()
        guard let encoded = try? encoder.encode(newValue) else {
            owsFailBeta("Unable to encode kbs auth credential(s)")
            return
        }
        kvStore.setData(encoded, key: Self.localCredentialsKey, transaction: transaction)
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

    private static let iCloudCredentialsKey = "signal_kbs_credentials"

    private var iCloudCredentials: [AuthCredential] {
        get {
            guard let rawData = NSUbiquitousKeyValueStore.default.data(forKey: Self.iCloudCredentialsKey) else {
                return []
            }
            let decoder = JSONDecoder()
            guard let credentials = try? decoder.decode([AuthCredential].self, from: rawData) else {
                owsFailBeta("Unable to decode kbs auth credential(s) from iCloud")
                return []
            }
            return credentials
        }
        set {
            let encoder = JSONEncoder()
            guard let encoded = try? encoder.encode(newValue) else {
                owsFailBeta("Unable to encode kbs auth credential(s) to iCloud")
                return
            }
            NSUbiquitousKeyValueStore.default.set(encoded, forKey: Self.iCloudCredentialsKey)
        }
    }

    // MARK: - Helpers

    private func updateCredentials(_ transaction: DBWriteTransaction, _ block: (inout [AuthCredential]) -> Void) {
        var credentials = consolidateLocalAndiCloud(transaction)
        block(&credentials)
        setLocalCredentials(credentials, transaction)
        // Consolidate again so that we sort and truncate.
        credentials = consolidateLocalAndiCloud(transaction)
        setLocalCredentials(credentials, transaction)
        iCloudCredentials = credentials
    }

    private func consolidateLocalAndiCloud(_ transaction: DBReadTransaction) -> [AuthCredential] {
        return Self.consolidateCredentials(allUnsortedCredentials: localCredentials(transaction) + iCloudCredentials)
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
        .prefix(KBS.maxKBSAuthCredentialsBackedUp)
        return Array(consolidated)
    }

    internal struct AuthCredential: Codable, Equatable {
        let username: String
        let password: String
        let insertionTime: Date

        static func from(_ credential: KBSAuthCredential) -> Self {
            return AuthCredential(
                username: credential.credential.username,
                password: credential.credential.password,
                insertionTime: Date()
            )
        }

        func toCredential() -> KBSAuthCredential {
            return KBSAuthCredential(credential: RemoteAttestation.Auth(username: username, password: password))
        }

        func isEqual(to credential: KBSAuthCredential) -> Bool {
            // Compare everything but the insertion time, make that equal.
            return AuthCredential(
                username: credential.username,
                password: credential.credential.password,
                insertionTime: self.insertionTime
            ) == self
        }
    }
}
