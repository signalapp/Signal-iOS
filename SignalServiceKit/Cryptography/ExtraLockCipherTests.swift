//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit // Grants access to internal types if ExtraLockCipher or its components are internal

// If libsodium functions are not automatically available through a bridging header
// included by SignalServiceKit, we might need to import a specific module or
// declare them. For now, assuming they are available as global functions.

class ExtraLockCipherTests: XCTestCase {

    // MARK: - Test Data Helper

    // Use constant values for reproducible tests
    let testRootKey = Data(repeating: 0xAA, count: 32)
    let testPeerExtraECDHSecret = Data(repeating: 0xBB, count: 32)
    let testUserPassphrase = "supersecurepassphrase"
    let testPlaintext = "This is some secret data for ExtraLock.".data(using: .utf8)!

    // Expected lengths (from ExtraLockCipher.swift, assuming they remain private)
    let expectedKeyOutputLength = 32
    let expectedNonceLength = 12
    let expectedTagLength = 16

    // MARK: - Key Derivation Tests

    func testDeriveExtraKey_ValidInputs_DeterministicOutput() throws {
        let key1 = try ExtraLockCipher.deriveExtraKey(
            rootKey: testRootKey,
            peerExtraECDHSecret: testPeerExtraECDHSecret,
            userPassphraseString: testUserPassphrase
        )
        XCTAssertEqual(key1.count, expectedKeyOutputLength, "Derived key 1 has incorrect length.")

        let key2 = try ExtraLockCipher.deriveExtraKey(
            rootKey: testRootKey,
            peerExtraECDHSecret: testPeerExtraECDHSecret,
            userPassphraseString: testUserPassphrase
        )
        XCTAssertEqual(key2.count, expectedKeyOutputLength, "Derived key 2 has incorrect length.")
        XCTAssertEqual(key1, key2, "Derived keys with identical inputs should be identical.")
    }

    func testDeriveExtraKey_DifferentRootKey_DifferentOutput() throws {
        let key1 = try ExtraLockCipher.deriveExtraKey(
            rootKey: testRootKey,
            peerExtraECDHSecret: testPeerExtraECDHSecret,
            userPassphraseString: testUserPassphrase
        )

        let differentRootKey = Data(repeating: 0xCC, count: 32)
        let key2 = try ExtraLockCipher.deriveExtraKey(
            rootKey: differentRootKey,
            peerExtraECDHSecret: testPeerExtraECDHSecret,
            userPassphraseString: testUserPassphrase
        )
        XCTAssertNotEqual(key1, key2, "Derived keys with different rootKey should be different.")
    }

    func testDeriveExtraKey_DifferentPeerSecret_DifferentOutput() throws {
        let key1 = try ExtraLockCipher.deriveExtraKey(
            rootKey: testRootKey,
            peerExtraECDHSecret: testPeerExtraECDHSecret,
            userPassphraseString: testUserPassphrase
        )

        let differentPeerSecret = Data(repeating: 0xDD, count: 32)
        let key2 = try ExtraLockCipher.deriveExtraKey(
            rootKey: testRootKey,
            peerExtraECDHSecret: differentPeerSecret,
            userPassphraseString: testUserPassphrase
        )
        XCTAssertNotEqual(key1, key2, "Derived keys with different peerExtraECDHSecret should be different.")
    }

    func testDeriveExtraKey_DifferentPassphrase_DifferentOutput() throws {
        let key1 = try ExtraLockCipher.deriveExtraKey(
            rootKey: testRootKey,
            peerExtraECDHSecret: testPeerExtraECDHSecret,
            userPassphraseString: testUserPassphrase
        )

        let key2 = try ExtraLockCipher.deriveExtraKey(
            rootKey: testRootKey,
            peerExtraECDHSecret: testPeerExtraECDHSecret,
            userPassphraseString: "anotherPassphrase"
        )
        XCTAssertNotEqual(key1, key2, "Derived keys with different passphrase should be different.")
    }

    func testDeriveExtraKey_EmptyPassphrase_ThrowsInvalidInput() {
        XCTAssertThrowsError(try ExtraLockCipher.deriveExtraKey(
            rootKey: testRootKey,
            peerExtraECDHSecret: testPeerExtraECDHSecret,
            userPassphraseString: ""
        )) { error in
            XCTAssertEqual(error as? ExtraLockCipherError, .invalidInput, "Expected .invalidInput error for empty passphrase.")
        }
    }

    // MARK: - Seal & Open (Encryption/Decryption) Tests

    func testSealOpen_RoundTrip_ValidKey() throws {
        let extraKey = try ExtraLockCipher.deriveExtraKey(
            rootKey: testRootKey,
            peerExtraECDHSecret: testPeerExtraECDHSecret,
            userPassphraseString: testUserPassphrase
        )
        XCTAssertEqual(extraKey.count, expectedKeyOutputLength)

        let sealedData = try ExtraLockCipher.seal(plaintext: testPlaintext, extraKey: extraKey)
        // Check format: nonce + ciphertext + tag
        XCTAssertEqual(sealedData.count, expectedNonceLength + testPlaintext.count + expectedTagLength, "Sealed data length is incorrect.")

        let decryptedPlaintext = try ExtraLockCipher.open(sealedData: sealedData, extraKey: extraKey)
        XCTAssertEqual(decryptedPlaintext, testPlaintext, "Decrypted plaintext does not match original.")
    }

    func testSealOpen_RoundTrip_EmptyPlaintext() throws {
        let extraKey = try ExtraLockCipher.deriveExtraKey(
            rootKey: testRootKey,
            peerExtraECDHSecret: testPeerExtraECDHSecret,
            userPassphraseString: testUserPassphrase
        )
        let emptyPlaintext = Data()

        let sealedData = try ExtraLockCipher.seal(plaintext: emptyPlaintext, extraKey: extraKey)
        XCTAssertEqual(sealedData.count, expectedNonceLength + emptyPlaintext.count + expectedTagLength, "Sealed data length for empty plaintext is incorrect.")

        let decryptedPlaintext = try ExtraLockCipher.open(sealedData: sealedData, extraKey: extraKey)
        XCTAssertEqual(decryptedPlaintext, emptyPlaintext, "Decrypted empty plaintext does not match original.")
    }


    func testSeal_InvalidKeyLength_ThrowsInvalidInput() {
        let invalidKey = Data(repeating: 0xAB, count: 16) // Incorrect length
        XCTAssertThrowsError(try ExtraLockCipher.seal(plaintext: testPlaintext, extraKey: invalidKey)) { error in
            XCTAssertEqual(error as? ExtraLockCipherError, .invalidInput, "Expected .invalidInput error for incorrect key length during seal.")
        }
    }

    func testOpen_InvalidKeyLength_ThrowsInvalidInput() throws {
        let validKey = Data(repeating: 0xCD, count: expectedKeyOutputLength)
        // Create some dummy sealed data (actual content doesn't matter as key check is first)
        let dummySealedData = Data(repeating: 0, count: expectedNonceLength + 5 + expectedTagLength)

        let invalidKey = Data(repeating: 0xEF, count: 16) // Incorrect length
        XCTAssertThrowsError(try ExtraLockCipher.open(sealedData: dummySealedData, extraKey: invalidKey)) { error in
            XCTAssertEqual(error as? ExtraLockCipherError, .invalidInput, "Expected .invalidInput error for incorrect key length during open.")
        }
    }

    func testOpen_SealedDataTooShort_NonceMissing_ThrowsInvalidInput() {
        let extraKey = Data(repeating: 0xCD, count: expectedKeyOutputLength)
        // Data shorter than a nonce
        let shortData = Data(repeating: 0, count: expectedNonceLength - 1)
        XCTAssertThrowsError(try ExtraLockCipher.open(sealedData: shortData, extraKey: extraKey)) { error in
            XCTAssertEqual(error as? ExtraLockCipherError, .invalidInput, "Expected .invalidInput for data shorter than nonce.")
        }
    }

    func testOpen_SealedDataTooShort_TagMissing_ThrowsInvalidInput() {
        let extraKey = Data(repeating: 0xCD, count: expectedKeyOutputLength)
        // Data shorter than nonce + tag
        let shortData = Data(repeating: 0, count: expectedNonceLength + expectedTagLength - 1)
        XCTAssertThrowsError(try ExtraLockCipher.open(sealedData: shortData, extraKey: extraKey)) { error in
            XCTAssertEqual(error as? ExtraLockCipherError, .invalidInput, "Expected .invalidInput for data shorter than nonce + tag.")
        }
    }

    func testOpen_TamperedCiphertext_ThrowsDecryptionFailed() throws {
        let extraKey = try ExtraLockCipher.deriveExtraKey(
            rootKey: testRootKey,
            peerExtraECDHSecret: testPeerExtraECDHSecret,
            userPassphraseString: testUserPassphrase
        )
        var sealedData = try ExtraLockCipher.seal(plaintext: testPlaintext, extraKey: extraKey)

        // Tamper with a byte in the ciphertext part
        // Ciphertext is after nonce (12 bytes) and before tag (16 bytes)
        if sealedData.count > expectedNonceLength + expectedTagLength { // Ensure there is ciphertext to tamper
            let tamperIndex = expectedNonceLength // Tamper the first byte of actual ciphertext
            sealedData[tamperIndex] = sealedData[tamperIndex] ^ 0xFF // Flip bits
        } else {
            // This case should not happen with non-empty plaintext
            XCTFail("Sealed data is too short to contain ciphertext for tampering test.")
            return
        }

        XCTAssertThrowsError(try ExtraLockCipher.open(sealedData: sealedData, extraKey: extraKey)) { error in
            XCTAssertEqual(error as? ExtraLockCipherError, .decryptionFailed, "Expected .decryptionFailed for tampered ciphertext.")
        }
    }

    func testOpen_TamperedNonce_ThrowsDecryptionFailed() throws {
        let extraKey = try ExtraLockCipher.deriveExtraKey(
            rootKey: testRootKey,
            peerExtraECDHSecret: testPeerExtraECDHSecret,
            userPassphraseString: testUserPassphrase
        )
        var sealedData = try ExtraLockCipher.seal(plaintext: testPlaintext, extraKey: extraKey)

        // Tamper with a byte in the nonce part
        if sealedData.count >= expectedNonceLength {
            let tamperIndex = 0 // Tamper the first byte of nonce
            sealedData[tamperIndex] = sealedData[tamperIndex] ^ 0xFF // Flip bits
        } else {
             XCTFail("Sealed data is too short to contain nonce for tampering test.")
            return
        }

        XCTAssertThrowsError(try ExtraLockCipher.open(sealedData: sealedData, extraKey: extraKey)) { error in
            XCTAssertEqual(error as? ExtraLockCipherError, .decryptionFailed, "Expected .decryptionFailed for tampered nonce.")
        }
    }

    func testOpen_TamperedTag_ThrowsDecryptionFailed() throws {
        let extraKey = try ExtraLockCipher.deriveExtraKey(
            rootKey: testRootKey,
            peerExtraECDHSecret: testPeerExtraECDHSecret,
            userPassphraseString: testUserPassphrase
        )
        var sealedData = try ExtraLockCipher.seal(plaintext: testPlaintext, extraKey: extraKey)

        // Tamper with a byte in the tag part
        if sealedData.count >= expectedTagLength {
            let tamperIndex = sealedData.count - 1 // Tamper the last byte of the tag
            sealedData[tamperIndex] = sealedData[tamperIndex] ^ 0xFF // Flip bits
        } else {
             XCTFail("Sealed data is too short to contain tag for tampering test.")
            return
        }

        XCTAssertThrowsError(try ExtraLockCipher.open(sealedData: sealedData, extraKey: extraKey)) { error in
            XCTAssertEqual(error as? ExtraLockCipherError, .decryptionFailed, "Expected .decryptionFailed for tampered tag.")
        }
    }

    func testOpen_DifferentKey_ThrowsDecryptionFailed() throws {
        let key1 = try ExtraLockCipher.deriveExtraKey(
            rootKey: testRootKey,
            peerExtraECDHSecret: testPeerExtraECDHSecret,
            userPassphraseString: testUserPassphrase
        )
        let sealedData = try ExtraLockCipher.seal(plaintext: testPlaintext, extraKey: key1)

        let key2 = try ExtraLockCipher.deriveExtraKey(
            rootKey: testRootKey,
            peerExtraECDHSecret: testPeerExtraECDHSecret,
            userPassphraseString: "a different passphrase" // Ensures a different key
        )
        XCTAssertNotEqual(key1, key2)

        XCTAssertThrowsError(try ExtraLockCipher.open(sealedData: sealedData, extraKey: key2)) { error in
            XCTAssertEqual(error as? ExtraLockCipherError, .decryptionFailed, "Expected .decryptionFailed when using a different decryption key.")
        }
    }

    // MARK: - Data.resetBytes Tests

    func testResetBytes_FullRange() {
        var data = Data([1, 2, 3, 4, 5])
        let fullRange = 0..<data.count
        data.resetBytes(in: fullRange)
        XCTAssertEqual(data, Data([0, 0, 0, 0, 0]), "Full range reset failed.")
    }

    func testResetBytes_PartialRange_Middle() {
        var data = Data([1, 2, 3, 4, 5])
        data.resetBytes(in: 1..<4) // Zero out 2, 3, 4
        XCTAssertEqual(data, Data([1, 0, 0, 0, 5]), "Partial middle range reset failed.")
    }

    func testResetBytes_PartialRange_Start() {
        var data = Data([1, 2, 3, 4, 5])
        data.resetBytes(in: 0..<2) // Zero out 1, 2
        XCTAssertEqual(data, Data([0, 0, 3, 4, 5]), "Partial start range reset failed.")
    }

    func testResetBytes_PartialRange_End() {
        var data = Data([1, 2, 3, 4, 5])
        data.resetBytes(in: 3..<data.count) // Zero out 4, 5
        XCTAssertEqual(data, Data([1, 2, 3, 0, 0]), "Partial end range reset failed.")
    }

    func testResetBytes_RangeEqualsData() {
        var data = Data([1, 2, 3, 4, 5])
        data.resetBytes(in: data.startIndex..<data.endIndex)
        XCTAssertEqual(data, Data([0, 0, 0, 0, 0]), "Range equal to data bounds reset failed.")
    }

    func testResetBytes_EmptyData() {
        var data = Data()
        data.resetBytes(in: 0..<0)
        XCTAssertEqual(data, Data(), "ResetBytes on empty data should do nothing and not crash.")

        // Also test with a non-empty range on empty data
        data.resetBytes(in: 0..<5)
        XCTAssertEqual(data, Data(), "ResetBytes with non-empty range on empty data should do nothing.")
    }

    func testResetBytes_EmptyRange() {
        var data = Data([1, 2, 3])
        let originalData = data
        data.resetBytes(in: 1..<1) // Empty range
        XCTAssertEqual(data, originalData, "ResetBytes with empty range should not modify data.")
    }

    func testResetBytes_RangeCompletelyBeforeStart() {
        var data = Data([1, 2, 3, 4, 5])
        let originalData = data
        // Assuming Data.Index is Int, this range is valid but outside positive indices.
        // The clamping logic should result in an empty effective range.
        data.resetBytes(in: -5 ..< -1)
        XCTAssertEqual(data, originalData, "Range completely before start should not modify data.")
    }

    func testResetBytes_RangeCompletelyAfterEnd() {
        var data = Data([1, 2, 3, 4, 5])
        let originalData = data
        data.resetBytes(in: 5..<10) // data.count is 5, so indices are 0..4
        XCTAssertEqual(data, originalData, "Range completely after end should not modify data.")
    }

    func testResetBytes_RangePartiallyBeforeStart() {
        var data = Data([1, 2, 3, 4, 5]) // count = 5, indices 0..4
        // Range is -2..<3. Clamped should be 0..<3.
        data.resetBytes(in: -2..<3)
        XCTAssertEqual(data, Data([0, 0, 0, 4, 5]), "Range partially before start, clamped reset failed.")
    }

    func testResetBytes_RangePartiallyAfterEnd() {
        var data = Data([1, 2, 3, 4, 5]) // count = 5, indices 0..4
        // Range is 3..<8. Clamped should be 3..<5.
        data.resetBytes(in: 3..<8)
        XCTAssertEqual(data, Data([1, 2, 3, 0, 0]), "Range partially after end, clamped reset failed.")
    }

    func testResetBytes_RangeIncludesAllAndMore() {
        var data = Data([1, 2, 3, 4, 5]) // count = 5, indices 0..4
        // Range is -2..<7. Clamped should be 0..<5.
        data.resetBytes(in: -2..<7)
        XCTAssertEqual(data, Data([0, 0, 0, 0, 0]), "Range including all and more, clamped reset failed.")
    }

    func testResetBytes_InvalidRange_LowerBoundGreaterThanUpperBound() {
        var data = Data([1, 2, 3, 4, 5])
        let originalData = data
        data.resetBytes(in: 3..<1) // Invalid range
        XCTAssertEqual(data, originalData, "Invalid range (lower > upper) should not modify data.")
    }

    func testResetBytes_SingleElementRange() {
        var data = Data([1, 2, 3, 4, 5])
        data.resetBytes(in: 2..<3) // Zero out element at index 2 (value 3)
        XCTAssertEqual(data, Data([1, 2, 0, 4, 5]), "Single element range reset failed.")
    }

    func testResetBytes_OnLargeData() {
        // Test with a larger data set to ensure performance is acceptable (though this isn't a perf test)
        // and that clamping works correctly with larger indices.
        let size = 1024
        var data = Data(repeating: 0xFF, count: size)
        let rangeToZero = 100..<200
        data.resetBytes(in: rangeToZero)

        var expectedData = Data(repeating: 0xFF, count: size)
        for i in rangeToZero {
            expectedData[i] = 0x00
        }
        XCTAssertEqual(data, expectedData, "Reset on larger data segment failed.")
    }
}
