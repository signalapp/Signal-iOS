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
        let identityKeyPair = Curve25519.generateKeyPair()
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

    func finalizeRegistrationPreKeys(
        _ bundles: RegistrationPreKeyUploadBundles,
        uploadDidSucceed: Bool
    ) -> Promise<Void> {
        return .value(())
    }

    func rotateOneTimePreKeysForRegistration(auth: ChatServiceAuth) -> Promise<Void> {
        return .value(())
    }

    func legacy_createPreKeys(auth: SignalServiceKit.ChatServiceAuth) -> SignalCoreKit.Promise<Void> { Promise.value(()) }
    func createOrRotatePNIPreKeys(auth: ChatServiceAuth) -> SignalCoreKit.Promise<Void> { Promise.value(()) }
    func rotateSignedPreKeys() -> SignalCoreKit.Promise<Void> { Promise.value(()) }
    func refreshOneTimePreKeys(forIdentity identity: OWSIdentity, alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool) { }

    func generateLastResortKyberPreKey(signedBy signingKeyPair: ECKeyPair) -> SignalServiceKit.KyberPreKeyRecord {

        let keyPair = KEMKeyPair.generate()
        let signature = try! Ed25519.sign(Data(keyPair.publicKey.serialize()), with: signingKeyPair)

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
