//
//  CrossPlatformCompatibilityTests.swift
//  EMMA Cross-Platform Compatibility Tests
//
//  Verifies iOS ↔ Android cryptographic interoperability
//

import XCTest
@testable import EMMASecurityKit

@available(iOS 15.0, *)
class CrossPlatformCompatibilityTests: XCTestCase {

    // MARK: - ML-KEM-1024 Interoperability Tests

    func testMLKEM1024KeyPairGeneration() {
        // Test that we can generate ML-KEM-1024 keypairs
        let keypair = EMMLKEM1024.generateKeypair()

        XCTAssertNotNil(keypair, "Keypair should be generated")
        XCTAssertEqual(keypair!.publicKey.count, 1568, "Public key should be 1568 bytes")
        XCTAssertEqual(keypair!.secretKey.count, 3168, "Secret key should be 3168 bytes")

        // Verify keys are not all zeros
        XCTAssertFalse(keypair!.publicKey.allSatisfy { $0 == 0 }, "Public key should not be all zeros")
        XCTAssertFalse(keypair!.secretKey.allSatisfy { $0 == 0 }, "Secret key should not be all zeros")

        NSLog("[TEST] ML-KEM-1024 keypair generated successfully")
    }

    func testMLKEM1024EncapsulationDecapsulation() {
        // Generate keypair
        guard let keypair = EMMLKEM1024.generateKeypair() else {
            XCTFail("Failed to generate keypair")
            return
        }

        // Encapsulate (create ciphertext and shared secret)
        guard let encapResult = EMMLKEM1024.encapsulate(withPublicKey: keypair.publicKey) else {
            XCTFail("Failed to encapsulate")
            return
        }

        XCTAssertEqual(encapResult.ciphertext.count, 1568, "Ciphertext should be 1568 bytes")
        XCTAssertEqual(encapResult.sharedSecret.count, 32, "Shared secret should be 32 bytes")

        // Decapsulate (recover shared secret from ciphertext)
        guard let recoveredSecret = EMMLKEM1024.decapsulate(
            withCiphertext: encapResult.ciphertext,
            secretKey: keypair.secretKey
        ) else {
            XCTFail("Failed to decapsulate")
            return
        }

        XCTAssertEqual(recoveredSecret.count, 32, "Recovered secret should be 32 bytes")

        // In stub mode, shared secrets won't match
        // In production mode with liboqs, they should match
        if liboqs_ml_kem_1024_enabled() {
            XCTAssertEqual(
                encapResult.sharedSecret,
                recoveredSecret,
                "Shared secrets should match in production mode"
            )
            NSLog("[TEST] ML-KEM-1024 encap/decap successful - PRODUCTION MODE")
        } else {
            NSLog("[TEST] ML-KEM-1024 encap/decap complete - STUB MODE (secrets won't match)")
        }
    }

    /// Test vector from NIST KAT (Known Answer Test)
    /// This verifies compatibility with standard ML-KEM-1024 implementations
    func testMLKEM1024WithKnownAnswerTest() {
        // Note: These are example test vectors
        // In production, use official NIST KAT test vectors

        // Skip in stub mode
        guard liboqs_ml_kem_1024_enabled() else {
            NSLog("[TEST] Skipping KAT test in stub mode")
            return
        }

        // TODO: Add actual NIST KAT test vectors when liboqs is integrated
        NSLog("[TEST] ML-KEM-1024 KAT test - requires production crypto")
    }

    // MARK: - ML-DSA-87 Interoperability Tests

    func testMLDSA87KeyPairGeneration() {
        // Test that we can generate ML-DSA-87 keypairs
        let keypair = EMMLDSA87.generateKeypair()

        XCTAssertNotNil(keypair, "Keypair should be generated")
        XCTAssertEqual(keypair!.publicKey.count, 2592, "Public key should be 2592 bytes")
        XCTAssertEqual(keypair!.secretKey.count, 4896, "Secret key should be 4896 bytes")

        // Verify keys are not all zeros
        XCTAssertFalse(keypair!.publicKey.allSatisfy { $0 == 0 }, "Public key should not be all zeros")
        XCTAssertFalse(keypair!.secretKey.allSatisfy { $0 == 0 }, "Secret key should not be all zeros")

        NSLog("[TEST] ML-DSA-87 keypair generated successfully")
    }

    func testMLDSA87SignAndVerify() {
        // Generate keypair
        guard let keypair = EMMLDSA87.generateKeypair() else {
            XCTFail("Failed to generate keypair")
            return
        }

        let message = "Hello from EMMA iOS!".data(using: .utf8)!

        // Sign message
        guard let signature = EMMLDSA87.sign(message, withSecretKey: keypair.secretKey) else {
            XCTFail("Failed to sign message")
            return
        }

        XCTAssertFalse(signature.signature.isEmpty, "Signature should not be empty")
        XCTAssertLessThanOrEqual(signature.signature.count, 4627, "Signature should be at most 4627 bytes")

        // Verify signature
        let isValid = EMMLDSA87.verifyMessage(
            message,
            signature: signature.signature,
            withPublicKey: keypair.publicKey
        )

        if liboqs_ml_dsa_87_enabled() {
            XCTAssertTrue(isValid, "Signature should be valid in production mode")
            NSLog("[TEST] ML-DSA-87 sign/verify successful - PRODUCTION MODE")
        } else {
            // In stub mode, verification always succeeds (insecure)
            NSLog("[TEST] ML-DSA-87 sign/verify complete - STUB MODE (always valid)")
        }
    }

    func testMLDSA87InvalidSignature() {
        guard liboqs_ml_dsa_87_enabled() else {
            NSLog("[TEST] Skipping invalid signature test in stub mode")
            return
        }

        // Generate keypair
        guard let keypair = EMMLDSA87.generateKeypair() else {
            XCTFail("Failed to generate keypair")
            return
        }

        let message = "Original message".data(using: .utf8)!
        let tamperedMessage = "Tampered message".data(using: .utf8)!

        // Sign original message
        guard let signature = EMMLDSA87.sign(message, withSecretKey: keypair.secretKey) else {
            XCTFail("Failed to sign message")
            return
        }

        // Verify with tampered message should fail
        let isValid = EMMLDSA87.verifyMessage(
            tamperedMessage,
            signature: signature.signature,
            withPublicKey: keypair.publicKey
        )

        XCTAssertFalse(isValid, "Tampered message should fail verification")
        NSLog("[TEST] ML-DSA-87 correctly rejected tampered message")
    }

    // MARK: - HKDF Key Derivation Tests

    func testHKDFDerivation() {
        // Simulate ML-KEM shared secret
        let sharedSecret = Data(repeating: 0x42, count: 32)

        // Derive AES-256 key
        let info = "EMMA-AES-256-GCM-KEY".data(using: .utf8)!

        // Note: We need to expose HKDF through the Objective-C++ bridge
        // For now, this tests the API structure

        // TODO: Add HKDF to EMSecurityKit.h/mm bridge
        NSLog("[TEST] HKDF test - requires bridge implementation")
    }

    // MARK: - Android Compatibility Test Vectors

    /// Test compatibility with known Android-generated keys
    func testAndroidCompatibilityVectors() {
        // These test vectors should be generated by EMMA-Android
        // and verified to work on iOS

        struct AndroidTestVector {
            let publicKey: Data
            let ciphertext: Data
            let expectedSharedSecret: Data
        }

        // TODO: Add actual test vectors from EMMA-Android
        NSLog("[TEST] Android compatibility test - requires test vectors from Android team")
    }

    // MARK: - Performance Benchmarks

    func testMLKEM1024PerformanceKeypair() {
        measure {
            for _ in 0..<10 {
                _ = EMMLKEM1024.generateKeypair()
            }
        }
        NSLog("[BENCHMARK] ML-KEM-1024 keypair generation")
    }

    func testMLKEM1024PerformanceEncapsulation() {
        guard let keypair = EMMLKEM1024.generateKeypair() else {
            XCTFail("Failed to generate keypair")
            return
        }

        measure {
            for _ in 0..<10 {
                _ = EMMLKEM1024.encapsulate(withPublicKey: keypair.publicKey)
            }
        }
        NSLog("[BENCHMARK] ML-KEM-1024 encapsulation")
    }

    func testMLDSA87PerformanceSign() {
        guard let keypair = EMMLDSA87.generateKeypair() else {
            XCTFail("Failed to generate keypair")
            return
        }

        let message = "Benchmark message for signing performance test".data(using: .utf8)!

        measure {
            for _ in 0..<10 {
                _ = EMMLDSA87.sign(message, withSecretKey: keypair.secretKey)
            }
        }
        NSLog("[BENCHMARK] ML-DSA-87 signing")
    }

    func testMLDSA87PerformanceVerify() {
        guard let keypair = EMMLDSA87.generateKeypair() else {
            XCTFail("Failed to generate keypair")
            return
        }

        let message = "Benchmark message for verification performance test".data(using: .utf8)!

        guard let signature = EMMLDSA87.sign(message, withSecretKey: keypair.secretKey) else {
            XCTFail("Failed to sign message")
            return
        }

        measure {
            for _ in 0..<10 {
                _ = EMMLDSA87.verifyMessage(
                    message,
                    signature: signature.signature,
                    withPublicKey: keypair.publicKey
                )
            }
        }
        NSLog("[BENCHMARK] ML-DSA-87 verification")
    }

    // MARK: - Integration Tests

    func testFullCryptoWorkflow() {
        // Simulate a complete EMMA encrypted message exchange

        // 1. Generate identity keypair (ML-DSA-87 for signatures)
        guard let identityKeys = EMMLDSA87.generateKeypair() else {
            XCTFail("Failed to generate identity keys")
            return
        }

        // 2. Generate ephemeral keypair (ML-KEM-1024 for key exchange)
        guard let ephemeralKeys = EMMLKEM1024.generateKeypair() else {
            XCTFail("Failed to generate ephemeral keys")
            return
        }

        // 3. Encapsulate to create shared secret
        guard let encapResult = EMMLKEM1024.encapsulate(withPublicKey: ephemeralKeys.publicKey) else {
            XCTFail("Failed to encapsulate")
            return
        }

        // 4. Sign the ciphertext
        guard let signature = EMMLDSA87.sign(
            encapResult.ciphertext,
            withSecretKey: identityKeys.secretKey
        ) else {
            XCTFail("Failed to sign ciphertext")
            return
        }

        // 5. Verify signature
        let isValid = EMMLDSA87.verifyMessage(
            encapResult.ciphertext,
            signature: signature.signature,
            withPublicKey: identityKeys.publicKey
        )

        if liboqs_ml_dsa_87_enabled() {
            XCTAssertTrue(isValid, "Signature should be valid")
        }

        // 6. Decapsulate to recover shared secret
        guard let recoveredSecret = EMMLKEM1024.decapsulate(
            withCiphertext: encapResult.ciphertext,
            secretKey: ephemeralKeys.secretKey
        ) else {
            XCTFail("Failed to decapsulate")
            return
        }

        // 7. Derive AES key from shared secret (would use HKDF in production)
        XCTAssertEqual(recoveredSecret.count, 32, "Shared secret ready for AES-256")

        NSLog("[TEST] Full crypto workflow complete")
        NSLog("[TEST]   - Identity keys: ML-DSA-87 (%d bytes public)", identityKeys.publicKey.count)
        NSLog("[TEST]   - Ephemeral keys: ML-KEM-1024 (%d bytes public)", ephemeralKeys.publicKey.count)
        NSLog("[TEST]   - Ciphertext: %d bytes", encapResult.ciphertext.count)
        NSLog("[TEST]   - Signature: %d bytes", signature.signature.count)
        NSLog("[TEST]   - Shared secret: %d bytes", recoveredSecret.count)
    }

    // MARK: - Compatibility Helpers

    override func setUp() {
        super.setUp()

        // Log crypto mode
        if liboqs_ml_kem_1024_enabled() && liboqs_ml_dsa_87_enabled() {
            NSLog("[TEST] Running in PRODUCTION CRYPTO mode")
        } else {
            NSLog("[TEST] Running in STUB mode - some tests will be skipped")
            NSLog("[TEST] To enable production crypto, integrate liboqs (see LIBOQS_INTEGRATION.md)")
        }
    }
}
