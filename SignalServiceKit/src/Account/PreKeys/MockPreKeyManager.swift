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

    func createPreKeysForRegistration() -> Promise<RegistrationPreKeyUploadBundles> {
        let identityKeyPair = ECKeyPair.generateKeyPair()
        return .value(.init(
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
        ))
    }

    func createPreKeysForProvisioning(
        aciIdentityKeyPair: ECKeyPair,
        pniIdentityKeyPair: ECKeyPair
    ) -> Promise<RegistrationPreKeyUploadBundles> {
        let identityKeyPair = ECKeyPair.generateKeyPair()
        return .value(.init(
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
        ))
    }

    public var didFinalizeRegistrationPrekeys = false

    func finalizeRegistrationPreKeys(
        _ bundles: RegistrationPreKeyUploadBundles,
        uploadDidSucceed: Bool
    ) -> Promise<Void> {
        didFinalizeRegistrationPrekeys = true
        return .value(())
    }

    func rotateOneTimePreKeysForRegistration(auth: ChatServiceAuth) -> Promise<Void> {
        return .value(())
    }

    func createOrRotatePNIPreKeys(auth: ChatServiceAuth) -> SignalCoreKit.Promise<Void> { Promise.value(()) }
    func rotateSignedPreKeys() -> SignalCoreKit.Promise<Void> { Promise.value(()) }
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
