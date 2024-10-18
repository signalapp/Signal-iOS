//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol PreKeyManager {
    func isAppLockedDueToPreKeyUpdateFailures(tx: DBReadTransaction) -> Bool

    func checkPreKeysIfNecessary(tx: DBReadTransaction)

    func rotatePreKeysOnUpgradeIfNecessary(for identity: OWSIdentity) async

    /// Creates a new set of prekeys for registration, creating a new identity key if needed
    /// (or reusing the existing identity key).
    /// These keys are persisted before this method's promise resolves, but best effort
    /// should be taken to finalize the keys once they have been accepted by the server.
    ///
    /// - returns: A task representing the completion of the prekey operation. This task is _not_
    /// a child task of the calling context; this call returns once the task has been scheduled, but running
    /// the task is handled separately (but can be optionally waited on by the caller).
    func createPreKeysForRegistration() -> Task<RegistrationPreKeyUploadBundles, Error>

    /// Creates a new set of prekeys for provisioning (linking a new secondary device),
    /// using the provided identity keys (which are delivered from the primary during linking).
    /// These keys are persisted before this method's promise resolves, but best effort
    /// should be taken to finalize the keys once they have been accepted by the server.
    /// Use `finalizeRegistrationPreKeys` to finalize once linking is complete.
    ///
    /// - returns: A task representing the completion of the prekey operation. This task is _not_
    /// a child task of the calling context; this call returns once the task has been scheduled, but running
    /// the task is handled separately (but can be optionally waited on by the caller).
    func createPreKeysForProvisioning(
        aciIdentityKeyPair: ECKeyPair,
        pniIdentityKeyPair: ECKeyPair
    ) -> Task<RegistrationPreKeyUploadBundles, Error>

    /// Called on a best-effort basis. Consequences of not calling this is that the keys are still
    /// persisted (from prior to uploading) but they aren't marked current and accepted.
    ///
    /// - returns: A task representing the completion of the prekey operation. This task is _not_
    /// a child task of the calling context; this call returns once the task has been scheduled, but running
    /// the task is handled separately (but can be optionally waited on by the caller).
    func finalizeRegistrationPreKeys(
        _ bundles: RegistrationPreKeyUploadBundles,
        uploadDidSucceed: Bool
    ) -> Task<Void, Error>

    /// - returns: A task representing the completion of the prekey operation. This task is _not_
    /// a child task of the calling context; this call returns once the task has been scheduled, but running
    /// the task is handled separately (but can be optionally waited on by the caller).
    func rotateOneTimePreKeysForRegistration(auth: ChatServiceAuth) -> Task<Void, Error>

    /// - returns: A task representing the completion of the prekey operation. This task is _not_
    /// a child task of the calling context; this call returns once the task has been scheduled, but running
    /// the task is handled separately (but can be optionally waited on by the caller).
    func rotateSignedPreKeys() -> Task<Void, Error>

    func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    )
}
