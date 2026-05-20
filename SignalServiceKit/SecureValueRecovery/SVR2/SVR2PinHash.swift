//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
import LibSignalClient

protocol SVR2PinHasher {
    func hashPin(
        normalizedPin: String,
        username: String,
        mrEnclave: MrEnclave,
    ) throws -> SVR2PinHash
}

struct LibSignalPinHasher: SVR2PinHasher {
    func hashPin(normalizedPin: String, username: String, mrEnclave: MrEnclave) throws -> SVR2PinHash {
        return try SVR2PinHash.derive(normalizedPin: normalizedPin, username: username, mrEnclave: mrEnclave)
    }
}

#if TESTABLE_BUILD

/// A "mock" PIN hasher that works even for invalid MrEnclave values.
struct MockPinHasher: SVR2PinHasher {
    func hashPin(normalizedPin: String, username: String, mrEnclave: MrEnclave) throws -> SVR2PinHash {
        // A fake hashing function that considers the same inputs as the real one.
        let result = try hkdf(outputLength: 64, inputKeyMaterial: Data(normalizedPin.utf8), salt: Data(username.utf8), info: mrEnclave.dataValue)
        return SVR2PinHash(accessKey: result.prefix(32), encryptionKey: result.suffix(32))
    }
}

#endif

struct SVR2PinHash {
    // The thing we use as the "pin" in SVR2 backup/restore requests.
    var accessKey: Data

    var encryptionKey: Data

    // The data we put into SVR2 backups, encrypted with the PIN.
    func encryptMasterKey(_ masterKey: Data) throws -> Data {
        let (iv, cipherText) = try Sha256HmacSiv.encrypt(data: masterKey, key: encryptionKey)
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
        let masterKey = try Sha256HmacSiv.decrypt(
            iv: encryptedMasterKey[ivRange],
            cipherText: encryptedMasterKey[cipherRange],
            key: encryptionKey,
        )

        guard masterKey.count == MasterKey.Constants.byteLength else { throw SVR.SVRError.assertion }

        return masterKey
    }

    static func derive(
        normalizedPin: String,
        username: String,
        mrEnclave: MrEnclave,
    ) throws -> Self {
        let pinHash = try LibSignalClient.PinHash(normalizedPin: Data(normalizedPin.utf8), username: username, mrenclave: mrEnclave.dataValue)
        return Self(accessKey: pinHash.accessKey, encryptionKey: pinHash.encryptionKey)
    }
}
