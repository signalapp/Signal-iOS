//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit // To access ExtraLockKeyManager and its error types
import libsodium // For libsodium constants if needed directly, though usually accessed via framework

class ExtraLockKeyManagerTests: XCTestCase {

    // MARK: - Key Pair Generation Tests

    func testGenerateKeyPair_Success() throws {
        let keyPair = try ExtraLockKeyManager.generateKeyPair()

        XCTAssertEqual(keyPair.publicKey.count, ExtraLockKeyManager.publicKeyLength, "Generated public key has incorrect length.")
        XCTAssertEqual(keyPair.privateKey.count, ExtraLockKeyManager.privateKeyLength, "Generated private key has incorrect length.")

        // Ensure keys are not all zeros (basic sanity check)
        XCTAssertTrue(keyPair.publicKey.contains(where: { $0 != 0 }), "Public key should not be all zeros.")
        XCTAssertTrue(keyPair.privateKey.contains(where: { $0 != 0 }), "Private key should not be all zeros.")
    }

    func testGenerateKeyPair_MultipleCalls_ProduceDifferentKeys() throws {
        let keyPair1 = try ExtraLockKeyManager.generateKeyPair()
        let keyPair2 = try ExtraLockKeyManager.generateKeyPair()

        XCTAssertNotEqual(keyPair1.publicKey, keyPair2.publicKey, "Multiple calls to generateKeyPair should produce different public keys.")
        XCTAssertNotEqual(keyPair1.privateKey, keyPair2.privateKey, "Multiple calls to generateKeyPair should produce different private keys.")
    }

    // MARK: - Shared Secret Calculation Tests

    func testCalculateSharedSecret_Success() throws {
        let localKeyPair = try ExtraLockKeyManager.generateKeyPair()
        let remoteKeyPair = try ExtraLockKeyManager.generateKeyPair()

        let sharedSecret1 = try ExtraLockKeyManager.calculateSharedSecret(
            localPrivateKey: localKeyPair.privateKey,
            remotePublicKey: remoteKeyPair.publicKey
        )
        XCTAssertEqual(sharedSecret1.count, ExtraLockKeyManager.sharedSecretLength, "Shared secret 1 has incorrect length.")
        XCTAssertTrue(sharedSecret1.contains(where: { $0 != 0 }), "Shared secret 1 should not be all zeros for valid random keys.")

        // ECDH property: secret(privA, pubB) == secret(privB, pubA)
        let sharedSecret2 = try ExtraLockKeyManager.calculateSharedSecret(
            localPrivateKey: remoteKeyPair.privateKey,
            remotePublicKey: localKeyPair.publicKey
        )
        XCTAssertEqual(sharedSecret2.count, ExtraLockKeyManager.sharedSecretLength, "Shared secret 2 has incorrect length.")
        XCTAssertEqual(sharedSecret1, sharedSecret2, "Shared secrets derived from swapped key pairs should be identical.")
    }

    func testCalculateSharedSecret_InvalidLocalPrivateKeyLength() throws {
        let localPrivateKeyInvalid = Data(repeating: 0xAA, count: ExtraLockKeyManager.privateKeyLength - 1)
        let remoteKeyPair = try ExtraLockKeyManager.generateKeyPair()

        XCTAssertThrowsError(try ExtraLockKeyManager.calculateSharedSecret(
            localPrivateKey: localPrivateKeyInvalid,
            remotePublicKey: remoteKeyPair.publicKey
        )) { error in
            guard let keyManagerError = error as? ExtraLockKeyManagerError else {
                XCTFail("Unexpected error type: \(error)")
                return
            }
            // Check for the specific error case. Based on implementation, this should be .invalidKeyLength
            // For example: XCTAssertEqual(keyManagerError, ExtraLockKeyManagerError.invalidKeyLength)
            // Or, if the error has associated values or is more generic:
            if case .invalidKeyLength = keyManagerError {
                // This is the expected error
            } else {
                XCTFail("Expected .invalidKeyLength, got \(keyManagerError)")
            }
        }
    }

    func testCalculateSharedSecret_InvalidRemotePublicKeyLength() throws {
        let localKeyPair = try ExtraLockKeyManager.generateKeyPair()
        let remotePublicKeyInvalid = Data(repeating: 0xBB, count: ExtraLockKeyManager.publicKeyLength + 1)

        XCTAssertThrowsError(try ExtraLockKeyManager.calculateSharedSecret(
            localPrivateKey: localKeyPair.privateKey,
            remotePublicKey: remotePublicKeyInvalid
        )) { error in
            guard let keyManagerError = error as? ExtraLockKeyManagerError else {
                XCTFail("Unexpected error type: \(error)")
                return
            }
            if case .invalidKeyLength = keyManagerError {
                // Expected
            } else {
                XCTFail("Expected .invalidKeyLength, got \(keyManagerError)")
            }
        }
    }

    func testCalculateSharedSecret_AllZeroRemotePublicKey_ThrowsError() throws {
        // crypto_scalarmult with a zero public key (identity element for some curves, or an invalid point)
        // should result in an all-zero shared secret, which our code explicitly checks against.
        // For Curve25519, the all-zero public key is an invalid point.
        // Libsodium's crypto_scalarmult is designed to return 0 (success) but output an all-zero buffer
        // if the input point is of small order (like the point at infinity, often represented by all zeros).
        let localKeyPair = try ExtraLockKeyManager.generateKeyPair()
        let allZeroPublicKey = Data(count: ExtraLockKeyManager.publicKeyLength) // All zeros

        XCTAssertThrowsError(try ExtraLockKeyManager.calculateSharedSecret(
            localPrivateKey: localKeyPair.privateKey,
            remotePublicKey: allZeroPublicKey
        )) { error in
            guard let keyManagerError = error as? ExtraLockKeyManagerError else {
                XCTFail("Unexpected error type: \(error)")
                return
            }
            // This should throw ecdhSharedSecretCalculationFailed due to the all-zero shared secret check.
            if case .ecdhSharedSecretCalculationFailed = keyManagerError {
                // This is the expected error
            } else {
                XCTFail("Expected .ecdhSharedSecretCalculationFailed for all-zero shared secret, got \(keyManagerError)")
            }
        }
    }

    func testCalculateSharedSecret_AllZeroLocalPrivateKey() throws {
        // While not typically done, if the local private key is all zeros,
        // crypto_scalarmult will produce an all-zero output.
        let allZeroPrivateKey = Data(count: ExtraLockKeyManager.privateKeyLength)
        let remoteKeyPair = try ExtraLockKeyManager.generateKeyPair()

        XCTAssertThrowsError(try ExtraLockKeyManager.calculateSharedSecret(
            localPrivateKey: allZeroPrivateKey,
            remotePublicKey: remoteKeyPair.publicKey
        )) { error in
            guard let keyManagerError = error as? ExtraLockKeyManagerError else {
                XCTFail("Unexpected error type: \(error)")
                return
            }
            if case .ecdhSharedSecretCalculationFailed = keyManagerError {
                // Expected due to all-zero shared secret
            } else {
                XCTFail("Expected .ecdhSharedSecretCalculationFailed for all-zero private key, got \(keyManagerError)")
            }
        }
    }
}
