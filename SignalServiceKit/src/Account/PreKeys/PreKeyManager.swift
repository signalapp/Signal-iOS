//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol PreKeyManager {
    func isAppLockedDueToPreKeyUpdateFailures(tx: DBReadTransaction) -> Bool

    func checkPreKeysIfNecessary(tx: DBReadTransaction)

    /// Creates a new set of prekeys for registration, creating a new identity key if needed
    /// (or reusing the existing identity key).
    /// These keys are persisted before this method's promise resolves, but best effort
    /// should be taken to finalize the keys once they have been accepted by the server.
    func createPreKeysForRegistration() -> Promise<RegistrationPreKeyUploadBundles>

    /// Creates a new set of prekeys for provisioning (linking a new secondary device),
    /// using the provided identity keys (which are delivered from the primary during linking).
    /// These keys are persisted before this method's promise resolves, but best effort
    /// should be taken to finalize the keys once they have been accepted by the server.
    /// Use `finalizeRegistrationPreKeys` to finalize once linking is complete.
    func createPreKeysForProvisioning(
        aciIdentityKeyPair: ECKeyPair,
        pniIdentityKeyPair: ECKeyPair
    ) -> Promise<RegistrationPreKeyUploadBundles>

    /// Called on a best-effort basis. Consequences of not calling this is that the keys are still
    /// persisted (from prior to uploading) but they aren't marked current and accepted.
    func finalizeRegistrationPreKeys(
        _ bundles: RegistrationPreKeyUploadBundles,
        uploadDidSucceed: Bool
    ) -> Promise<Void>

    func rotateOneTimePreKeysForRegistration(auth: ChatServiceAuth) -> Promise<Void>

    func legacy_createPreKeys(auth: ChatServiceAuth) -> Promise<Void>

    /// Our local PNI can get out of sync with the server, including because we never had
    /// a PNI or the server never got ours. In these cases we create new PNI prekeys
    /// to give to the server, ignoring any old ones we may have had.
    func createOrRotatePNIPreKeys(auth: ChatServiceAuth) -> Promise<Void>

    func rotateSignedPreKeys() -> Promise<Void>

    func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    )
}
