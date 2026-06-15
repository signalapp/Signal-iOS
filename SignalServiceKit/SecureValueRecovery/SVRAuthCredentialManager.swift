//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension SVR {
    static let maxSVRAuthCredentialsBackedUp: Int = 10
}

/// Stores credentials to authenticate with SVR.
///
/// May simultaneously store credentials for multiple Signal accounts. This
/// can happen if multiple Signal accounts share an iCloud account.
///
/// Credentials are stored across all `credentialStores`. Typically there
/// are two stores: a local KeyValueStore and an encrypted iCloud container.
///
/// They are written to local storage so we can reuse them locally if iCloud
/// is disabled or fails for any reason.
///
/// They are written to iCloud's (encrypted) key value store to be synced
/// between a user's devices. These credentials can be used in tandem with
/// the user's PIN to bypass SMS verification during registration. (For
/// example, if you buy a new phone, sign into iCloud, and then register
/// with the same number.) Note: The user MUST know their PIN to bypass SMS
/// verification and to access their account data. The credential doesn't
/// provide any account information; it only provides the ability to make
/// PIN guesses without first completing SMS verification.
public struct SVRAuthCredentialManager {

    private let credentialStores: [any SVRAuthCredentialStore]
    private let usernameStore: KeyValueStore

    init(
        credentialStores: [any SVRAuthCredentialStore],
        usernameStore: KeyValueStore,
    ) {
        self.credentialStores = credentialStores
        self.usernameStore = usernameStore
    }

#if TESTABLE_BUILD

    static func mock(storeCount: Int = 1) -> Self {
        owsPrecondition(storeCount >= 1)
        let kvStores = (1...storeCount).map {
            return KeyValueStore(collection: "SVRAuthCredential.Mock.\($0)")
        }
        return Self(
            credentialStores: kvStores.map(SVRAuthCredentialLocalStore.init(kvStore:)),
            usernameStore: kvStores.first!,
        )
    }

#endif

    // MARK: SVR2

    /// Stores an `SVR2AuthCredential` to all `credentialStores` (e.g., a local
    /// key value store and iCloud).
    ///
    /// Overwrites any existing credentials for the same username (e.g., ACI).
    ///
    /// Updates the current username so that `getAuthCredentialForCurrentUser`
    /// will return the just-stored credential (barring race conditions and
    /// clock manipulations).
    ///
    /// Stores up to `SVR.maxSVRAuthCredentialsBackedUp` credentials; if more
    /// are inserted, they are dropped in FIFO order.
    ///
    /// Note: Multiple accounts can share an iCloud account, so more than one
    /// username may be present in storage.
    public func storeAuthCredentialForCurrentUsername(_ credential: SVR2AuthCredential, _ transaction: DBWriteTransaction) {
        let credential = AuthCredential.from(credential)
        updateCredentials(transaction) {
            // Sorting is handled by updateCredentials
            $0.append(credential)
        }
        setCurrentUsername(credential.username, transaction)
    }

    /// Gets `SVR2AuthCredential`s from all `credentialStores`.
    ///
    /// Credentials may be expired (i.e., won't be valid for any account and can
    /// be thrown away) or invalid for a particular account (i.e., they aren't
    /// expired but they can't be used for the account we're registering);
    /// callers should poke the registration server to validate them.
    ///
    /// Returns up to `SVR.maxSVRAuthCredentialsBackedUp` credentials.
    public func getAuthCredentials(_ transaction: DBReadTransaction) -> [SVR2AuthCredential] {
        var credentials = [AuthCredential]()
        for credentialStore in credentialStores {
            credentials.append(contentsOf: getCredentials(in: credentialStore, tx: transaction))
        }
        let consolidatedCredentials = Self.consolidateCredentials(allUnsortedCredentials: credentials)
        return consolidatedCredentials.map { $0.toSVR2Credential() }
    }

    /// Gets the most recent `SVR2AuthCredential` for the current username.
    ///
    /// Returns nil if there are no backed up credentials, or if all credentials
    /// came from iCloud storage and therefore there is no "current" username.
    ///
    /// This method should not be used during registration. (Use
    /// `getAuthCredentials` during registration.)
    func getAuthCredentialForCurrentUser(_ transaction: DBReadTransaction) -> SVR2AuthCredential? {
        let credentialCandidates = getAuthCredentials(transaction)
        if credentialCandidates.isEmpty {
            return nil
        }
        let currentUsername = currentUsername(transaction)
        return credentialCandidates.first(where: { return $0.credential.username == currentUsername })
    }

    /// Removes the provided credentials from storage.
    ///
    /// Should be called when the server tells the client the credential(s) are invalid.
    public func deleteInvalidCredentials(_ invalidCredentials: [SVR2AuthCredential], _ transaction: DBWriteTransaction) {
        updateCredentials(transaction) {
            $0.removeAll(where: { existingCredential in
                invalidCredentials.contains(where: { invalidCredential in
                    existingCredential.isEqual(to: invalidCredential)
                })
            })
        }
    }

    /// Removes all credentials for the current user from storage.
    public func removeSVR2CredentialsForCurrentUser(_ transaction: DBWriteTransaction) {
        let currentUsername = currentUsername(transaction)
        updateCredentials(transaction) {
            $0.removeAll(where: { existingCredential in
                existingCredential.username == currentUsername
            })
        }
    }

    private static let usernameKey = "username"

    private func currentUsername(_ transaction: DBReadTransaction) -> String? {
        return usernameStore.getString(Self.usernameKey, transaction: transaction)
    }

    private func setCurrentUsername(_ newValue: String?, _ transaction: DBWriteTransaction) {
        usernameStore.setString(newValue, key: Self.usernameKey, transaction: transaction)
    }

    private func getCredentials(in credentialStore: any SVRAuthCredentialStore, tx: DBReadTransaction) -> [AuthCredential] {
        guard let encodedValue = credentialStore.getCredentialData(tx: tx) else {
            return []
        }
        guard let credentials = try? JSONDecoder().decode([AuthCredential].self, from: encodedValue) else {
            owsFailDebug("couldn't decode auth credential(s)")
            return []
        }
        return credentials
    }

    private func setCredentials(_ newValue: [AuthCredential], in credentialStore: any SVRAuthCredentialStore, tx: DBWriteTransaction) {
        let encodedValue = failIfThrows { try JSONEncoder().encode(newValue) }
        credentialStore.setCredentialData(encodedValue, tx: tx)
    }

    // MARK: - Helpers

    private func updateCredentials(
        _ transaction: DBWriteTransaction,
        _ block: (inout [AuthCredential]) -> Void,
    ) {
        // Apply `block` independently to each credentialStore. If Store A contains
        // a credential that was deleted from Store B, adding an unrelated
        // credential could resurrect the credential that was deleted, and that
        // shouldn't happen. See also testTwoSignalOneCloud.
        for credentialStore in credentialStores {
            var credentials = getCredentials(in: credentialStore, tx: transaction)
            credentials = Self.consolidateCredentials(allUnsortedCredentials: credentials)
            block(&credentials)
            // Consolidate again so that we sort and truncate.
            credentials = Self.consolidateCredentials(allUnsortedCredentials: credentials)
            setCredentials(credentials, in: credentialStore, tx: transaction)
        }
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
