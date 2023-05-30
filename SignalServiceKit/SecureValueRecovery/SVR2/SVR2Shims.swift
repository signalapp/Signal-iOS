//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal enum SVR2 {
    struct PinHashResult {
        // The data we put into SVR2 backups, encrypted with the PIN.
        let encryptedMasterKey: Data
        // The thing we use as the "pin" in SVR2 backup requests.
        let accessKey: Data
    }
}

internal protocol SVR2ClientWrapper {

    func hashPinAndEncryptMasterKey(
        connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>,
        utf8Pin: Data,
        utf8Username: Data,
        masterKey: Data
    ) throws -> SVR2.PinHashResult
}

internal class SVR2ClientWrapperImpl: SVR2ClientWrapper {

    init() {}

    func hashPinAndEncryptMasterKey(
        connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>,
        utf8Pin: Data,
        utf8Username: Data,
        masterKey: Data
    ) throws -> SVR2.PinHashResult {
        let pinHash = try connection.client.hashPin(utf8Pin, forUser: utf8Username)
        let (iv, cipherText) = try Cryptography.encryptSHA256HMACSIV(data: masterKey, key: Data(pinHash.encryptionKey))
        if iv.count != 16 || cipherText.count != 32 {
            throw SVR.SVRError.assertion
        }
        let encryptedMasterKey = iv + cipherText
        let accessKey = Data(pinHash.accessKey)
        return SVR2.PinHashResult(encryptedMasterKey: encryptedMasterKey, accessKey: accessKey)
    }

}

#if TESTABLE_BUILD

internal class MockSVR2ClientWrapper: SVR2ClientWrapper {

    init() {}

    public var didHashPinAndEncryptMasterKey: ((_ utf8Pin: Data, _ utf8Username: Data, _ masterKey: Data) throws -> SVR2.PinHashResult)!

    func hashPinAndEncryptMasterKey(
        connection: SgxWebsocketConnection<SVR2WebsocketConfigurator>,
        utf8Pin: Data,
        utf8Username: Data,
        masterKey: Data
    ) throws -> SVR2.PinHashResult {
        return try didHashPinAndEncryptMasterKey(utf8Pin, utf8Username, masterKey)
    }

}

#endif
