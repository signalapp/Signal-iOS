//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalServiceKit
@testable import SignalClient
import Curve25519Kit
import SignalCoreKit

// https://github.com/signalapp/libsignal-metadata-java/blob/master/tests/src/test/java/org/signal/libsignal/metadata/SecretSessionCipherTest.java
// public class SecretSessionCipherTest extends TestCase {
class SMKSecretSessionCipherTest: SSKBaseTestSwift {

    // public void testEncryptDecrypt() throws UntrustedIdentityException, InvalidKeyException, InvalidCertificateException, InvalidProtocolBufferException, InvalidMetadataMessageException, ProtocolDuplicateMessageException, ProtocolUntrustedIdentityException, ProtocolLegacyMessageException, ProtocolInvalidKeyException, InvalidMetadataVersionException, ProtocolInvalidVersionException, ProtocolInvalidMessageException, ProtocolInvalidKeyIdException, ProtocolNoSessionException, SelfSendException {
    func testEncryptDecrypt() {
        // TestInMemorySignalProtocolStore aliceStore = new TestInMemorySignalProtocolStore();
        // TestInMemorySignalProtocolStore bobStore   = new TestInMemorySignalProtocolStore();
        // NOTE: We use MockClient to ensure consistency between of our session state.
        let aliceMockClient = MockClient(address: MockClient.aliceAddress, deviceId: 1, registrationId: 1234)
        let bobMockClient = MockClient(address: MockClient.bobAddress, deviceId: 1, registrationId: 1235)

        // initializeSessions(aliceStore, bobStore);
        initializeSessions(aliceMockClient: aliceMockClient, bobMockClient: bobMockClient)

        // ECKeyPair           trustRoot         = Curve.generateKeyPair();
        let trustRoot = IdentityKeyPair.generate()

        // SenderCertificate   senderCertificate = createCertificateFor(trustRoot, "+14151111111", 1, aliceStore.getIdentityKeyPair().getPublicKey().getPublicKey(), 31337);
        let senderCertificate = createCertificateFor(trustRoot: trustRoot,
                                                     senderAddress: aliceMockClient.address,
                                                     senderDeviceId: UInt32(aliceMockClient.deviceId),
                                                     identityKey: aliceMockClient.identityKeyPair.publicKey,
                                                     expirationTimestamp: 31337)

        // SecretSessionCipher aliceCipher       = new SecretSessionCipher(aliceStore);
        let aliceCipher: SMKSecretSessionCipher = try! aliceMockClient.createSecretSessionCipher()

        // byte[] ciphertext = aliceCipher.encrypt(new SignalProtocolAddress("+14152222222", 1),
        // senderCertificate, "smert za smert".getBytes());
        // NOTE: The java tests don't bother padding the plaintext.
        let alicePlaintext = "smert za smert".data(using: String.Encoding.utf8)!
        let ciphertext = try! aliceCipher.encryptMessage(recipient: bobMockClient.address,
                                                         deviceId: bobMockClient.deviceId,
                                                         paddedPlaintext: alicePlaintext,
                                                         senderCertificate: senderCertificate)

        // SealedSessionCipher bobCipher = new SealedSessionCipher(bobStore, new SignalProtocolAddress("+14152222222", 1));
        let bobCipher: SMKSecretSessionCipher = try! bobMockClient.createSecretSessionCipher()

        // Pair<SignalProtocolAddress, byte[]> plaintext = bobCipher.decrypt(new CertificateValidator(trustRoot.getPublicKey()), ciphertext, 31335);
        let bobPlaintext = try! bobCipher.decryptMessage(trustRoot: trustRoot.publicKey,
                                                         cipherTextData: ciphertext,
                                                         timestamp: 31335,
                                                         protocolContext: nil)

        // assertEquals(new String(plaintext.second()), "smert za smert");
        // assertEquals(plaintext.first().getName(), "+14151111111");
        // assertEquals(plaintext.first().getDeviceId(), 1);
        XCTAssertEqual(String(data: bobPlaintext.paddedPayload, encoding: .utf8), "smert za smert")
        XCTAssertEqual(bobPlaintext.senderAddress, aliceMockClient.address)
        XCTAssertEqual(bobPlaintext.senderDeviceId, Int(aliceMockClient.deviceId))
    }

    // public void testEncryptDecryptUntrusted() throws Exception {
    func testEncryptDecryptUntrusted() {
        // TestInMemorySignalProtocolStore aliceStore = new TestInMemorySignalProtocolStore();
        // TestInMemorySignalProtocolStore bobStore   = new TestInMemorySignalProtocolStore();
        // NOTE: We use MockClient to ensure consistency between of our session state.
        let aliceMockClient = MockClient(address: MockClient.aliceAddress, deviceId: 1, registrationId: 1234)
        let bobMockClient = MockClient(address: MockClient.bobAddress, deviceId: 1, registrationId: 1235)

        // initializeSessions(aliceStore, bobStore);
        initializeSessions(aliceMockClient: aliceMockClient, bobMockClient: bobMockClient)

        // ECKeyPair           trustRoot         = Curve.generateKeyPair();
        // ECKeyPair           falseTrustRoot    = Curve.generateKeyPair();
        let trustRoot = IdentityKeyPair.generate()
        let falseTrustRoot = IdentityKeyPair.generate()
        // SenderCertificate   senderCertificate = createCertificateFor(falseTrustRoot, "+14151111111", 1, aliceStore.getIdentityKeyPair().getPublicKey().getPublicKey(), 31337);
        let senderCertificate = createCertificateFor(trustRoot: falseTrustRoot,
                                                     senderAddress: aliceMockClient.address,
                                                     senderDeviceId: UInt32(aliceMockClient.deviceId),
                                                     identityKey: aliceMockClient.identityKeyPair.publicKey,
                                                     expirationTimestamp: 31337)

        // SecretSessionCipher aliceCipher       = new SecretSessionCipher(aliceStore);
        let aliceCipher: SMKSecretSessionCipher = try! aliceMockClient.createSecretSessionCipher()

        // byte[] ciphertext = aliceCipher.encrypt(new SignalProtocolAddress("+14152222222", 1),
        // senderCertificate, "и вот я".getBytes());
        // NOTE: The java tests don't bother padding the plaintext.
        let alicePlaintext = "и вот я".data(using: String.Encoding.utf8)!
        let aliceGroupId = Randomness.generateRandomBytes(6)
        let aliceContentHint = UnidentifiedSenderMessageContent.ContentHint.implicit
        let ciphertext = try! aliceCipher.encryptMessage(recipient: bobMockClient.address,
                                                         deviceId: bobMockClient.deviceId,
                                                         paddedPlaintext: alicePlaintext,
                                                         contentHint: aliceContentHint,
                                                         groupId: aliceGroupId,
                                                         senderCertificate: senderCertificate)

        // SecretSessionCipher bobCipher = new SecretSessionCipher(bobStore);
        let bobCipher: SMKSecretSessionCipher = try! bobMockClient.createSecretSessionCipher()

        // try {
        //   bobCipher.decrypt(new CertificateValidator(trustRoot.getPublicKey()), ciphertext, 31335);
        //   throw new AssertionError();
        // } catch (InvalidMetadataMessageException e) {
        //   // good
        // }
        do {
            _ = try bobCipher.decryptMessage(trustRoot: trustRoot.publicKey,
                                             cipherTextData: ciphertext,
                                             timestamp: 31335,
                                             protocolContext: nil)
            XCTFail("Decryption should have failed.")
        } catch let knownSenderError as SecretSessionKnownSenderError {
            // Decryption is expected to fail.
            guard case SMKSecretSessionCipherError.invalidCertificate = knownSenderError.underlyingError else {
                XCTFail("wrong underlying error: \(knownSenderError.underlyingError)")
                return
            }
            XCTAssertEqual(knownSenderError.contentHint, aliceContentHint)
            XCTAssertEqual(knownSenderError.groupId, aliceGroupId)
            XCTAssertNoThrow(
                try DecryptionErrorMessage(
                    originalMessageBytes: knownSenderError.unsealedContent,
                    type: knownSenderError.cipherType,
                    timestamp: 31335,
                    originalSenderDeviceId: knownSenderError.senderDeviceId
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // public void testEncryptDecryptExpired() throws Exception {
    func testEncryptDecryptExpired() {
        // TestInMemorySignalProtocolStore aliceStore = new TestInMemorySignalProtocolStore();
        // TestInMemorySignalProtocolStore bobStore   = new TestInMemorySignalProtocolStore();
        // NOTE: We use MockClient to ensure consistency between of our session state.
        let aliceMockClient = MockClient(address: MockClient.aliceAddress, deviceId: 1, registrationId: 1234)
        let bobMockClient = MockClient(address: MockClient.bobAddress, deviceId: 1, registrationId: 1235)

        // initializeSessions(aliceStore, bobStore);
        initializeSessions(aliceMockClient: aliceMockClient, bobMockClient: bobMockClient)

        // ECKeyPair           trustRoot         = Curve.generateKeyPair();
        let trustRoot = IdentityKeyPair.generate()

        // SenderCertificate   senderCertificate = createCertificateFor(trustRoot, "+14151111111", 1, aliceStore.getIdentityKeyPair().getPublicKey().getPublicKey(), 31337);
        let senderCertificate = createCertificateFor(trustRoot: trustRoot,
                                                     senderAddress: aliceMockClient.address,
                                                     senderDeviceId: UInt32(aliceMockClient.deviceId),
                                                     identityKey: aliceMockClient.identityKeyPair.publicKey,
                                                     expirationTimestamp: 31337)

        // SecretSessionCipher aliceCipher       = new SecretSessionCipher(aliceStore);
        let aliceCipher: SMKSecretSessionCipher = try! aliceMockClient.createSecretSessionCipher()

        // byte[] ciphertext = aliceCipher.encrypt(new SignalProtocolAddress("+14152222222", 1),
        //     senderCertificate, "и вот я".getBytes());
        // NOTE: The java tests don't bother padding the plaintext.
        let alicePlaintext = "и вот я".data(using: String.Encoding.utf8)!
        let aliceGroupId = Randomness.generateRandomBytes(6)
        let aliceContentHint = UnidentifiedSenderMessageContent.ContentHint.resendable

        let ciphertext = try! aliceCipher.encryptMessage(recipient: bobMockClient.address,
                                                         deviceId: bobMockClient.deviceId,
                                                         paddedPlaintext: alicePlaintext,
                                                         contentHint: aliceContentHint,
                                                         groupId: aliceGroupId,
                                                         senderCertificate: senderCertificate)

        // SecretSessionCipher bobCipher = new SecretSessionCipher(bobStore);
        let bobCipher: SMKSecretSessionCipher = try! bobMockClient.createSecretSessionCipher()

        // try {
        //   bobCipher.decrypt(new CertificateValidator(trustRoot.getPublicKey()), ciphertext, 31338);
        //   throw new AssertionError();
        // } catch (InvalidMetadataMessageException e) {
        //   // good
        // }
        do {
            _ = try bobCipher.decryptMessage(trustRoot: trustRoot.publicKey,
                                             cipherTextData: ciphertext,
                                             timestamp: 31338,
                                             protocolContext: nil)
            XCTFail("Decryption should have failed.")
        } catch let knownSenderError as SecretSessionKnownSenderError {
            // Decryption is expected to fail.
            guard case SMKSecretSessionCipherError.invalidCertificate = knownSenderError.underlyingError else {
                XCTFail("wrong underlying error: \(knownSenderError.underlyingError)")
                return
            }
            XCTAssertEqual(knownSenderError.contentHint, aliceContentHint)
            XCTAssertEqual(knownSenderError.groupId, aliceGroupId)
            XCTAssertNoThrow(
                try DecryptionErrorMessage(
                    originalMessageBytes: knownSenderError.unsealedContent,
                    type: knownSenderError.cipherType,
                    timestamp: 31338,
                    originalSenderDeviceId: knownSenderError.senderDeviceId
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

     // public void testEncryptFromWrongIdentity() throws Exception {
     func testEncryptFromWrongIdentity() {
        // TestInMemorySignalProtocolStore aliceStore = new TestInMemorySignalProtocolStore();
        // TestInMemorySignalProtocolStore bobStore   = new TestInMemorySignalProtocolStore();
        // NOTE: We use MockClient to ensure consistency between of our session state.
        let aliceMockClient = MockClient(address: MockClient.aliceAddress, deviceId: 1, registrationId: 1234)
        let bobMockClient = MockClient(address: MockClient.bobAddress, deviceId: 1, registrationId: 1235)

        // initializeSessions(aliceStore, bobStore);
        initializeSessions(aliceMockClient: aliceMockClient,
                           bobMockClient: bobMockClient)

        // ECKeyPair           trustRoot         = Curve.generateKeyPair();
        let trustRoot = IdentityKeyPair.generate()
        // ECKeyPair           randomKeyPair     = Curve.generateKeyPair();
        let randomKeyPair = IdentityKeyPair.generate()
        // SenderCertificate   senderCertificate = createCertificateFor(trustRoot, "+14151111111", 1, randomKeyPair.getPublicKey(), 31337);
        let senderCertificate = createCertificateFor(trustRoot: trustRoot,
                                                     senderAddress: aliceMockClient.address,
                                                     senderDeviceId: UInt32(aliceMockClient.deviceId),
                                                     identityKey: randomKeyPair.publicKey,
                                                     expirationTimestamp: 31337)
        // SecretSessionCipher aliceCipher       = new SecretSessionCipher(aliceStore);
        let aliceCipher: SMKSecretSessionCipher = try! aliceMockClient.createSecretSessionCipher()

        // byte[] ciphertext = aliceCipher.encrypt(new SignalProtocolAddress("+14152222222", 1),
        //    senderCertificate, "smert za smert".getBytes());
        // NOTE: The java tests don't bother padding the plaintext.
        let alicePlaintext = "smert za smert".data(using: String.Encoding.utf8)!
        let ciphertext = try! aliceCipher.encryptMessage(recipient: bobMockClient.address,
                                                         deviceId: bobMockClient.deviceId,
                                                         paddedPlaintext: alicePlaintext,
                                                         senderCertificate: senderCertificate)

        // SecretSessionCipher bobCipher = new SecretSessionCipher(bobStore);
        let bobCipher: SMKSecretSessionCipher = try! bobMockClient.createSecretSessionCipher()

        // try {
        //   bobCipher.decrypt(new CertificateValidator(trustRoot.getPublicKey()), ciphertext, 31335);
        // } catch (InvalidMetadataMessageException e) {
        //   // good
        // }
        do {
            _ = try bobCipher.decryptMessage(trustRoot: trustRoot.publicKey,
                                             cipherTextData: ciphertext,
                                             timestamp: 31335,
                                             protocolContext: nil)
            XCTFail("Decryption should have failed.")
        } catch SignalError.invalidMessage(_) {
            // Decryption is expected to fail.
            // FIXME: This particular failure doesn't get wrapped as a SecretSessionKnownSenderError
            // because it's checked before the unwrapped message is returned.
            // Why? Because it uses crypto values calculated during unwrapping to validate the sender certificate.
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testGroupEncryptDecrypt_Success() {
        // Setup: Initialize sessions and sender certificate
        let aliceMockClient = MockClient(address: MockClient.aliceAddress, deviceId: 1, registrationId: 1234)
        let bobMockClient = MockClient(address: MockClient.bobAddress, deviceId: 1, registrationId: 1235)
        initializeSessions(aliceMockClient: aliceMockClient, bobMockClient: bobMockClient)

        let trustRoot = IdentityKeyPair.generate()
        let senderCertificate = createCertificateFor(
            trustRoot: trustRoot,
            senderAddress: aliceMockClient.address,
            senderDeviceId: UInt32(aliceMockClient.deviceId),
            identityKey: aliceMockClient.identityKeyPair.publicKey,
            expirationTimestamp: 31337)

        // Setup: Distribute alice's sender key to bob's key store
        let distributionId = UUID()
        let aliceSenderKeyMessage = try! SenderKeyDistributionMessage(
            from: aliceMockClient.protocolAddress,
            distributionId: distributionId,
            store: aliceMockClient.senderKeyStore,
            context: NullContext())

        try! processSenderKeyDistributionMessage(
            aliceSenderKeyMessage,
            from: aliceMockClient.protocolAddress,
            store: bobMockClient.senderKeyStore,
            context: NullContext())

        // Test: Alice encrypt's a message using `groupEncryptMessage`
        let aliceCipher = try! aliceMockClient.createSecretSessionCipher()
        let alicePlaintext = "beltalowda".data(using: String.Encoding.utf8)!
        let aliceCiphertext = try! aliceCipher.groupEncryptMessage(
            recipients: [bobMockClient.protocolAddress],
            paddedPlaintext: alicePlaintext,
            senderCertificate: senderCertificate,
            groupId: Data(),
            distributionId: distributionId,
            contentHint: .implicit,
            protocolContext: nil).map { $0 }

        // This splits out irrelevant per-recipient data from the shared sender key message
        // This is only necessary in tests. The server would usually handle this.
        let singleRecipientCiphertext = try! sealedSenderMultiRecipientMessageForSingleRecipient(aliceCiphertext)

        // Test: Bob decrypts the ciphertext
        let bobCipher = try! bobMockClient.createSecretSessionCipher()
        let bobPlaintext = try! bobCipher.decryptMessage(
            trustRoot: trustRoot.publicKey,
            cipherTextData: Data(singleRecipientCiphertext),
            timestamp: 31335,
            protocolContext: nil)

        // Verify
        XCTAssertEqual(String(data: bobPlaintext.paddedPayload, encoding: .utf8), "beltalowda")
        XCTAssertEqual(bobPlaintext.senderAddress, aliceMockClient.address)
        XCTAssertEqual(bobPlaintext.senderDeviceId, Int(aliceMockClient.deviceId))
        XCTAssertEqual(bobPlaintext.messageType, .senderKey)
    }

    func testGroupEncryptDecrypt_Failure() {
        // Setup: Initialize sessions and sender certificate
        let aliceMockClient = MockClient(address: MockClient.aliceAddress, deviceId: 1, registrationId: 1234)
        let bobMockClient = MockClient(address: MockClient.bobAddress, deviceId: 1, registrationId: 1235)
        initializeSessions(aliceMockClient: aliceMockClient, bobMockClient: bobMockClient)

        let trustRoot = IdentityKeyPair.generate()
        let senderCertificate = createCertificateFor(
            trustRoot: trustRoot,
            senderAddress: aliceMockClient.address,
            senderDeviceId: UInt32(aliceMockClient.deviceId),
            identityKey: aliceMockClient.identityKeyPair.publicKey,
            expirationTimestamp: 31337)

        // Setup: Alice creates a sender key
        // Test: Bob intentionally does not process Alice's SKDM to simulate an unsent key
        let distributionId = UUID()
        let _ = try! SenderKeyDistributionMessage(
            from: aliceMockClient.protocolAddress,
            distributionId: distributionId,
            store: aliceMockClient.senderKeyStore,
            context: NullContext())

        // Test: Alice encrypt's a message using `groupEncryptMessage`
        let aliceCipher = try! aliceMockClient.createSecretSessionCipher()
        let alicePlaintext = "beltalowda".data(using: String.Encoding.utf8)!
        let aliceCiphertext = try! aliceCipher.groupEncryptMessage(
            recipients: [bobMockClient.protocolAddress],
            paddedPlaintext: alicePlaintext,
            senderCertificate: senderCertificate,
            groupId: "inyalowda".data(using: String.Encoding.utf8)!,
            distributionId: distributionId,
            contentHint: .resendable,
            protocolContext: nil).map { $0 }

        // This splits out irrelevant per-recipient data from the shared sender key message
        // This is only necessary in tests. The server would usually handle this.
        let singleRecipientCiphertext = try! sealedSenderMultiRecipientMessageForSingleRecipient(aliceCiphertext)

        // Test: Bob decrypts the ciphertext
        let bobCipher = try! bobMockClient.createSecretSessionCipher()
        do {
            _ = try bobCipher.decryptMessage(
                trustRoot: trustRoot.publicKey,
                cipherTextData: Data(singleRecipientCiphertext),
                timestamp: 31335,
                protocolContext: nil)
            XCTFail("Decryption should have failed.")
        } catch let knownSenderError as SecretSessionKnownSenderError {
            // Verify: We need to make sure that the sender, group, and contentHint are preserved
            // through decryption failures because of missing a missing sender key. This will
            // help with recovery.
            XCTAssertEqual(knownSenderError.senderAddress, aliceMockClient.address)
            XCTAssertEqual(knownSenderError.senderDeviceId, UInt32(aliceMockClient.deviceId))
            XCTAssertEqual(Data(knownSenderError.groupId!), "inyalowda".data(using: String.Encoding.utf8)!)
            XCTAssertEqual(knownSenderError.contentHint, .resendable)
            XCTAssertNoThrow(
                try DecryptionErrorMessage(
                    originalMessageBytes: knownSenderError.unsealedContent,
                    type: knownSenderError.cipherType,
                    timestamp: 31335,
                    originalSenderDeviceId: knownSenderError.senderDeviceId
                )
            )

            if case SignalError.invalidState(_) = knownSenderError.underlyingError {
                // Expected
            } else {
                XCTFail()
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

     // MARK: - Utils

    // private SenderCertificate createCertificateFor(ECKeyPair trustRoot, String sender, int deviceId, ECPublicKey identityKey, long expires)
    //     throws InvalidKeyException, InvalidCertificateException, InvalidProtocolBufferException {
    private func createCertificateFor(trustRoot: IdentityKeyPair,
                                      senderAddress: SignalServiceAddress,
                                      senderDeviceId: UInt32,
                                      identityKey: PublicKey,
                                      expirationTimestamp: UInt64) -> SenderCertificate {
        let serverKey = IdentityKeyPair.generate()
        let serverCertificate = try! ServerCertificate(keyId: 1,
                                                       publicKey: serverKey.publicKey,
                                                       trustRoot: trustRoot.privateKey)
        return try! SenderCertificate(sender: SealedSenderAddress(e164: senderAddress.phoneNumber,
                                                                  uuidString: senderAddress.uuidString!,
                                                                  deviceId: senderDeviceId),
                                      publicKey: identityKey,
                                      expiration: expirationTimestamp,
                                      signerCertificate: serverCertificate,
                                      signerKey: serverKey.privateKey)
    }

    // private void initializeSessions(TestInMemorySignalProtocolStore aliceStore, TestInMemorySignalProtocolStore bobStore)
    //     throws InvalidKeyException, UntrustedIdentityException
    private func initializeSessions(aliceMockClient: MockClient, bobMockClient: MockClient) {
        aliceMockClient.initializeSession(with: bobMockClient)
    }
}
