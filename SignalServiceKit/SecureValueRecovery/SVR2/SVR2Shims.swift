//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension SVR2 {
    public enum Shims {
        public typealias AppReadiness = _SVR2_AppReadinessShim
        public typealias OWS2FAManager = _SVR2_OWS2FAManagerShim
    }
    public enum Wrappers {
        public typealias AppReadiness = _SVR2_AppReadinessWrapper
        public typealias OWS2FAManager = _SVR2_OWS2FAManagerWrapper
    }
}

public protocol _SVR2_AppReadinessShim {

    var isMainApp: Bool { get }

    func runNowOrWhenMainAppDidBecomeReadyAsync(_ block: @escaping () -> Void)
}

public class _SVR2_AppReadinessWrapper: _SVR2_AppReadinessShim {

    public init() {}

    public var isMainApp: Bool {
        return CurrentAppContext().isMainApp
    }

    public func runNowOrWhenMainAppDidBecomeReadyAsync(_ block: @escaping () -> Void) {
        AppReadiness.runNowOrWhenMainAppDidBecomeReadyAsync(block)
    }
}

// MARK: - OWS2FAManager

public protocol _SVR2_OWS2FAManagerShim {
    func pinCode(transaction: DBReadTransaction) -> String?
    func markDisabled(transaction: DBWriteTransaction)
}

public class _SVR2_OWS2FAManagerWrapper: SVR2.Shims.OWS2FAManager {
    private let manager: OWS2FAManager
    public init(_ manager: OWS2FAManager) { self.manager = manager }

    public func pinCode(transaction: DBReadTransaction) -> String? {
        return manager.pinCode(with: SDSDB.shimOnlyBridge(transaction))
    }

    public func markDisabled(transaction: DBWriteTransaction) {
        manager.markDisabled(transaction: SDSDB.shimOnlyBridge(transaction))
    }
}

// NOTE: The below aren't shims/wrappers in the normal sense; they
// wrap libsignal stuff that we will _always_ need to wrap.

protocol SVR2PinHash {
    // The thing we use as the "pin" in SVR2 backup/restore requests.
    var accessKey: Data { get }

    // The data we put into SVR2 backups, encrypted with the PIN.
    func encryptMasterKey(_ masterKey: Data) throws -> Data

    func decryptMasterKey(_ encryptedMasterKey: Data) throws -> Data
}

internal protocol SVR2ClientWrapper {

    func hashPin(
        connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>,
        utf8NormalizedPin: Data,
        username: String
    ) throws -> SVR2PinHash
}

internal class SVR2ClientWrapperImpl: SVR2ClientWrapper {

    init() {}

    private class SVR2PinHashImpl: SVR2PinHash {

        private let pinHash: PinHash

        init(_ pinHash: PinHash) {
            self.pinHash = pinHash
        }

        var accessKey: Data { Data(pinHash.accessKey) }
        private var encryptionKey: Data { Data(pinHash.encryptionKey) }

        func encryptMasterKey(_ masterKey: Data) throws -> Data {
            let (iv, cipherText) = try Cryptography.encryptSHA256HMACSIV(data: masterKey, key: encryptionKey)
            if iv.count != 16 || cipherText.count != 32 {
                throw SVR.SVRError.assertion
            }
            let encryptedMasterKey = iv + cipherText
            return encryptedMasterKey
        }

        func decryptMasterKey(_ encryptedMasterKey: Data) throws -> Data {
            guard encryptedMasterKey.count == 48 else { throw SVR.SVRError.assertion }

            let startIndex: Int = encryptedMasterKey.startIndex
            let ivRange = startIndex...(startIndex + 15)
            let cipherRange = (startIndex + 16)...(startIndex + 47)
            let masterKey = try Cryptography.decryptSHA256HMACSIV(
                iv: encryptedMasterKey[ivRange],
                cipherText: encryptedMasterKey[cipherRange],
                key: encryptionKey
            )

            guard masterKey.count == SVR.masterKeyLengthBytes else { throw SVR.SVRError.assertion }

            return masterKey
        }
    }

    func hashPin(
        connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>,
        utf8NormalizedPin: Data,
        username: String
    ) throws -> SVR2PinHash {
        let pinHash = try LibSignalClient.PinHash.init(normalizedPin: utf8NormalizedPin, username: username, mrenclave: connection.mrEnclave.dataValue)
        return SVR2PinHashImpl(pinHash)
    }

}

#if TESTABLE_BUILD

extension SVR2 {
    enum Mocks {
        typealias AppReadiness = _SVR2_AppReadinessMock
    }
}

internal class _SVR2_AppReadinessMock: _SVR2_AppReadinessShim {

    init() {}

    var isMainApp: Bool { true }

    func runNowOrWhenMainAppDidBecomeReadyAsync(_ block: @escaping () -> Void) {}
}

internal class MockSVR2ClientWrapper: SVR2ClientWrapper {

    init() {}

    class MockSVR2PinHash: SVR2PinHash {

        init(utf8NormalizedPin: Data) {
            self.accessKey = utf8NormalizedPin
        }

        var accessKey: Data

        var didEncryptMasterKey: (_ masterKey: Data) throws -> Data = { return $0 }

        func encryptMasterKey(_ masterKey: Data) throws -> Data {
            return try didEncryptMasterKey(masterKey)
        }

        var didDecryptMasterKey: (_ encryptedMasterKey: Data) throws -> Data = { return $0 }

        func decryptMasterKey(_ encryptedMasterKey: Data) throws -> Data {
            return try didDecryptMasterKey(encryptedMasterKey)
        }
    }

    public var didHashPin: ((_ utf8NormalizedPin: Data, _ username: String) throws -> MockSVR2PinHash) = { utf8NormalizedPin, _ in
        return MockSVR2PinHash(utf8NormalizedPin: utf8NormalizedPin)
    }

    func hashPin(
        connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>,
        utf8NormalizedPin: Data,
        username: String
    ) throws -> SVR2PinHash {
        return try didHashPin(utf8NormalizedPin, username)
    }

}

#endif
