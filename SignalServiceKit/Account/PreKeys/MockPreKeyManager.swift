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
    func checkPreKeysIfNecessary(tx: SignalServiceKit.DBReadTransaction) { }
    func rotatePreKeysOnUpgradeIfNecessary(for identity: OWSIdentity) async throws { }
    var attemptedRefreshes: [(OWSIdentity, Bool)] = []

    func createPreKeysForRegistration() -> Task<RegistrationPreKeyUploadBundles, Error> {
        let identityKeyPair = ECKeyPair.generateKeyPair()
        return Task {
            .init(
                aci: .init(
                    identity: .aci,
                    identityKeyPair: identityKeyPair,
                    signedPreKey: SignedPreKeyStoreImpl.generateSignedPreKey(keyId: PreKeyId.random(), signedBy: identityKeyPair.keyPair.privateKey),
                    lastResortPreKey: generateLastResortKyberPreKey(signedBy: identityKeyPair.keyPair.privateKey),
                ),
                pni: .init(
                    identity: .pni,
                    identityKeyPair: identityKeyPair,
                    signedPreKey: SignedPreKeyStoreImpl.generateSignedPreKey(keyId: PreKeyId.random(), signedBy: identityKeyPair.keyPair.privateKey),
                    lastResortPreKey: generateLastResortKyberPreKey(signedBy: identityKeyPair.keyPair.privateKey),
                ),
            )
        }
    }

    func createPreKeysForProvisioning(
        aciIdentityKeyPair: ECKeyPair,
        pniIdentityKeyPair: ECKeyPair,
    ) -> Task<RegistrationPreKeyUploadBundles, Error> {
        let identityKeyPair = ECKeyPair.generateKeyPair()
        return Task {
            .init(
                aci: .init(
                    identity: .aci,
                    identityKeyPair: identityKeyPair,
                    signedPreKey: SignedPreKeyStoreImpl.generateSignedPreKey(keyId: PreKeyId.random(), signedBy: identityKeyPair.keyPair.privateKey),
                    lastResortPreKey: generateLastResortKyberPreKey(signedBy: identityKeyPair.keyPair.privateKey),
                ),
                pni: .init(
                    identity: .pni,
                    identityKeyPair: identityKeyPair,
                    signedPreKey: SignedPreKeyStoreImpl.generateSignedPreKey(keyId: PreKeyId.random(), signedBy: identityKeyPair.keyPair.privateKey),
                    lastResortPreKey: generateLastResortKyberPreKey(signedBy: identityKeyPair.keyPair.privateKey),
                ),
            )
        }
    }

    var didFinalizeRegistrationPrekeys = false

    func finalizeRegistrationPreKeys(
        _ bundles: RegistrationPreKeyUploadBundles,
        uploadDidSucceed: Bool,
    ) -> Task<Void, Error> {
        didFinalizeRegistrationPrekeys = true
        return Task {}
    }

    func rotateOneTimePreKeysForRegistration(auth: ChatServiceAuth) -> Task<Void, Error> {
        return Task {}
    }

    func rotateSignedPreKeysIfNeeded() -> Task<Void, Error> { Task {} }
    func refreshOneTimePreKeys(forIdentity identity: OWSIdentity, alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool) {
        attemptedRefreshes.append((identity, shouldRefreshSignedPreKey))
    }

    func generateLastResortKyberPreKey(signedBy identityKey: PrivateKey) -> LibSignalClient.KyberPreKeyRecord {
        return KyberPreKeyStoreImpl.generatePreKeyRecord(keyId: PreKeyId.random(), now: Date(), signedBy: identityKey)
    }

    func setIsChangingNumber(_ isChangingNumber: Bool) {
    }
}

#endif
