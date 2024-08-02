//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

enum Sha256HmacSiv {
    private static let hmacsivIVLength = 16
    private static let hmacsivDataLength = 32

    private static func invalidLengthError(_ parameter: String) -> Error {
        return OWSAssertionError("\(parameter) length is invalid")
    }

    /// Encrypts a 32-byte `data` with the provided 32-byte `key` using SHA-256 HMAC-SIV.
    /// Returns a tuple of (16-byte IV, 32-byte Ciphertext) or `nil` if an error occurs.
    static func encrypt(data: Data, key: Data) throws -> (iv: Data, ciphertext: Data) {
        guard data.count == hmacsivDataLength else { throw invalidLengthError("data") }
        guard key.count == hmacsivDataLength else { throw invalidLengthError("key") }

        guard let authData = "auth".data(using: .utf8),
              let Ka = Cryptography.computeSHA256HMAC(authData, key: key) else {
            throw OWSAssertionError("failed to compute Ka")
        }
        guard let encData = "enc".data(using: .utf8),
              let Ke = Cryptography.computeSHA256HMAC(encData, key: key) else {
            throw OWSAssertionError("failed to compute Ke")
        }

        guard let iv = Cryptography.computeSHA256HMAC(data, key: Ka, truncatedToBytes: UInt(hmacsivIVLength)) else {
            throw OWSAssertionError("failed to compute IV")
        }

        guard let Kx = Cryptography.computeSHA256HMAC(iv, key: Ke) else {
            throw OWSAssertionError("failed to compute Kx")
        }

        let ciphertext = try Kx ^ data

        return (iv, ciphertext)
    }

    /// Decrypts a 32-byte `cipherText` with the provided 32-byte `key` and 16-byte `iv` using SHA-256 HMAC-SIV.
    /// Returns the decrypted 32-bytes of data or `nil` if an error occurs.
    static func decrypt(iv: Data, cipherText: Data, key: Data) throws -> Data {
        guard iv.count == hmacsivIVLength else { throw invalidLengthError("iv") }
        guard cipherText.count == hmacsivDataLength else { throw invalidLengthError("cipherText") }
        guard key.count == hmacsivDataLength else { throw invalidLengthError("key") }

        guard let authData = "auth".data(using: .utf8),
              let Ka = Cryptography.computeSHA256HMAC(authData, key: key) else {
            throw OWSAssertionError("failed to compute Ka")
        }
        guard let encData = "enc".data(using: .utf8),
              let Ke = Cryptography.computeSHA256HMAC(encData, key: key) else {
            throw OWSAssertionError("failed to compute Ke")
        }

        guard let Kx = Cryptography.computeSHA256HMAC(iv, key: Ke) else {
            throw OWSAssertionError("failed to compute Kx")
        }

        let decryptedData = try Kx ^ cipherText

        guard let ourIV = Cryptography.computeSHA256HMAC(decryptedData, key: Ka, truncatedToBytes: UInt(hmacsivIVLength)) else {
            throw OWSAssertionError("failed to compute IV")
        }

        guard ourIV.ows_constantTimeIsEqual(to: iv) else {
            throw OWSAssertionError("failed to validate IV")
        }

        return decryptedData
    }
}

extension Data {
    fileprivate static func ^ (lhs: Data, rhs: Data) throws -> Data {
        guard lhs.count == rhs.count else { throw OWSAssertionError("lhs length must equal rhs length") }
        return Data(zip(lhs, rhs).map { $0 ^ $1 })
    }
}
