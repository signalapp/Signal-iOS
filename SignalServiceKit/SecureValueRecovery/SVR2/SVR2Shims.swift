//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

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
        utf8Pin: Data,
        utf8Username: Data
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
        utf8Pin: Data,
        utf8Username: Data
    ) throws -> SVR2PinHash {
        let pinHash = try connection.client.hashPin(utf8Pin, forUser: utf8Username)
        return SVR2PinHashImpl(pinHash)
    }

}

#if TESTABLE_BUILD

internal class MockSVR2ClientWrapper: SVR2ClientWrapper {

    init() {}

    class MockSVR2PinHash: SVR2PinHash {

        init() {}

        var accessKey: Data = Data()

        var didEncryptMasterKey: (_ masterKey: Data) throws -> Data = { return $0 }

        func encryptMasterKey(_ masterKey: Data) throws -> Data {
            return try didEncryptMasterKey(masterKey)
        }

        var didDecryptMasterKey: (_ encryptedMasterKey: Data) throws -> Data = { return $0 }

        func decryptMasterKey(_ encryptedMasterKey: Data) throws -> Data {
            return try didDecryptMasterKey(encryptedMasterKey)
        }
    }

    public var didHashPin: ((_ utf8Pin: Data, _ utf8Username: Data) throws -> MockSVR2PinHash) = { _, _ in
        return MockSVR2PinHash()
    }

    func hashPin(
        connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>,
        utf8Pin: Data,
        utf8Username: Data
    ) throws -> SVR2PinHash {
        return try didHashPin(utf8Pin, utf8Username)
    }

}

#endif
