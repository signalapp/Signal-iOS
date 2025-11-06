//
//  TranslationKitTests.swift
//  SWORDCOMM TranslationKit Tests
//
//  Unit tests for SWORDCOMM translation features
//

import XCTest
@testable import SWORDCOMMTranslationKit

class TranslationKitTests: XCTestCase {

    // MARK: - Translation Engine Tests

    func testTranslationEngineInitialization() {
        let engine = EMTranslationEngine.shared()
        XCTAssertNotNil(engine, "Engine should not be nil")

        // Test with non-existent path (should fail gracefully)
        let success = engine.initialize(withModelPath: "/nonexistent/model.mlmodel")
        XCTAssertFalse(success, "Initialization should fail with non-existent path")
    }

    func testTranslationEngineIsModelLoaded() {
        let engine = EMTranslationEngine.shared()

        // Initially should not be loaded
        XCTAssertFalse(engine.isModelLoaded(), "Model should not be loaded initially")
    }

    func testTranslationBasic() {
        let engine = EMTranslationEngine.shared()

        // Test translation with stub implementation
        let result = engine.translateText("Hej",
                                          fromLanguage: "da",
                                          toLanguage: "en")

        XCTAssertNotNil(result, "Translation should return result")
        XCTAssertFalse(result!.translatedText.isEmpty, "Translated text should not be empty")

        print("Translation result:")
        print("  Input: Hej (da)")
        print("  Output: \(result!.translatedText) (en)")
        print("  Confidence: \(result!.confidence)")
        print("  Time: \(result!.inferenceTimeUs)μs")
        print("  Used network: \(result!.usedNetwork)")

        // Verify confidence is in valid range
        XCTAssertGreaterThanOrEqual(result!.confidence, 0.0)
        XCTAssertLessThanOrEqual(result!.confidence, 1.0)

        // Verify inference time is recorded
        XCTAssertGreaterThan(result!.inferenceTimeUs, 0)
    }

    func testTranslationLanguagePairSupport() {
        let engine = EMTranslationEngine.shared()

        // Currently only da->en is supported
        XCTAssertTrue(engine.isLanguagePairSupportedFrom("da", to: "en"),
                     "Danish to English should be supported")

        XCTAssertFalse(engine.isLanguagePairSupportedFrom("fr", to: "en"),
                      "French to English should not be supported")

        XCTAssertFalse(engine.isLanguagePairSupportedFrom("en", to: "da"),
                      "English to Danish should not be supported (reverse)")
    }

    func testTranslationNetworkFallback() {
        let engine = EMTranslationEngine.shared()

        // Test network fallback setting
        engine.networkFallbackEnabled = true
        XCTAssertTrue(engine.networkFallbackEnabled, "Network fallback should be enabled")

        engine.networkFallbackEnabled = false
        XCTAssertFalse(engine.networkFallbackEnabled, "Network fallback should be disabled")
    }

    func testTranslationMultipleTexts() {
        let engine = EMTranslationEngine.shared()

        let testPhrases = [
            "Hej",
            "Godmorgen",
            "Hvordan har du det?",
            "Tak skal du have"
        ]

        for phrase in testPhrases {
            let result = engine.translateText(phrase,
                                             fromLanguage: "da",
                                             toLanguage: "en")

            XCTAssertNotNil(result, "Translation should succeed for: \(phrase)")
            print("Translated: '\(phrase)' -> '\(result!.translatedText)'")
        }
    }

    func testTranslationEmptyInput() {
        let engine = EMTranslationEngine.shared()

        let result = engine.translateText("",
                                          fromLanguage: "da",
                                          toLanguage: "en")

        // Empty input should still return a result (empty or unchanged)
        XCTAssertNotNil(result, "Should handle empty input gracefully")
    }

    func testTranslationLongText() {
        let engine = EMTranslationEngine.shared()

        let longText = String(repeating: "Dette er en lang tekst. ", count: 100)

        let startTime = Date()
        let result = engine.translateText(longText,
                                          fromLanguage: "da",
                                          toLanguage: "en")
        let endTime = Date()

        let elapsedMs = endTime.timeIntervalSince(startTime) * 1000

        XCTAssertNotNil(result, "Should handle long text")

        print("Long text translation:")
        print("  Input length: \(longText.count) characters")
        print("  Output length: \(result!.translatedText.count) characters")
        print("  Time: \(elapsedMs)ms")
    }

    // MARK: - Performance Tests

    func testPerformanceTranslationShort() {
        let engine = EMTranslationEngine.shared()

        measure {
            _ = engine.translateText("Hej",
                                    fromLanguage: "da",
                                    toLanguage: "en")
        }
    }

    func testPerformanceTranslationMedium() {
        let engine = EMTranslationEngine.shared()
        let mediumText = "Dette er en mellemlang tekst til test af oversættelse"

        measure {
            _ = engine.translateText(mediumText,
                                    fromLanguage: "da",
                                    toLanguage: "en")
        }
    }

    func testPerformanceMultipleTranslations() {
        let engine = EMTranslationEngine.shared()

        let phrases = ["Hej", "Godmorgen", "Tak", "Farvel", "Ja"]

        measure {
            for phrase in phrases {
                _ = engine.translateText(phrase,
                                        fromLanguage: "da",
                                        toLanguage: "en")
            }
        }
    }

    // MARK: - Thread Safety Tests

    func testConcurrentTranslations() {
        let engine = EMTranslationEngine.shared()
        let expectation = self.expectation(description: "Concurrent translations")
        expectation.expectedFulfillmentCount = 10

        let queue = DispatchQueue(label: "translation.test", attributes: .concurrent)

        for i in 0..<10 {
            queue.async {
                let result = engine.translateText("Test \(i)",
                                                  fromLanguage: "da",
                                                  toLanguage: "en")

                XCTAssertNotNil(result, "Concurrent translation \(i) should succeed")
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 10, handler: nil)
    }

    // MARK: - Edge Cases

    func testTranslationWithSpecialCharacters() {
        let engine = EMTranslationEngine.shared()

        let specialTexts = [
            "Hej! Hvordan går det?",
            "Test @#$%^&*()",
            "Unicode: 你好 مرحبا",
            "Emoji: 😀👍🎉",
            "Newlines:\nMultiple\nLines"
        ]

        for text in specialTexts {
            let result = engine.translateText(text,
                                             fromLanguage: "da",
                                             toLanguage: "en")

            XCTAssertNotNil(result, "Should handle special characters: \(text)")
            print("Special char translation: '\(text)' -> '\(result!.translatedText)'")
        }
    }

    func testTranslationWithNumbers() {
        let engine = EMTranslationEngine.shared()

        let numberedTexts = [
            "1234",
            "Test 123",
            "123 test 456",
            "Version 1.2.3"
        ]

        for text in numberedTexts {
            let result = engine.translateText(text,
                                             fromLanguage: "da",
                                             toLanguage: "en")

            XCTAssertNotNil(result, "Should handle numbers: \(text)")
        }
    }
}
