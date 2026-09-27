//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol PreKeyManager {
    func isAppLockedDueToPreKeyUpdateFailures(tx: DBReadTransaction) -> Bool

    func checkPreKeysIfNecessary() async throws

    /// Creates a new set of prekeys for registration, creating a new identity
    /// key if needed (or reusing the existing identity key).
    ///
    /// These keys are persisted before this method returns, but best effort
    /// should be taken to finalize the keys after the server accepts them.
    func createPreKeysForRegistration(forIdentity identity: OWSIdentity) async -> RegistrationPreKeyUploadBundle

    /// Creates a new set of prekeys for provisioning (linking a new secondary
    /// device), using the provided identity keys (which are delivered from the
    /// primary during linking). These keys are persisted before this method
    /// returns, but best effort should be taken to finalize the keys after the
    /// server accepts them.
    func createPreKeysForProvisioning(
        forIdentity identity: OWSIdentity,
        keyPair: IdentityKeyPair,
    ) async -> RegistrationPreKeyUploadBundle

    /// Called on a best-effort basis. Consequences of not calling this is that
    /// the keys are still persisted (from prior to uploading) but they aren't
    /// marked current and accepted.
    func finalizeRegistrationPreKeyBundle(
        _ bundle: RegistrationPreKeyUploadBundle,
        uploadDidSucceed: Bool,
    ) async

    func rotateOneTimePreKeysForRegistration(auth: ChatServiceAuth) async throws

    func rotateSignedPreKeysIfNeeded() async throws

    func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool,
    ) async throws

    func setIsChangingNumber(_ isChangingNumber: Bool)
}
