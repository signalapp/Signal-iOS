//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest
@testable import SignalServiceKit

class MessageDecryptionTest: SSKBaseTest {
    let localE164Identifier = "+13235551234"
    let localAci = UUID()
    let localPni = UUID()

    let remoteE164Identifier = "+14715355555"
    lazy var remoteClient: TestSignalClient = FakeSignalClient.generate(e164Identifier: remoteE164Identifier)

    private lazy var localClient = LocalSignalClient()
    private lazy var localPniClient = LocalSignalClient(identity: .pni)
    let runner = TestProtocolRunner()

    let sealedSenderTrustRoot = IdentityKeyPair.generate()

    private var fakeMessageSender: FakeMessageSender {
        SSKEnvironment.shared.messageSenderRef as! FakeMessageSender
    }

    // MARK: - Hooks

    override func setUp() {
        super.setUp()

        // ensure local client has necessary "registered" state
        let identityManager = DependenciesBridge.shared.identityManager
        identityManager.generateAndPersistNewIdentityKey(for: .aci)
        identityManager.generateAndPersistNewIdentityKey(for: .pni)
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .init(
                    aci: .init(fromUUID: localAci),
                    pni: .init(fromUUID: localPni),
                    e164: .init(localE164Identifier)!,
                ),
                tx: tx,
            )

            DependenciesBridge.shared.tsAccountManager.setRegistrationId(RegistrationIdGenerator.generate(), for: .aci, tx: tx)
            DependenciesBridge.shared.tsAccountManager.setRegistrationId(RegistrationIdGenerator.generate(), for: .pni, tx: tx)
        }

        (SSKEnvironment.shared.notificationPresenterRef as! NoopNotificationPresenterImpl).expectErrors = true
        (SSKEnvironment.shared.udManagerRef as! OWSUDManagerImpl).trustRoots = [sealedSenderTrustRoot.publicKey]
    }

    // MARK: - Tests

    private let message = "abc"

    private func generateAndDecrypt(
        type: SSKProtoEnvelopeType,
        destinationIdentity: OWSIdentity,
        destinationServiceId: ServiceId? = nil,
        hasSignedPreKey: Bool = true,
        hasOneTimePreKey: Bool = true,
        handleResult: (Result<DecryptedIncomingEnvelope, Error>, SSKProtoEnvelope) -> Void,
    ) {
        write { transaction in
            let localClient: TestSignalClient
            let localDestinationServiceId: ServiceId
            switch destinationIdentity {
            case .aci:
                localClient = self.localClient
                localDestinationServiceId = Aci(fromUUID: localAci)
            case .pni:
                localClient = self.localPniClient
                localDestinationServiceId = Pni(fromUUID: localPni)
            }

            switch type {
            case .ciphertext:
                try! runner.initialize(
                    senderClient: remoteClient,
                    recipientClient: localClient,
                    hasSignedPreKey: hasSignedPreKey,
                    hasOneTimePreKey: hasOneTimePreKey,
                    transaction: transaction,
                )
            case .prekeyBundle, .unidentifiedSender:
                try! runner.initializePreKeys(
                    senderClient: remoteClient,
                    recipientClient: localClient,
                    hasSignedPreKey: hasSignedPreKey,
                    hasOneTimePreKey: hasOneTimePreKey,
                    transaction: transaction,
                )
            default:
                XCTFail("unsupported envelope type for this test: \(type)")
                return
            }

            let timestamp = MessageTimestampGenerator.sharedInstance.generateTimestamp()

            var contentProto = SignalServiceProtos_Content()
            contentProto.dataMessage.timestamp = timestamp
            contentProto.dataMessage.body = message

            let ciphertext = try! runner.encrypt(
                try! contentProto.serializedData().paddedMessageBody,
                senderClient: remoteClient,
                recipient: localClient.protocolAddress,
                context: transaction,
            )

            let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: timestamp)
            envelopeBuilder.setType(type)
            envelopeBuilder.setDestinationServiceIDBinary((destinationServiceId ?? localDestinationServiceId).serviceIdBinary)
            envelopeBuilder.setServerTimestamp(Date.ows_millisecondTimestamp())

            if type == .unidentifiedSender {
                let senderCert = SMKSecretSessionCipherTest.createCertificateFor(
                    trustRoot: sealedSenderTrustRoot,
                    senderAddress: try! SealedSenderAddress(
                        e164: remoteClient.e164Identifier,
                        aci: remoteClient.serviceId as! Aci,
                        deviceId: remoteClient.deviceId,
                    ),
                    identityKey: remoteClient.identityKeyPair.identityKeyPair.publicKey,
                    expirationTimestamp: 13337,
                )
                let usmc = try! UnidentifiedSenderMessageContent(
                    ciphertext,
                    from: senderCert,
                    contentHint: .default,
                    groupId: [],
                )
                envelopeBuilder.setContent(try! sealedSenderEncrypt(
                    usmc,
                    for: localClient.protocolAddress,
                    identityStore: remoteClient.identityKeyStore,
                    context: transaction,
                ))
                envelopeBuilder.setServerTimestamp(13336)
            } else {
                envelopeBuilder.setSourceServiceIDBinary(remoteClient.serviceId.serviceIdBinary)
                envelopeBuilder.setSourceDevice(remoteClient.deviceId)
                envelopeBuilder.setContent(ciphertext.serialize())
            }

            let envelope = try! envelopeBuilder.build()

            let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)!
            let decryptedEnvelope: Result<DecryptedIncomingEnvelope, Error> = Result {
                let validatedEnvelope = try ValidatedIncomingEnvelope(envelope, localIdentifiers: localIdentifiers)
                switch validatedEnvelope.kind {
                case .serverReceipt:
                    owsFail("Not supported.")
                case .unidentifiedSender:
                    return try SSKEnvironment.shared.messageDecrypterRef.decryptUnidentifiedSenderEnvelope(
                        validatedEnvelope,
                        localIdentifiers: localIdentifiers,
                        localDeviceId: DependenciesBridge.shared.tsAccountManager.storedDeviceId(tx: transaction),
                        tx: transaction,
                    )
                case .identifiedSender(let cipherType):
                    return try SSKEnvironment.shared.messageDecrypterRef.decryptIdentifiedEnvelope(
                        validatedEnvelope,
                        cipherType: cipherType,
                        localIdentifiers: localIdentifiers,
                        tx: transaction,
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

    private func expectDecryptionFailure(
        type: SSKProtoEnvelopeType,
        destinationIdentity: OWSIdentity,
        destinationServiceId: ServiceId? = nil,
        hasSignedPreKey: Bool = true,
        hasOneTimePreKey: Bool = true,
        isExpectedError: (Error) -> Bool,
    ) {
        generateAndDecrypt(
            type: type,
            destinationIdentity: destinationIdentity,
            destinationServiceId: destinationServiceId,
            hasSignedPreKey: hasSignedPreKey,
            hasOneTimePreKey: hasOneTimePreKey,
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
        expectDecryptionFailure(
            type: .prekeyBundle,
            destinationIdentity: .pni,
            destinationServiceId: localClient.serviceId,
        ) { error in
            if let error = error as? OWSError {
                let underlyingError = error.errorUserInfo[NSUnderlyingErrorKey]
                if case SignalServiceKit.PreKeyStore.Error.noPreKeyWithId(_)? = underlyingError {
                    return true
                }
            }
            return false
        }
    }

    func testDecryptPreKeyPniWithWrongDestinationUuid() {
        expectDecryptionFailure(
            type: .prekeyBundle,
            destinationIdentity: .pni,
            destinationServiceId: Pni.randomForTesting(),
        ) { error in
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

        fakeMessageSender.stubbedFailingErrors = [nil]
        fakeMessageSender.sendMessageWasCalledBlock = { message in
            guard let resendRequest = message as? OWSOutgoingResendRequest else {
                return
            }
            self.fakeMessageSender.sendMessageWasCalledBlock = nil

            let decryptionError = try! DecryptionErrorMessage(bytes: resendRequest.decryptionErrorData)
            if let ratchetKey = decryptionError.ratchetKey {
                future.resolve(ratchetKey)
            } else {
                XCTFail("missing ratchet key", line: line)
            }
        }
        return promise
    }

    private func checkRemoteRatchetKey(expected: PublicKey) {
        guard
            let session = try! remoteClient.sessionStore.loadSession(
                for: localClient.protocolAddress,
                context: NullContext(),
            )
        else {
            XCTFail("no session established")
            return
        }
        XCTAssert(try! session.currentRatchetKeyMatches(expected))
    }

    func testMissingSignedPreKey() {
        SSKEnvironment.shared.messageSenderJobQueueRef.setUp()

        let requestRatchetKey = waitForResendRequestRatchetKey()

        expectDecryptionFailure(
            type: .prekeyBundle,
            destinationIdentity: .aci,
            hasSignedPreKey: false,
        ) { error in
            if let error = error as? OWSError {
                let underlyingError = error.errorUserInfo[NSUnderlyingErrorKey]
                if case SignalServiceKit.PreKeyStore.Error.noPreKeyWithId(_)? = underlyingError {
                    return true
                }
            }
            return false
        }

        checkRemoteRatchetKey(expected: requestRatchetKey.expect(timeout: 1))

        let sealedSenderResendRequestRatchetKey = waitForResendRequestRatchetKey()

        expectDecryptionFailure(
            type: .unidentifiedSender,
            destinationIdentity: .aci,
            hasSignedPreKey: false,
        ) { error in
            if let error = error as? OWSError {
                let underlyingError = error.errorUserInfo[NSUnderlyingErrorKey]
                if case SignalServiceKit.PreKeyStore.Error.noPreKeyWithId(_)? = underlyingError {
                    return true
                }
            }
            return false
        }

        checkRemoteRatchetKey(expected: sealedSenderResendRequestRatchetKey.expect(timeout: 1))
    }

    func testMissingOneTimePreKey() {
        SSKEnvironment.shared.messageSenderJobQueueRef.setUp()

        let requestRatchetKey = waitForResendRequestRatchetKey()

        expectDecryptionFailure(
            type: .prekeyBundle,
            destinationIdentity: .aci,
            hasOneTimePreKey: false,
        ) { error in
            if let error = error as? OWSError {
                let underlyingError = error.errorUserInfo[NSUnderlyingErrorKey]
                if case SignalServiceKit.PreKeyStore.Error.noPreKeyWithId(_)? = underlyingError {
                    return true
                }
            }
            return false
        }

        checkRemoteRatchetKey(expected: requestRatchetKey.expect(timeout: 1))

        let sealedSenderResendRequestRatchetKey = waitForResendRequestRatchetKey()

        expectDecryptionFailure(
            type: .unidentifiedSender,
            destinationIdentity: .aci,
            hasOneTimePreKey: false,
        ) { error in
            if let error = error as? OWSError {
                let underlyingError = error.errorUserInfo[NSUnderlyingErrorKey]
                if case SignalServiceKit.PreKeyStore.Error.noPreKeyWithId(_)? = underlyingError {
                    return true
                }
            }
            return false
        }

        checkRemoteRatchetKey(expected: sealedSenderResendRequestRatchetKey.expect(timeout: 1))
    }
}
