//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

class SVRAuthCredentialStorageImpl: SVRAuthCredentialStorage {

    private let credentialStores: [any SVRAuthCredentialStore]
    private let usernameStore: KeyValueStore

    init(
        credentialStores: [any SVRAuthCredentialStore],
        usernameStore: KeyValueStore,
    ) {
        self.credentialStores = credentialStores
        self.usernameStore = usernameStore
    }

    // MARK: SVR2

    func storeAuthCredentialForCurrentUsername(_ credential: SVR2AuthCredential, _ transaction: DBWriteTransaction) {
        let credential = AuthCredential.from(credential)
        updateCredentials(transaction) {
            // Sorting is handled by updateCredentials
            $0.append(credential)
        }
        setCurrentUsername(credential.username, transaction)
    }

    func getAuthCredentials(_ transaction: DBReadTransaction) -> [SVR2AuthCredential] {
        let consolidatedCredentials = Self.consolidateCredentials(allUnsortedCredentials: self.getCredentials(tx: transaction))
        return consolidatedCredentials.map { $0.toSVR2Credential() }
    }

    func getAuthCredentialForCurrentUser(_ transaction: DBReadTransaction) -> SVR2AuthCredential? {
        let credentialCandidates = getAuthCredentials(transaction)
        if credentialCandidates.isEmpty {
            return nil
        }
        let currentUsername = currentUsername(transaction)
        return credentialCandidates.first(where: { return $0.credential.username == currentUsername })
    }

    func deleteInvalidCredentials(_ invalidCredentials: [SVR2AuthCredential], _ transaction: DBWriteTransaction) {
        updateCredentials(transaction) {
            $0.removeAll(where: { existingCredential in
                invalidCredentials.contains(where: { invalidCredential in
                    existingCredential.isEqual(to: invalidCredential)
                })
            })
        }
    }

    func removeSVR2CredentialsForCurrentUser(_ transaction: DBWriteTransaction) {
        let currentUsername = currentUsername(transaction)
        updateCredentials(transaction) {
            $0.removeAll(where: { existingCredential in
                existingCredential.username == currentUsername
            })
        }
    }

    // Also write any KBS auth credentials we know about to local, encrypted database storage,
    // so we can reuse them locally even if iCloud is disabled or fails for any reason.

    private static let usernameKey = "username"

    private func currentUsername(_ transaction: DBReadTransaction) -> String? {
        return usernameStore.getString(Self.usernameKey, transaction: transaction)
    }

    private func setCurrentUsername(_ newValue: String?, _ transaction: DBWriteTransaction) {
        usernameStore.setString(newValue, key: Self.usernameKey, transaction: transaction)
    }

    private func getCredentials(tx: DBReadTransaction) -> [AuthCredential] {
        var results = [AuthCredential]()
        for credentialStore in credentialStores {
            guard let encodedValue = credentialStore.getCredentialData(tx: tx) else {
                continue
            }
            guard let credentials = try? JSONDecoder().decode([AuthCredential].self, from: encodedValue) else {
                owsFailDebug("couldn't decode auth credential(s)")
                continue
            }
            results.append(contentsOf: credentials)
        }
        return results
    }

    private func setCredentials(_ newValue: [AuthCredential], tx: DBWriteTransaction) {
        let encodedValue = failIfThrows { try JSONEncoder().encode(newValue) }
        for credentialStore in credentialStores {
            credentialStore.setCredentialData(encodedValue, tx: tx)
        }
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

    // MARK: - Helpers

    private func updateCredentials(
        _ transaction: DBWriteTransaction,
        _ block: (inout [AuthCredential]) -> Void,
    ) {
        var credentials = getCredentials(tx: transaction)
        credentials = Self.consolidateCredentials(allUnsortedCredentials: credentials)
        block(&credentials)
        // Consolidate again so that we sort and truncate.
        credentials = Self.consolidateCredentials(allUnsortedCredentials: credentials)
        setCredentials(credentials, tx: transaction)
    }

    // Exposed for testing.
    static func consolidateCredentials(
        allUnsortedCredentials: [AuthCredential],
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

    struct AuthCredential: Codable, Equatable {
        let username: String
        let password: String
        let insertionTime: Date

        static func from(_ credential: SVR2AuthCredential) -> Self {
            return AuthCredential(
                username: credential.credential.username,
                password: credential.credential.password,
                insertionTime: Date(),
            )
        }

        private var credential: RemoteAttestationAuth {
            return RemoteAttestationAuth(username: username, password: password)
        }

        func toSVR2Credential() -> SVR2AuthCredential {
            return SVR2AuthCredential(credential: credential)
        }

        func isEqual(to credential: SVR2AuthCredential) -> Bool {
            // Compare everything but the insertion time, make that equal.
            return AuthCredential(
                username: credential.credential.username,
                password: credential.credential.password,
                insertionTime: self.insertionTime,
            ) == self
        }
    }
}
