//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit
import LibSignalClient

class MessageDecryptionTest: SSKBaseTestSwift {
    let localE164Identifier = "+13235551234"
    let localAci = UUID()
    let localPni = UUID()

    let remoteE164Identifier = "+14715355555"
    lazy var remoteClient: TestSignalClient = FakeSignalClient.generate(e164Identifier: remoteE164Identifier)

    let localClient = LocalSignalClient()
    let localPniClient = LocalSignalClient(identity: .pni)
    let runner = TestProtocolRunner()

    let sealedSenderTrustRoot = Curve25519.generateKeyPair()

    private var fakeMessageSender: FakeMessageSender {
        MockSSKEnvironment.shared.messageSender as! FakeMessageSender
    }

    // MARK: - Hooks

    override func setUp() {
        super.setUp()

        // ensure local client has necessary "registered" state
        identityManager.generateAndPersistNewIdentityKey(for: .aci)
        identityManager.generateAndPersistNewIdentityKey(for: .pni)
        tsAccountManager.registerForTests(withLocalNumber: localE164Identifier, uuid: localAci, pni: localPni)

        (notificationsManager as! NoopNotificationsManager).expectErrors = true
        (udManager as! OWSUDManagerImpl).trustRoot = try! sealedSenderTrustRoot.ecPublicKey()
    }

    // MARK: - Tests

    private let message = "abc"

    private func generateAndDecrypt(
        type: SSKProtoEnvelopeType,
        destinationIdentity: OWSIdentity,
        destinationServiceId: ServiceId? = nil,
        prepareForDecryption: (SignalProtocolStore, SDSAnyWriteTransaction) -> Void = { _, _ in },
        handleResult: (Result<DecryptedIncomingEnvelope, Error>, SSKProtoEnvelope) -> Void
    ) {
        write { transaction in
            let localClient: TestSignalClient
            let localDestinationServiceId: ServiceId
            let localProtocolStore: SignalProtocolStore
            switch destinationIdentity {
            case .aci:
                localClient = self.localClient
                localDestinationServiceId = Aci(fromUUID: localAci)
                localProtocolStore = self.localClient.protocolStore
            case .pni:
                localClient = self.localPniClient
                localDestinationServiceId = Pni(fromUUID: localPni)
                localProtocolStore = self.localPniClient.protocolStore
            }

            switch type {
            case .ciphertext:
                try! runner.initialize(senderClient: remoteClient,
                                       recipientClient: localClient,
                                       transaction: transaction)
            case .prekeyBundle, .unidentifiedSender:
                try! runner.initializePreKeys(senderClient: remoteClient,
                                              recipientClient: localClient,
                                              transaction: transaction)
            default:
                XCTFail("unsupported envelope type for this test: \(type)")
                return
            }

            var contentProto = SignalServiceProtos_Content()
            contentProto.dataMessage.body = message

            let ciphertext = try! runner.encrypt(try! contentProto.serializedData().paddedMessageBody,
                                                 senderClient: remoteClient,
                                                 recipient: localClient.protocolAddress,
                                                 context: transaction)

            let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: Date.ows_millisecondTimestamp())
            envelopeBuilder.setType(type)
            envelopeBuilder.setDestinationServiceID((destinationServiceId ?? localDestinationServiceId).serviceIdString)
            envelopeBuilder.setServerTimestamp(Date.ows_millisecondTimestamp())

            if type == .unidentifiedSender {
                let senderCert = SMKSecretSessionCipherTest.createCertificateFor(
                    trustRoot: sealedSenderTrustRoot.identityKeyPair,
                    senderAddress: try! SealedSenderAddress(
                        e164: remoteClient.e164Identifier,
                        aci: remoteClient.serviceId as! Aci,
                        deviceId: remoteClient.deviceId
                    ),
                    identityKey: remoteClient.identityKeyPair.identityKeyPair.publicKey,
                    expirationTimestamp: 13337)
                let usmc = try! UnidentifiedSenderMessageContent(ciphertext,
                                                                 from: senderCert,
                                                                 contentHint: .default,
                                                                 groupId: [])
                envelopeBuilder.setContent(Data(try! sealedSenderEncrypt(usmc,
                                                                         for: localClient.protocolAddress,
                                                                         identityStore: remoteClient.identityKeyStore,
                                                                         context: transaction)))
                envelopeBuilder.setServerTimestamp(13336)
            } else {
                envelopeBuilder.setSourceServiceID(remoteClient.serviceId.serviceIdString)
                envelopeBuilder.setSourceDevice(remoteClient.deviceId)
                envelopeBuilder.setContent(Data(ciphertext.serialize()))
            }

            let envelope = try! envelopeBuilder.build()

            prepareForDecryption(localProtocolStore, transaction)

            let localIdentifiers = tsAccountManager.localIdentifiers(transaction: transaction)!
            let decryptedEnvelope: Result<DecryptedIncomingEnvelope, Error> = Result {
                let validatedEnvelope = try ValidatedIncomingEnvelope(envelope, localIdentifiers: localIdentifiers)
                switch validatedEnvelope.kind {
                case .serverReceipt:
                    owsFail("Not supported.")
                case .unidentifiedSender:
                    return try messageDecrypter.decryptUnidentifiedSenderEnvelope(
                        validatedEnvelope,
                        localIdentifiers: localIdentifiers,
                        localDeviceId: tsAccountManager.storedDeviceId(transaction: transaction),
                        tx: transaction
                    )
                case .identifiedSender(let cipherType):
                    return try messageDecrypter.decryptIdentifiedEnvelope(
                        validatedEnvelope,
                        cipherType: cipherType,
                        tx: transaction
                    )
                }
            }
            handleResult(decryptedEnvelope, envelope)
        }
    }

    private func expectDecryptsSuccessfully(type: SSKProtoEnvelopeType, destinationIdentity: OWSIdentity) {
        generateAndDecrypt(type: type, destinationIdentity: destinationIdentity) { result, originalEnvelope in
            let decryptedEnvelope = try! result.get()
            XCTAssertEqual(decryptedEnvelope.localIdentity, destinationIdentity)
            XCTAssertEqual(decryptedEnvelope.content?.dataMessage?.body, message)

            if type == .unidentifiedSender {
                XCTAssertNotIdentical(decryptedEnvelope.envelope, originalEnvelope)
            } else {
                XCTAssertIdentical(decryptedEnvelope.envelope, originalEnvelope)
            }
        }
    }

    private func expectDecryptionFailure(type: SSKProtoEnvelopeType,
                                         destinationIdentity: OWSIdentity,
                                         destinationServiceId: ServiceId? = nil,
                                         prepareForDecryption: (SignalProtocolStore, SDSAnyWriteTransaction) -> Void = { _, _ in },
                                         isExpectedError: (Error) -> Bool) {
        generateAndDecrypt(
            type: type,
            destinationIdentity: destinationIdentity,
            destinationServiceId: destinationServiceId,
            prepareForDecryption: prepareForDecryption
        ) { result, _ in
            switch result {
            case .success:
                XCTFail("should not have decrypted successfully")
            case .failure(let error):
                XCTAssert(isExpectedError(error), "unexpected error: \(error)")
            }
        }
    }

    func testDecryptWhisperExplicitAci() {
        expectDecryptsSuccessfully(type: .ciphertext, destinationIdentity: .aci)
    }

    func testDecryptWhisperPni() {
        expectDecryptionFailure(type: .ciphertext, destinationIdentity: .pni) { error in
            if case MessageProcessingError.invalidMessageTypeForDestinationUuid = error {
                return true
            }
            return false
        }
    }

    func testDecryptPreKeyExplicitAci() {
        expectDecryptsSuccessfully(type: .prekeyBundle, destinationIdentity: .aci)
    }

    func testDecryptPreKeyPni() {
        expectDecryptsSuccessfully(type: .prekeyBundle, destinationIdentity: .pni)
    }

    func testDecryptPreKeyPniWithAciDestinationUuid() {
        expectDecryptionFailure(type: .prekeyBundle,
                                destinationIdentity: .pni,
                                destinationServiceId: localClient.serviceId) { error in
            if let error = error as? OWSError {
                let underlyingError = error.errorUserInfo[NSUnderlyingErrorKey]
                if case SSKSignedPreKeyStore.Error.noPreKeyWithId(_)? = underlyingError {
                    return true
                }
            }
            return false
        }
    }

    func testDecryptPreKeyPniWithWrongDestinationUuid() {
        expectDecryptionFailure(type: .prekeyBundle,
                                destinationIdentity: .pni,
                                destinationServiceId: Pni.randomForTesting()) { error in
            if case MessageProcessingError.wrongDestinationUuid = error {
                return true
            }
            return false
        }
    }

    func testDecryptSealedSenderPreKeyPni() {
        expectDecryptionFailure(type: .unidentifiedSender, destinationIdentity: .pni) { error in
            if case MessageProcessingError.invalidMessageTypeForDestinationUuid = error {
                return true
            }
            return false
        }
    }

    private func waitForResendRequestRatchetKey(line: UInt = #line) -> Promise<PublicKey> {
        let (promise, future) = Promise<PublicKey>.pending()

        fakeMessageSender.sendMessageWasCalledBlock = { message in
            guard let resendRequest = message as? OWSOutgoingResendRequest else {
                return
            }
            let decryptionError = try! DecryptionErrorMessage(bytes: resendRequest.decryptionErrorData)
            if let ratchetKey = decryptionError.ratchetKey {
                future.resolve(ratchetKey)
            } else {
                XCTFail("missing ratchet key", line: line)
            }

            self.fakeMessageSender.sendMessageWasCalledBlock = nil
        }
        return promise
    }

    private func checkRemoteRatchetKey(expected: PublicKey) {
        guard let session = try! remoteClient.sessionStore.loadSession(for: localClient.protocolAddress,
                                                                       context: NullContext()) else {
            XCTFail("no session established")
            return
        }
        XCTAssert(try! session.currentRatchetKeyMatches(expected))
    }

    func testMissingSignedPreKey() {
        sskJobQueues.messageSenderJobQueue.setup()

        let requestRatchetKey = waitForResendRequestRatchetKey()

        expectDecryptionFailure(type: .prekeyBundle,
                                destinationIdentity: .aci,
                                prepareForDecryption: { protocolStore, transaction in
                protocolStore.signedPreKeyStore.removeAll(tx: transaction.asV2Write)
        }) { error in
            if let error = error as? OWSError {
                let underlyingError = error.errorUserInfo[NSUnderlyingErrorKey]
                if case SSKSignedPreKeyStore.Error.noPreKeyWithId(_)? = underlyingError {
                    return true
                }
            }
            return false
        }

        checkRemoteRatchetKey(expected: requestRatchetKey.expect(timeout: 1))

        let sealedSenderResendRequestRatchetKey = waitForResendRequestRatchetKey()

        expectDecryptionFailure(type: .unidentifiedSender,
                                destinationIdentity: .aci,
                                prepareForDecryption: { protocolStore, transaction in
            protocolStore.signedPreKeyStore.removeAll(tx: transaction.asV2Write)
        }) { error in
            if let error = error as? OWSError {
                let underlyingError = error.errorUserInfo[NSUnderlyingErrorKey]
                if case SSKSignedPreKeyStore.Error.noPreKeyWithId(_)? = underlyingError {
                    return true
                }
            }
            return false
        }

        checkRemoteRatchetKey(expected: sealedSenderResendRequestRatchetKey.expect(timeout: 1))
    }

    func testMissingOneTimePreKey() {
        sskJobQueues.messageSenderJobQueue.setup()

        let requestRatchetKey = waitForResendRequestRatchetKey()

        expectDecryptionFailure(type: .prekeyBundle,
                                destinationIdentity: .aci,
                                prepareForDecryption: { protocolStore, transaction in
            protocolStore.preKeyStore.removeAll(tx: transaction.asV2Write)
        }) { error in
            if let error = error as? OWSError {
                let underlyingError = error.errorUserInfo[NSUnderlyingErrorKey]
                if case SSKPreKeyStore.Error.noPreKeyWithId(_)? = underlyingError {
                    return true
                }
            }
            return false
        }

        checkRemoteRatchetKey(expected: requestRatchetKey.expect(timeout: 1))

        let sealedSenderResendRequestRatchetKey = waitForResendRequestRatchetKey()

        expectDecryptionFailure(type: .unidentifiedSender,
                                destinationIdentity: .aci,
                                prepareForDecryption: { protocolStore, transaction in
            protocolStore.preKeyStore.removeAll(tx: transaction.asV2Write)
        }) { error in
            if let error = error as? OWSError {
                let underlyingError = error.errorUserInfo[NSUnderlyingErrorKey]
                if case SSKPreKeyStore.Error.noPreKeyWithId(_)? = underlyingError {
                    return true
                }
            }
            return false
        }

        checkRemoteRatchetKey(expected: sealedSenderResendRequestRatchetKey.expect(timeout: 1))
    }
}
