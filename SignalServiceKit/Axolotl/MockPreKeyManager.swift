//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

#if TESTABLE_BUILD

class MockPreKeyManager: PreKeyManager {
    func isAppLockedDueToPreKeyUpdateFailures(tx: SignalServiceKit.DBReadTransaction) -> Bool { false }
    func refreshOneTimePreKeysCheckDidSucceed() { }
    func checkPreKeysIfNecessary() async throws { }
    var attemptedRefreshes: [(OWSIdentity, Bool)] = []

    func createPreKeysForRegistration(forIdentity identity: OWSIdentity) async -> RegistrationPreKeyUploadBundle {
        let identityKeyPair = IdentityKeyPair.generate()
        return RegistrationPreKeyUploadBundle(
            identity: identity,
            identityKeyPair: identityKeyPair,
            signedPreKey: SignedPreKeyStoreImpl.generateSignedPreKey(keyId: PreKeyId.random(), signedBy: identityKeyPair.privateKey),
            lastResortPreKey: generateLastResortKyberPreKey(signedBy: identityKeyPair.privateKey),
        )
    }

    func createPreKeysForProvisioning(
        forIdentity identity: OWSIdentity,
        keyPair: IdentityKeyPair,
    ) async -> RegistrationPreKeyUploadBundle {
        return RegistrationPreKeyUploadBundle(
            identity: identity,
            identityKeyPair: keyPair,
            signedPreKey: SignedPreKeyStoreImpl.generateSignedPreKey(keyId: PreKeyId.random(), signedBy: keyPair.privateKey),
            lastResortPreKey: generateLastResortKyberPreKey(signedBy: keyPair.privateKey),
        )
    }

    var didFinalizeRegistrationPrekeys = false

    func finalizeRegistrationPreKeyBundle(_ bundle: RegistrationPreKeyUploadBundle, uploadDidSucceed: Bool) async {
        didFinalizeRegistrationPrekeys = true
    }

    func rotateOneTimePreKeysForRegistration(auth: ChatServiceAuth) async throws {
    }

    func rotateSignedPreKeysIfNeeded() async throws {}

    func refreshOneTimePreKeys(forIdentity identity: OWSIdentity, alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool) async throws {
        attemptedRefreshes.append((identity, shouldRefreshSignedPreKey))
    }

    func generateLastResortKyberPreKey(signedBy identityKey: PrivateKey) -> LibSignalClient.KyberPreKeyRecord {
        return KyberPreKeyStoreImpl.generatePreKeyRecord(keyId: PreKeyId.random(), now: Date(), signedBy: identityKey)
    }

    func setIsChangingNumber(_ isChangingNumber: Bool) {
    }
}

#endif
