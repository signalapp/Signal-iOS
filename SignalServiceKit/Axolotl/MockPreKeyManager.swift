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
    func rotatePreKeysOnUpgradeIfNecessary(for identity: OWSIdentity) async throws { }
    var attemptedRefreshes: [(OWSIdentity, Bool)] = []

    func createPreKeysForRegistration() async -> RegistrationPreKeyUploadBundles {
        let identityKeyPair = ECKeyPair.generateKeyPair()
        return .init(
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

    func createPreKeysForProvisioning(
        aciIdentityKeyPair: ECKeyPair,
        pniIdentityKeyPair: ECKeyPair,
    ) async -> RegistrationPreKeyUploadBundles {
        let identityKeyPair = ECKeyPair.generateKeyPair()
        return .init(
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

    var didFinalizeRegistrationPrekeys = false

    func finalizeRegistrationPreKeys(
        _ bundles: RegistrationPreKeyUploadBundles,
        uploadDidSucceed: Bool,
    ) async {
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
