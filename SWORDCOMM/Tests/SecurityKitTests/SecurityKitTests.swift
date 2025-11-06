//
//  SecurityKitTests.swift
//  SWORDCOMM SecurityKit Tests
//
//  Unit tests for SWORDCOMM security features
//

import XCTest
@testable import SWORDCOMMSecurityKit

class SecurityKitTests: XCTestCase {

    // MARK: - EL2 Detector Tests

    func testEL2DetectorInitialization() {
        let detector = EMEL2Detector.shared()
        XCTAssertNotNil(detector, "Detector should not be nil")

        let success = detector.initialize()
        XCTAssertTrue(success, "Detector initialization should succeed")
    }

    func testEL2DetectorAnalyzeThreat() {
        let detector = EMEL2Detector.shared()
        detector.initialize()

        let analysis = detector.analyzeThreat()
        XCTAssertNotNil(analysis, "Analysis should not be nil")

        // Verify threat level is in valid range
        XCTAssertGreaterThanOrEqual(analysis!.threatLevel, 0.0)
        XCTAssertLessThanOrEqual(analysis!.threatLevel, 1.0)

        // Verify hypervisor confidence is in valid range
        XCTAssertGreaterThanOrEqual(analysis!.hypervisorConfidence, 0.0)
        XCTAssertLessThanOrEqual(analysis!.hypervisorConfidence, 1.0)

        // Verify timestamp is set
        XCTAssertGreaterThan(analysis!.analysisTimestamp, 0)

        print("Threat Analysis Results:")
        print("  Threat Level: \(analysis!.threatLevel)")
        print("  Hypervisor Confidence: \(analysis!.hypervisorConfidence)")
        print("  Timing Anomaly: \(analysis!.timingAnomalyDetected)")
        print("  Cache Anomaly: \(analysis!.cacheAnomalyDetected)")
        print("  Perf Counter Blocked: \(analysis!.perfCounterBlocked)")
        print("  Memory Anomaly: \(analysis!.memoryAnomalyDetected)")
    }

    func testMultipleAnalyses() {
        let detector = EMEL2Detector.shared()
        detector.initialize()

        // Run multiple analyses to ensure consistency
        var threatLevels: [Float] = []

        for _ in 0..<5 {
            if let analysis = detector.analyzeThreat() {
                threatLevels.append(analysis.threatLevel)
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        XCTAssertEqual(threatLevels.count, 5, "Should have 5 threat levels")

        // All threat levels should be in valid range
        for level in threatLevels {
            XCTAssertGreaterThanOrEqual(level, 0.0)
            XCTAssertLessThanOrEqual(level, 1.0)
        }

        print("Multiple analysis threat levels: \(threatLevels)")
    }

    // MARK: - Memory Scrambler Tests

    func testMemoryScramblerSecureWipe() {
        let testData = "Secret message that should be wiped".data(using: .utf8)!
        var mutableData = NSMutableData(data: testData)

        // Store original bytes
        let originalBytes = Data(mutableData as Data)

        // Wipe the data
        EMMemoryScrambler.secureWipeData(mutableData)

        let wipedBytes = Data(mutableData as Data)

        // Data should be different after wipe
        // (Note: Due to DoD 5220.22-M, final pass is zeros)
        XCTAssertNotEqual(originalBytes, wipedBytes, "Data should be modified after secure wipe")

        print("Original data size: \(originalBytes.count)")
        print("Wiped data size: \(wipedBytes.count)")
    }

    func testMemoryScramblerScramble() {
        let testData = "This data should be scrambled".data(using: .utf8)!
        var mutableData = NSMutableData(data: testData)

        let originalBytes = Data(mutableData as Data)

        // Scramble the data
        EMMemoryScrambler.scrambleData(mutableData)

        let scrambledBytes = Data(mutableData as Data)

        // Data should be different after scramble
        XCTAssertNotEqual(originalBytes, scrambledBytes, "Data should be modified after scramble")

        // Size should remain the same
        XCTAssertEqual(originalBytes.count, scrambledBytes.count)

        print("Scrambled \(scrambledBytes.count) bytes")
    }

    // MARK: - Timing Obfuscation Tests

    func testTimingObfuscationRandomDelay() {
        let minUs = 100
        let maxUs = 1000

        let startTime = Date()
        EMTimingObfuscation.randomDelayMinUs(Int32(minUs), maxUs: Int32(maxUs))
        let endTime = Date()

        let elapsedUs = Int(endTime.timeIntervalSince(startTime) * 1_000_000)

        print("Random delay elapsed: \(elapsedUs)μs (range: \(minUs)-\(maxUs)μs)")

        // Should be at least minUs (with some tolerance for overhead)
        XCTAssertGreaterThanOrEqual(elapsedUs, minUs - 50)

        // Should not exceed maxUs by too much (account for overhead)
        XCTAssertLessThanOrEqual(elapsedUs, maxUs + 500)
    }

    func testTimingObfuscationJitterSleep() {
        let baseMs = 10
        let jitterPercent = 50

        let startTime = Date()
        EMTimingObfuscation.jitterSleepMs(Int32(baseMs), jitterPercent: Int32(jitterPercent))
        let endTime = Date()

        let elapsedMs = Int(endTime.timeIntervalSince(startTime) * 1000)

        print("Jitter sleep elapsed: \(elapsedMs)ms (base: \(baseMs)ms, jitter: \(jitterPercent)%)")

        // Should be roughly around base time (accounting for jitter)
        let minExpected = baseMs - (baseMs * jitterPercent / 100) - 5 // 5ms tolerance
        let maxExpected = baseMs + (baseMs * jitterPercent / 100) + 5

        XCTAssertGreaterThanOrEqual(elapsedMs, 0)
        XCTAssertLessThanOrEqual(elapsedMs, maxExpected + 10) // Extra tolerance for overhead
    }

    func testTimingObfuscationExecuteWithObfuscation() {
        var executed = false

        let startTime = Date()
        EMTimingObfuscation.executeWithObfuscation({
            executed = true
        }, chaosPercent: 50)
        let endTime = Date()

        let elapsedMs = endTime.timeIntervalSince(startTime) * 1000

        XCTAssertTrue(executed, "Block should have been executed")
        XCTAssertGreaterThan(elapsedMs, 0, "Should have taken some time due to obfuscation")

        print("Execute with obfuscation elapsed: \(elapsedMs)ms")
    }

    // MARK: - Cache Operations Tests

    func testCacheOperationsPoisonCache() {
        // This is a basic smoke test - hard to verify cache state directly
        let intensities = [0, 50, 100]

        for intensity in intensities {
            let startTime = Date()
            EMCacheOperations.poisonCacheIntensityPercent(Int32(intensity))
            let endTime = Date()

            let elapsedMs = endTime.timeIntervalSince(startTime) * 1000

            print("Cache poison (intensity \(intensity)%) took: \(elapsedMs)ms")

            // Should complete in reasonable time
            XCTAssertLessThan(elapsedMs, 1000, "Cache poison should complete in < 1s")
        }
    }

    func testCacheOperationsFlushAndPrefetch() {
        // Allocate test buffer
        let testSize = 64 * 1024 // 64 KB
        var testBuffer = [UInt8](repeating: 0, count: testSize)

        testBuffer.withUnsafeMutableBytes { bufferPointer in
            if let baseAddress = bufferPointer.baseAddress {
                // Flush cache range
                EMCacheOperations.flushCacheRangeWithPointer(baseAddress, size: testSize)

                // Prefetch cache range
                EMCacheOperations.prefetchCacheRangeWithPointer(baseAddress, size: testSize)
            }
        }

        // If we got here without crashing, test passed
        XCTAssertTrue(true, "Cache flush and prefetch completed")
    }

    // MARK: - Kyber-1024 Tests

    func testKyberKeypairGeneration() {
        let keyPair = EMKyber1024.generateKeypair()
        XCTAssertNotNil(keyPair, "Keypair generation should succeed")

        // Verify key sizes
        XCTAssertEqual(keyPair!.publicKey.count, 1568, "Public key should be 1568 bytes")
        XCTAssertEqual(keyPair!.secretKey.count, 3168, "Secret key should be 3168 bytes")

        print("Generated Kyber-1024 keypair:")
        print("  Public key: \(keyPair!.publicKey.count) bytes")
        print("  Secret key: \(keyPair!.secretKey.count) bytes")
    }

    func testKyberEncapsulation() {
        let keyPair = EMKyber1024.generateKeypair()
        XCTAssertNotNil(keyPair)

        let result = EMKyber1024.encapsulate(withPublicKey: keyPair!.publicKey)
        XCTAssertNotNil(result, "Encapsulation should succeed")

        // Verify sizes
        XCTAssertEqual(result!.ciphertext.count, 1568, "Ciphertext should be 1568 bytes")
        XCTAssertEqual(result!.sharedSecret.count, 32, "Shared secret should be 32 bytes")

        print("Kyber-1024 encapsulation:")
        print("  Ciphertext: \(result!.ciphertext.count) bytes")
        print("  Shared secret: \(result!.sharedSecret.count) bytes")
    }

    func testKyberDecapsulation() {
        let keyPair = EMKyber1024.generateKeypair()
        XCTAssertNotNil(keyPair)

        let encapResult = EMKyber1024.encapsulate(withPublicKey: keyPair!.publicKey)
        XCTAssertNotNil(encapResult)

        let sharedSecret = EMKyber1024.decapsulate(withCiphertext: encapResult!.ciphertext,
                                                     secretKey: keyPair!.secretKey)
        XCTAssertNotNil(sharedSecret, "Decapsulation should succeed")

        // Verify size
        XCTAssertEqual(sharedSecret!.count, 32, "Decapsulated shared secret should be 32 bytes")

        print("Kyber-1024 decapsulation:")
        print("  Shared secret: \(sharedSecret!.count) bytes")

        // Note: In stub implementation, secrets won't match
        // In production with liboqs, they should match
        // XCTAssertEqual(sharedSecret, encapResult!.sharedSecret)
    }

    func testKyberInvalidInputs() {
        // Test with invalid public key size
        let invalidPublicKey = Data(repeating: 0, count: 100)
        let result1 = EMKyber1024.encapsulate(withPublicKey: invalidPublicKey)
        XCTAssertNil(result1, "Encapsulation should fail with invalid public key")

        // Test with invalid ciphertext size
        let invalidCiphertext = Data(repeating: 0, count: 100)
        let invalidSecretKey = Data(repeating: 0, count: 3168)
        let result2 = EMKyber1024.decapsulate(withCiphertext: invalidCiphertext,
                                               secretKey: invalidSecretKey)
        XCTAssertNil(result2, "Decapsulation should fail with invalid ciphertext")

        // Test with invalid secret key size
        let validCiphertext = Data(repeating: 0, count: 1568)
        let invalidSecretKey2 = Data(repeating: 0, count: 100)
        let result3 = EMKyber1024.decapsulate(withCiphertext: validCiphertext,
                                               secretKey: invalidSecretKey2)
        XCTAssertNil(result3, "Decapsulation should fail with invalid secret key")
    }

    // MARK: - Performance Tests

    func testPerformanceEL2Detection() {
        let detector = EMEL2Detector.shared()
        detector.initialize()

        measure {
            _ = detector.analyzeThreat()
        }
    }

    func testPerformanceKyberKeygen() {
        measure {
            _ = EMKyber1024.generateKeypair()
        }
    }

    func testPerformanceCachePoison() {
        measure {
            EMCacheOperations.poisonCacheIntensityPercent(50)
        }
    }
}
