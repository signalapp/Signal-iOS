//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@testable import SignalServiceKit

class MockClient {
    var protocolAddress: ProtocolAddress { ProtocolAddress(aci, deviceId: deviceId) }

    var sealedSenderAddress: SealedSenderAddress {
        try! SealedSenderAddress(
            e164: phoneNumber.stringValue,
            uuidString: aci.serviceIdString,
            deviceId: deviceId.uint32Value,
        )
    }

    var localIdentifiers: LocalIdentifiers {
        LocalIdentifiers(aci: aci, pni: nil, phoneNumber: phoneNumber.stringValue)
    }

    let aci: Aci
    let phoneNumber: E164
    let deviceId: DeviceId
    let registrationId: Int32

    let identityKeyPair: IdentityKeyPair

    let sessionStore: InMemorySignalProtocolStore
    let preKeyStore: InMemorySignalProtocolStore
    let signedPreKeyStore: InMemorySignalProtocolStore
    let kyberPreKeyStore: InMemorySignalProtocolStore
    let identityStore: InMemorySignalProtocolStore
    let senderKeyStore: InMemorySignalProtocolStore

    init(aci: Aci, phoneNumber: E164, deviceId: DeviceId, registrationId: Int32) {
        self.aci = aci
        self.phoneNumber = phoneNumber
        self.deviceId = deviceId
        self.registrationId = registrationId
        self.identityKeyPair = IdentityKeyPair.generate()

        let protocolStore = InMemorySignalProtocolStore(
            identity: identityKeyPair,
            registrationId: UInt32(registrationId),
        )

        sessionStore = protocolStore
        preKeyStore = protocolStore
        signedPreKeyStore = protocolStore
        kyberPreKeyStore = protocolStore
        identityStore = protocolStore
        senderKeyStore = protocolStore
    }

    func createSecretSessionCipher() -> SMKSecretSessionCipher {
        return SMKSecretSessionCipher(
            sessionStore: sessionStore,
            preKeyStore: preKeyStore,
            signedPreKeyStore: signedPreKeyStore,
            kyberPreKeyStore: kyberPreKeyStore,
            identityStore: identityStore,
            senderKeyStore: senderKeyStore,
        )
    }

    func generateMockPreKey() -> LibSignalClient.PreKeyRecord {
        let preKeyId = UInt32(Int32.random(in: 0...Int32.max))
        let preKey = try! PreKeyRecord(id: preKeyId, privateKey: PrivateKey.generate())
        try! self.preKeyStore.storePreKey(preKey, id: preKeyId, context: NullContext())
        return preKey
    }

    func generateMockSignedPreKey() -> LibSignalClient.SignedPreKeyRecord {
        let signedPreKeyId = UInt32(Int32.random(in: 0...Int32.max))
        let keyPair = IdentityKeyPair.generate()
        let generatedAt = Date()
        let identityKeyPair = try! self.identityStore.identityKeyPair(context: NullContext())
        let signature = identityKeyPair.privateKey.generateSignature(message: keyPair.publicKey.serialize())
        let signedPreKey = try! SignedPreKeyRecord(
            id: signedPreKeyId,
            timestamp: UInt64(generatedAt.timeIntervalSince1970),
            privateKey: keyPair.privateKey,
            signature: signature,
        )
        try! self.signedPreKeyStore.storeSignedPreKey(signedPreKey, id: signedPreKeyId, context: NullContext())
        return signedPreKey
    }

    func generateMockKyberPreKey() -> LibSignalClient.KyberPreKeyRecord {
        let kyberPreKeyId = UInt32(Int32.random(in: 0...Int32.max))
        let keyPair = KEMKeyPair.generate()
        let generatedAt = Date()
        let identityKeyPair = try! self.identityStore.identityKeyPair(context: NullContext())
        let signature = identityKeyPair.privateKey.generateSignature(message: keyPair.publicKey.serialize())
        let kyberPreKey = try! KyberPreKeyRecord(
            id: kyberPreKeyId,
            timestamp: UInt64(generatedAt.timeIntervalSince1970),
            keyPair: keyPair,
            signature: signature,
        )
        try! self.kyberPreKeyStore.storeKyberPreKey(kyberPreKey, id: kyberPreKeyId, context: NullContext())
        return kyberPreKey
    }

    // Moved from SMKSecretSessionCipherTest.
    // private void initializeSessions(TestInMemorySignalProtocolStore aliceStore, TestInMemorySignalProtocolStore bobStore)
    //     throws InvalidKeyException, UntrustedIdentityException
    func initializeSession(with bobMockClient: MockClient) {
        // ECKeyPair          bobPreKey       = Curve.generateKeyPair();
        let bobPreKey = bobMockClient.generateMockPreKey()

        // IdentityKeyPair    bobIdentityKey  = bobStore.getIdentityKeyPair();
        let bobIdentityKey = bobMockClient.identityKeyPair

        // SignedPreKeyRecord bobSignedPreKey = KeyHelper.generateSignedPreKey(bobIdentityKey, 2);
        let bobSignedPreKey = bobMockClient.generateMockSignedPreKey()

        let bobKyberPreKey = bobMockClient.generateMockKyberPreKey()

        // PreKeyBundle bobBundle             = new PreKeyBundle(1, 1, 1, bobPreKey.getPublicKey(), 2, bobSignedPreKey.getKeyPair().getPublicKey(), bobSignedPreKey.getSignature(), bobIdentityKey.getPublicKey());
        let bobBundle = try! PreKeyBundle(
            registrationId: UInt32(bitPattern: bobMockClient.registrationId),
            deviceId: bobMockClient.deviceId.uint32Value,
            prekeyId: bobPreKey.id,
            prekey: try! bobPreKey.publicKey(),
            signedPrekeyId: bobSignedPreKey.id,
            signedPrekey: try! bobSignedPreKey.publicKey(),
            signedPrekeySignature: bobSignedPreKey.signature,
            identity: bobIdentityKey.identityKey,
            kyberPrekeyId: bobKyberPreKey.id,
            kyberPrekey: try! bobKyberPreKey.publicKey(),
            kyberPrekeySignature: bobKyberPreKey.signature,
        )

        // SessionBuilder aliceSessionBuilder = new SessionBuilder(aliceStore, new SignalProtocolAddress("+14152222222", 1));
        // aliceSessionBuilder.process(bobBundle);
        let bobProtocolAddress = bobMockClient.protocolAddress
        try! processPreKeyBundle(
            bobBundle,
            for: bobProtocolAddress,
            sessionStore: sessionStore,
            identityStore: identityStore,
            context: NullContext(),
        )

        // bobStore.storeSignedPreKey(2, bobSignedPreKey);
        // bobStore.storePreKey(1, new PreKeyRecord(1, bobPreKey));
        // NOTE: These stores are taken care of in the mocks' createKey() methods above.
    }
}
