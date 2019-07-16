//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

/// A helper for tests which can initializes Signal Protocol sessions
/// and then encrypt and decrypt messages for those sessions.
public struct TestProtocolRunner {

    public init() { }

    public func initialize(senderClient: SignalClient, recipientClient: SignalClient, protocolContext: SPKProtocolWriteContext?) throws {
        try SignalProtocolHelper.sessionInitialization(withAliceSessionStore: senderClient.sessionStore,
                                                       aliceIdentityKeyStore: senderClient.identityKeyStore,
                                                       aliceIdentifier: senderClient.e164Identifier,
                                                       aliceIdentityKeyPair: senderClient.identityKeyPair,
                                                       bobSessionStore: recipientClient.sessionStore,
                                                       bobIdentityKeyStore: recipientClient.identityKeyStore,
                                                       bobIdentifier: recipientClient.e164Identifier,
                                                       bobIdentityKeyPair: recipientClient.identityKeyPair,
                                                       protocolContext: protocolContext)
    }

    public func encrypt(plaintext: Data, senderClient: SignalClient, recipientE164: SignalE164Identifier, protocolContext: SPKProtocolWriteContext?) throws -> CipherMessage {
        let sessionCipher = try senderClient.sessionCipher(for: recipientE164)
        return try sessionCipher.encryptMessage(plaintext, protocolContext: protocolContext)
    }

    public func decrypt(cipherMessage: CipherMessage, recipientClient: SignalClient, senderE164: SignalE164Identifier, protocolContext: SPKProtocolWriteContext?) throws -> Data {
        let sessionCipher = try recipientClient.sessionCipher(for: senderE164)
        return try sessionCipher.decrypt(cipherMessage, protocolContext: protocolContext)
    }
}

public typealias SignalE164Identifier = String
public typealias SignalUUIDIdentifier = String

/// Represents a Signal installation, it can represent the local client or
/// a remote client.
public protocol SignalClient {
    var identityKeyPair: ECKeyPair { get }
    var identityKey: IdentityKey { get }
    var e164Identifier: SignalE164Identifier { get }
    var uuidIdentifier: SignalUUIDIdentifier { get }
    var uuid: UUID { get }
    var deviceId: UInt32 { get }

    var sessionStore: SessionStore { get }
    var preKeyStore: PreKeyStore { get }
    var signedPreKeyStore: SignedPreKeyStore { get }
    var identityKeyStore: IdentityKeyStore { get }

    func sessionCipher(for e164Identifier: SignalE164Identifier) throws -> SessionCipher
}

public extension SignalClient {
    var identityKey: IdentityKey {
        return identityKeyPair.publicKey
    }

    var uuidIdentifier: SignalUUIDIdentifier {
        return uuid.uuidString
    }

    func sessionCipher(for e164Identifier: SignalE164Identifier) throws -> SessionCipher {
        return SessionCipher(sessionStore: sessionStore,
                             preKeyStore: preKeyStore,
                             signedPreKeyStore: signedPreKeyStore,
                             identityKeyStore: identityKeyStore,
                             recipientId: e164Identifier,
                             deviceId: 1)
    }
}

/// Can be used to represent the protocol state held by a remote client.
/// i.e. someone who's sending messages to the local client.
public struct FakeSignalClient: SignalClient {

    public var sessionStore: SessionStore { return protocolStore }
    public var preKeyStore: PreKeyStore { return protocolStore }
    public var signedPreKeyStore: SignedPreKeyStore { return protocolStore }
    public var identityKeyStore: IdentityKeyStore { return protocolStore }

    public let e164Identifier: SignalE164Identifier
    public let uuid: UUID
    public let deviceId: UInt32
    public let identityKeyPair: ECKeyPair
    public let protocolStore: AxolotlStore

    public static func generate(e164Identifier: SignalE164Identifier) -> FakeSignalClient {
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

    public var e164Identifier: SignalE164Identifier {
        return TSAccountManager.localNumber()!
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
