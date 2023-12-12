//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class MockPreKeyManager: PreKeyManager {
    func isAppLockedDueToPreKeyUpdateFailures(tx: SignalServiceKit.DBReadTransaction) -> Bool { false }
    func refreshPreKeysDidSucceed() { }
    func checkPreKeysIfNecessary(tx: SignalServiceKit.DBReadTransaction) { }

    func createPreKeysForRegistration() async -> Task<RegistrationPreKeyUploadBundles, Error> {
        let identityKeyPair = ECKeyPair.generateKeyPair()
        return Task {
            .init(
                aci: .init(
                    identity: .aci,
                    identityKeyPair: identityKeyPair,
                    signedPreKey: SSKSignedPreKeyStore.generateSignedPreKey(signedBy: identityKeyPair),
                    lastResortPreKey: generateLastResortKyberPreKey(signedBy: identityKeyPair)
                ),
                pni: .init(
                    identity: .pni,
                    identityKeyPair: identityKeyPair,
                    signedPreKey: SSKSignedPreKeyStore.generateSignedPreKey(signedBy: identityKeyPair),
                    lastResortPreKey: generateLastResortKyberPreKey(signedBy: identityKeyPair)
                )
            )
        }
    }

    func createPreKeysForProvisioning(
        aciIdentityKeyPair: ECKeyPair,
        pniIdentityKeyPair: ECKeyPair
    ) async -> Task<RegistrationPreKeyUploadBundles, Error> {
        let identityKeyPair = ECKeyPair.generateKeyPair()
        return Task {
            .init(
                aci: .init(
                    identity: .aci,
                    identityKeyPair: identityKeyPair,
                    signedPreKey: SSKSignedPreKeyStore.generateSignedPreKey(signedBy: identityKeyPair),
                    lastResortPreKey: generateLastResortKyberPreKey(signedBy: identityKeyPair)
                ),
                pni: .init(
                    identity: .pni,
                    identityKeyPair: identityKeyPair,
                    signedPreKey: SSKSignedPreKeyStore.generateSignedPreKey(signedBy: identityKeyPair),
                    lastResortPreKey: generateLastResortKyberPreKey(signedBy: identityKeyPair)
                )
            )
        }
    }

    public var didFinalizeRegistrationPrekeys = false

    func finalizeRegistrationPreKeys(
        _ bundles: RegistrationPreKeyUploadBundles,
        uploadDidSucceed: Bool
    ) async -> Task<Void, Error> {
        didFinalizeRegistrationPrekeys = true
        return Task {}
    }

    func rotateOneTimePreKeysForRegistration(auth: ChatServiceAuth) async -> Task<Void, Error> {
        return Task {}
    }

    func createOrRotatePNIPreKeys(auth: ChatServiceAuth) async -> Task<Void, Error> { Task {} }
    func rotateSignedPreKeys() async -> Task<Void, Error> { Task {} }
    func refreshOneTimePreKeys(forIdentity identity: OWSIdentity, alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool) { }

    func generateLastResortKyberPreKey(signedBy signingKeyPair: ECKeyPair) -> SignalServiceKit.KyberPreKeyRecord {

        let keyPair = KEMKeyPair.generate()
        let signature = Data(signingKeyPair.keyPair.privateKey.generateSignature(message: Data(keyPair.publicKey.serialize())))

        let record = SignalServiceKit.KyberPreKeyRecord(
            0,
            keyPair: keyPair,
            signature: signature,
            generatedAt: Date(),
            isLastResort: true
        )
        return record
    }
}
