//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalClient

#if TESTABLE_BUILD
/// A helper for tests which can initializes Signal Protocol sessions
/// and then encrypt and decrypt messages for those sessions.
public struct TestProtocolRunner {

    public init() { }

    public func initialize(senderClient: TestSignalClient, recipientClient: TestSignalClient, transaction: SDSAnyWriteTransaction) throws {

        _ = OWSAccountIdFinder.ensureAccountId(forAddress: senderClient.address, transaction: transaction)
        _ = OWSAccountIdFinder.ensureAccountId(forAddress: recipientClient.address, transaction: transaction)

        let bobPreKey = PrivateKey.generate()
        let bobSignedPreKey = PrivateKey.generate()

        let bobSignedPreKeyPublic = bobSignedPreKey.publicKey.serialize()

        let bobIdentityKey = recipientClient.identityKeyPair.identityKeyPair
        let bobSignedPreKeySignature = bobIdentityKey.privateKey.generateSignature(message: bobSignedPreKeyPublic)
        let bobRegistrationId = try recipientClient.identityKeyStore.localRegistrationId(context: transaction)

        let prekeyId: UInt32 = 4570
        let signedPrekeyId: UInt32 = 3006

        let bobBundle = try PreKeyBundle(registrationId: bobRegistrationId,
                                         deviceId: recipientClient.deviceId,
                                         prekeyId: prekeyId,
                                         prekey: bobPreKey.publicKey,
                                         signedPrekeyId: signedPrekeyId,
                                         signedPrekey: bobSignedPreKey.publicKey,
                                         signedPrekeySignature: bobSignedPreKeySignature,
                                         identity: bobIdentityKey.identityKey)

        // Alice processes the bundle:
        try processPreKeyBundle(bobBundle,
                                for: recipientClient.protocolAddress,
                                sessionStore: senderClient.sessionStore,
                                identityStore: senderClient.identityKeyStore,
                                context: transaction)

        // Bob does the same:
        try recipientClient.preKeyStore.storePreKey(PreKeyRecord(id: prekeyId, privateKey: bobPreKey),
                                                    id: prekeyId,
                                                    context: transaction)

        try recipientClient.signedPreKeyStore.storeSignedPreKey(
            SignedPreKeyRecord(
                id: signedPrekeyId,
                timestamp: 42000,
                privateKey: bobSignedPreKey,
                signature: bobSignedPreKeySignature
            ),
            id: signedPrekeyId,
            context: transaction)

        // Then Alice sends a message to Bob so he gets her pre-key as well.
        let aliceMessage = try encrypt(Data(),
                                       senderClient: senderClient,
                                       recipient: recipientClient.protocolAddress,
                                       context: transaction)
        _ = try signalDecryptPreKey(message: PreKeySignalMessage(bytes: aliceMessage.serialize()),
                                    from: senderClient.protocolAddress,
                                    sessionStore: recipientClient.sessionStore,
                                    identityStore: recipientClient.identityKeyStore,
                                    preKeyStore: recipientClient.preKeyStore,
                                    signedPreKeyStore: recipientClient.signedPreKeyStore,
                                    context: transaction)

        // Finally, Bob sends a message back to acknowledge the pre-key.
        let bobMessage = try encrypt(Data(),
                                     senderClient: recipientClient,
                                     recipient: senderClient.protocolAddress,
                                     context: transaction)
        _ = try signalDecrypt(message: SignalMessage(bytes: bobMessage.serialize()),
                              from: recipientClient.protocolAddress,
                              sessionStore: senderClient.sessionStore,
                              identityStore: senderClient.identityKeyStore,
                              context: transaction)
    }

    public func encrypt(_ plaintext: Data,
                        senderClient: TestSignalClient,
                        recipient: ProtocolAddress,
                        context: StoreContext) throws -> CiphertextMessage {
        return try signalEncrypt(message: plaintext,
                                 for: recipient,
                                 sessionStore: senderClient.sessionStore,
                                 identityStore: senderClient.identityKeyStore,
                                 context: context)
    }

    public func decrypt(_ cipherMessage: CiphertextMessage,
                        recipientClient: TestSignalClient,
                        sender: ProtocolAddress,
                        context: StoreContext) throws -> Data {
        owsAssert(cipherMessage.messageType == .whisper, "only bare SignalMessages are supported")
        let message = try SignalMessage(bytes: cipherMessage.serialize())
        return Data(try signalDecrypt(message: message,
                                      from: sender,
                                      sessionStore: recipientClient.sessionStore,
                                      identityStore: recipientClient.identityKeyStore,
                                      context: context))
    }
}

public typealias SignalE164Identifier = String
public typealias SignalUUIDIdentifier = String
public typealias SignalAccountIdentifier = String

/// Represents a Signal installation, it can represent the local client or
/// a remote client.
public protocol TestSignalClient {
    var identityKeyPair: ECKeyPair { get }
    var identityKey: IdentityKey { get }
    var e164Identifier: SignalE164Identifier? { get }
    var uuidIdentifier: SignalUUIDIdentifier { get }
    var uuid: UUID { get }
    var deviceId: UInt32 { get }
    var address: SignalServiceAddress { get }
    var protocolAddress: ProtocolAddress { get }

    var sessionStore: SessionStore { get }
    var preKeyStore: PreKeyStore { get }
    var signedPreKeyStore: SignedPreKeyStore { get }
    var identityKeyStore: IdentityKeyStore { get }
}

public extension TestSignalClient {
    var identityKey: IdentityKey {
        return identityKeyPair.publicKey
    }

    var uuidIdentifier: SignalUUIDIdentifier {
        return uuid.uuidString
    }

    var address: SignalServiceAddress {
        return SignalServiceAddress(uuid: uuid, phoneNumber: e164Identifier)
    }

    var protocolAddress: ProtocolAddress {
        return try! ProtocolAddress(name: uuidIdentifier, deviceId: deviceId)
    }

    func accountId(transaction: SDSAnyWriteTransaction) -> String {
        return OWSAccountIdFinder.ensureAccountId(forAddress: address, transaction: transaction)
    }
}

/// Can be used to represent the protocol state held by a remote client.
/// i.e. someone who's sending messages to the local client.
public struct FakeSignalClient: TestSignalClient {

    public var sessionStore: SessionStore { return protocolStore }
    public var preKeyStore: PreKeyStore { return protocolStore }
    public var signedPreKeyStore: SignedPreKeyStore { return protocolStore }
    public var identityKeyStore: IdentityKeyStore { return protocolStore }

    public let e164Identifier: SignalE164Identifier?
    public let uuid: UUID
    public let protocolStore: InMemorySignalProtocolStore

    public var deviceId: UInt32 { return 1 }
    public var identityKeyPair: ECKeyPair {
        return ECKeyPair(try! protocolStore.identityKeyPair(context: NullContext()))
    }

    public static func generate() -> FakeSignalClient {
        return FakeSignalClient(e164Identifier: CommonGenerator.e164(),
                                uuid: UUID(),
                                protocolStore: InMemorySignalProtocolStore(identity: .generate(), deviceId: 1))
    }

    public static func generate(e164Identifier: SignalE164Identifier? = nil, uuid: UUID? = nil) -> FakeSignalClient {
        return FakeSignalClient(e164Identifier: e164Identifier,
                                uuid: uuid ?? UUID(),
                                protocolStore: InMemorySignalProtocolStore(identity: .generate(), deviceId: 1))
    }
}

/// Represents the local user, backed by the same protocol stores, etc.
/// used in the app.
public struct LocalSignalClient: TestSignalClient {

    public init() { }

    public var identityKeyPair: ECKeyPair {
        return SSKEnvironment.shared.identityManager.identityKeyPair()!
    }

    public var e164Identifier: SignalE164Identifier? {
        return TSAccountManager.localNumber
    }

    public var uuid: UUID {
        return TSAccountManager.shared.localUuid!
    }

    public let deviceId: UInt32 = 1

    public var sessionStore: SessionStore {
        return SSKEnvironment.shared.sessionStore
    }

    public var preKeyStore: PreKeyStore {
        return SSKEnvironment.shared.preKeyStore
    }

    public var signedPreKeyStore: SignedPreKeyStore {
        return SSKEnvironment.shared.signedPreKeyStore
    }

    public var identityKeyStore: IdentityKeyStore {
        return SSKEnvironment.shared.identityManager
    }
}

var envelopeId: UInt64 = 0

public struct FakeService: Dependencies {
    public let localClient: LocalSignalClient
    public let runner: TestProtocolRunner

    public init(localClient: LocalSignalClient, runner: TestProtocolRunner) {
        self.localClient = localClient
        self.runner = runner
    }

    public func envelopeBuilder(fromSenderClient senderClient: TestSignalClient, bodyText: String? = nil) throws -> SSKProtoEnvelope.SSKProtoEnvelopeBuilder {
        envelopeId += 1
        let builder = SSKProtoEnvelope.builder(timestamp: envelopeId)
        builder.setType(.ciphertext)
        builder.setSourceDevice(senderClient.deviceId)

        let content = try buildEncryptedContentData(fromSenderClient: senderClient, bodyText: bodyText)
        builder.setContent(content)

        // builder.setServerTimestamp(serverTimestamp)
        // builder.setServerGuid(serverGuid)

        return builder
    }

    public func buildEncryptedContentData(fromSenderClient senderClient: TestSignalClient, bodyText: String?) throws -> Data {
        let plaintext = try buildContentData(bodyText: bodyText)
        let cipherMessage: CiphertextMessage = databaseStorage.write { transaction in
            return try! self.runner.encrypt(plaintext,
                                            senderClient: senderClient,
                                            recipient: self.localClient.protocolAddress,
                                            context: transaction)
        }

        assert(cipherMessage.messageType == .whisper)
        return Data(cipherMessage.serialize())
    }

    public func buildContentData(bodyText: String?) throws -> Data {
        let dataMessageBuilder = SSKProtoDataMessage.builder()
        if let bodyText = bodyText {
            dataMessageBuilder.setBody(bodyText)
        } else {
            dataMessageBuilder.setBody(CommonGenerator.paragraph)
        }

        let contentBuilder = SSKProtoContent.builder()
        contentBuilder.setDataMessage(try dataMessageBuilder.build())

        return try contentBuilder.buildSerializedData()
    }
}

#endif
