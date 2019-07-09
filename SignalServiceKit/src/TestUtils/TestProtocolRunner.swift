//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

#if DEBUG
/// A helper for tests which can initializes Signal Protocol sessions
/// and then encrypt and decrypt messages for those sessions.
public struct TestProtocolRunner {

    public init() { }

    let accountIdentifierFinder  = OWSAccountIdFinder()

    public func initialize(senderClient: SignalClient, recipientClient: SignalClient, transaction: SDSAnyWriteTransaction) throws {

        let senderIdentifier = accountIdentifierFinder.ensureAccountId(forAddress: senderClient.address, transaction: transaction)
        let recipientIdentifier = accountIdentifierFinder.ensureAccountId(forAddress: recipientClient.address, transaction: transaction)

        try SignalProtocolHelper.sessionInitialization(withAliceSessionStore: senderClient.sessionStore,
                                                       aliceIdentityKeyStore: senderClient.identityKeyStore,
                                                       aliceIdentifier: senderIdentifier,
                                                       aliceIdentityKeyPair: senderClient.identityKeyPair,
                                                       bobSessionStore: recipientClient.sessionStore,
                                                       bobIdentityKeyStore: recipientClient.identityKeyStore,
                                                       bobIdentifier: recipientIdentifier,
                                                       bobIdentityKeyPair: recipientClient.identityKeyPair,
                                                       protocolContext: transaction)
    }

    public func encrypt(plaintext: Data, senderClient: SignalClient, recipientAccountId: SignalAccountIdentifier, protocolContext: SPKProtocolWriteContext?) throws -> CipherMessage {
        let sessionCipher = try senderClient.sessionCipher(for: recipientAccountId)
        return try sessionCipher.encryptMessage(plaintext, protocolContext: protocolContext)
    }

    public func decrypt(cipherMessage: CipherMessage, recipientClient: SignalClient, senderAccountId: SignalAccountIdentifier, protocolContext: SPKProtocolWriteContext?) throws -> Data {
        let sessionCipher = try recipientClient.sessionCipher(for: senderAccountId)
        return try sessionCipher.decrypt(cipherMessage, protocolContext: protocolContext)
    }
}

public typealias SignalE164Identifier = String
public typealias SignalUUIDIdentifier = String
public typealias SignalAccountIdentifier = String

/// Represents a Signal installation, it can represent the local client or
/// a remote client.
public protocol SignalClient {
    var identityKeyPair: ECKeyPair { get }
    var identityKey: IdentityKey { get }
    var e164Identifier: SignalE164Identifier? { get }
    var uuidIdentifier: SignalUUIDIdentifier { get }
    var uuid: UUID { get }
    var deviceId: UInt32 { get }
    var address: SignalServiceAddress { get }

    var sessionStore: SessionStore { get }
    var preKeyStore: PreKeyStore { get }
    var signedPreKeyStore: SignedPreKeyStore { get }
    var identityKeyStore: IdentityKeyStore { get }

    func sessionCipher(for accountId: SignalAccountIdentifier) throws -> SessionCipher
}

public extension SignalClient {
    var identityKey: IdentityKey {
        return identityKeyPair.publicKey
    }

    var uuidIdentifier: SignalUUIDIdentifier {
        return uuid.uuidString
    }

    var address: SignalServiceAddress {
        if FeatureFlags.allowUUIDOnlyContacts {
            return SignalServiceAddress(uuid: uuid, phoneNumber: e164Identifier)
        } else {
            return SignalServiceAddress(phoneNumber: e164Identifier!)
        }
    }

    func sessionCipher(for e164Identifier: SignalE164Identifier) throws -> SessionCipher {
        return SessionCipher(sessionStore: sessionStore,
                             preKeyStore: preKeyStore,
                             signedPreKeyStore: signedPreKeyStore,
                             identityKeyStore: identityKeyStore,
                             recipientId: e164Identifier,
                             deviceId: 1)
    }

    var accountIdFinder: OWSAccountIdFinder {
        return OWSAccountIdFinder()
    }

    func accountId(transaction: SDSAnyWriteTransaction) -> String {
        return accountIdFinder.ensureAccountId(forAddress: address, transaction: transaction)
    }
}

/// Can be used to represent the protocol state held by a remote client.
/// i.e. someone who's sending messages to the local client.
public struct FakeSignalClient: SignalClient {

    public var sessionStore: SessionStore { return protocolStore }
    public var preKeyStore: PreKeyStore { return protocolStore }
    public var signedPreKeyStore: SignedPreKeyStore { return protocolStore }
    public var identityKeyStore: IdentityKeyStore { return protocolStore }

    public let e164Identifier: SignalE164Identifier?
    public let uuid: UUID
    public let deviceId: UInt32
    public let identityKeyPair: ECKeyPair
    public let protocolStore: AxolotlStore

    public static func generate() -> FakeSignalClient {
        return FakeSignalClient(e164Identifier: CommonGenerator.e164(),
                                uuid: UUID(),
                                deviceId: 1,
                                identityKeyPair: Curve25519.generateKeyPair(),
                                protocolStore: SPKMockProtocolStore())
    }

    public static func generate(e164Identifier: SignalE164Identifier?) -> FakeSignalClient {
        return FakeSignalClient(e164Identifier: e164Identifier,
                                uuid: UUID(),
                                deviceId: 1,
                                identityKeyPair: Curve25519.generateKeyPair(),
                                protocolStore: SPKMockProtocolStore())
    }
}

/// Represents the local user, backed by the same protocol stores, etc.
/// used in the app.
public struct LocalSignalClient: SignalClient {

    public init() { }

    public var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    public var identityKeyPair: ECKeyPair {
        return SSKEnvironment.shared.identityManager.identityKeyPair()!
    }

    public var e164Identifier: SignalE164Identifier? {
        return TSAccountManager.localNumber()
    }

    public var uuid: UUID {
        return TSAccountManager.sharedInstance().uuid!
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

public struct FakeService {
    public let localClient: LocalSignalClient
    public let runner: TestProtocolRunner

    public init(localClient: LocalSignalClient, runner: TestProtocolRunner) {
        self.localClient = localClient
        self.runner = runner
    }

    var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    public func envelopeBuilder(fromSenderClient senderClient: SignalClient) throws -> SSKProtoEnvelope.SSKProtoEnvelopeBuilder {
        let now = NSDate.ows_millisecondTimeStamp()
        let builder = SSKProtoEnvelope.builder(timestamp: now)
        builder.setType(.ciphertext)
        builder.setSourceDevice(senderClient.deviceId)

        let content = try buildEncryptedContentData(fromSenderClient: senderClient)
        builder.setContent(content)

        // builder.setServerTimestamp(serverTimestamp)
        // builder.setServerGuid(serverGuid)

        return builder
    }

    public func buildEncryptedContentData(fromSenderClient senderClient: SignalClient) throws -> Data {
        let plaintext = try buildContentData()
        let cipherMessage: CipherMessage = databaseStorage.writeReturningResult { transaction in
            return try! self.runner.encrypt(plaintext: plaintext,
                                            senderClient: senderClient,
                                            recipientAccountId: self.localClient.accountId(transaction: transaction),
                                            protocolContext: transaction)
        }

        assert(cipherMessage is WhisperMessage)
        return cipherMessage.serialized()
    }

    public func buildContentData() throws -> Data {
        let messageText = "Those who stands for nothing will fall for anything"
        let dataMessageBuilder = SSKProtoDataMessage.builder()
        dataMessageBuilder.setBody(messageText)

        let contentBuilder = SSKProtoContent.builder()
        contentBuilder.setDataMessage(try dataMessageBuilder.build())

        return try contentBuilder.buildSerializedData()
    }
}

#endif
