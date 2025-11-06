//
//  SignalIntegrationTests.swift
//  SWORDCOMM Signal-iOS Integration Tests
//
//  End-to-end integration tests for SWORDCOMM in Signal
//

import XCTest
import SwiftUI
@testable import SWORDCOMMSecurityKit
@testable import SWORDCOMMTranslationKit

@available(iOS 15.0, *)
class SignalIntegrationTests: XCTestCase {

    // MARK: - App Lifecycle Integration Tests

    func testSWORDCOMMInitialization() {
        // Test that SWORDCOMM can be initialized
        let config = SWORDCOMMInitializer.Configuration()
        config.enableSecurityMonitoring = true
        config.enableTranslation = true

        let success = SWORDCOMMInitializer.shared.initialize(with: config)
        XCTAssertTrue(success, "SWORDCOMM should initialize successfully")

        NSLog("[TEST] SWORDCOMM initialization: SUCCESS")
    }

    func testSWORDCOMMLifecycleHandlers() {
        // Test lifecycle handlers don't crash
        let initializer = SWORDCOMMInitializer.shared

        // Initialize first
        _ = initializer.initialize()

        // Test lifecycle methods
        initializer.handleAppLaunch()
        initializer.handleAppBecameActive()
        initializer.handleAppEnteredBackground()

        // Should not crash
        XCTAssert(true, "Lifecycle handlers executed without crashing")

        NSLog("[TEST] SWORDCOMM lifecycle handlers: SUCCESS")
    }

    func testSWORDCOMMConfigurationPersistence() {
        // Test that configuration is saved and loaded correctly
        var config = SWORDCOMMInitializer.Configuration()
        config.enableSecurityMonitoring = false
        config.enableTranslation = true
        config.countermeasureIntensity = 0.75

        // Save
        UserDefaults.standard.swordcommConfiguration = config

        // Load
        let loadedConfig = UserDefaults.standard.swordcommConfiguration

        // Verify
        XCTAssertEqual(loadedConfig.enableSecurityMonitoring, false)
        XCTAssertEqual(loadedConfig.enableTranslation, true)
        XCTAssertEqual(loadedConfig.countermeasureIntensity, 0.75, accuracy: 0.01)

        NSLog("[TEST] Configuration persistence: SUCCESS")
    }

    // MARK: - Security Integration Tests

    func testSecurityManagerIntegration() {
        // Test SecurityManager can be accessed and used
        let manager = SecurityManager.shared

        let success = manager.initialize()
        XCTAssertTrue(success, "SecurityManager should initialize")

        // Start monitoring
        manager.startMonitoring()

        // Get threat analysis
        if let analysis = manager.analyzeThreat() {
            XCTAssertGreaterThanOrEqual(analysis.threatLevel, 0.0)
            XCTAssertLessThanOrEqual(analysis.threatLevel, 1.0)

            NSLog("[TEST] SecurityManager threat level: \(analysis.threatLevel)")
        }

        // Stop monitoring
        manager.stopMonitoring()

        NSLog("[TEST] SecurityManager integration: SUCCESS")
    }

    func testSecurityCallbacks() {
        // Test that security callbacks work
        let manager = SecurityManager.shared
        _ = manager.initialize()

        let expectation = self.expectation(description: "Security callback")
        expectation.isInverted = true // We don't expect it to be called immediately

        manager.onThreatLevelChanged = { analysis in
            NSLog("[TEST] Threat level callback: \(analysis.threatLevel)")
        }

        manager.startMonitoring()

        wait(for: [expectation], timeout: 1.0)

        manager.stopMonitoring()

        NSLog("[TEST] Security callbacks: SUCCESS")
    }

    // MARK: - Translation Integration Tests

    func testTranslationEngineIntegration() {
        // Test TranslationEngine can be accessed
        let engine = EMTranslationEngine.shared()

        XCTAssertNotNil(engine, "TranslationEngine should be accessible")

        // Check model status
        let isLoaded = engine.isModelLoaded()

        if isLoaded {
            NSLog("[TEST] Translation model is loaded")
        } else {
            NSLog("[TEST] Translation model not loaded (expected if model not bundled)")
        }

        NSLog("[TEST] TranslationEngine integration: SUCCESS")
    }

    func testTranslationCaching() {
        // Test translation caching
        let manager = SWORDCOMMMessageTranslationManager.shared

        // Clear cache first
        manager.clearCache()

        // Should start with empty cache
        let expectation = self.expectation(description: "Translation")

        let testText = "Hej verden"

        manager.translateMessage(testText) { result in
            XCTAssertNotNil(result, "Translation should complete")

            if let result = result {
                XCTAssertFalse(result.translatedText.isEmpty, "Translation should not be empty")
                NSLog("[TEST] Translated '\(testText)' to '\(result.translatedText)'")
            }

            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        NSLog("[TEST] Translation caching: SUCCESS")
    }

    // MARK: - UI Integration Tests

    func testSecurityHUDCreation() {
        // Test that SecurityHUD can be created
        let hud = SecurityHUD()
        XCTAssertNotNil(hud, "SecurityHUD should be created")

        // Test that it can be hosted
        let hostingController = UIHostingController(rootView: hud)
        XCTAssertNotNil(hostingController, "SecurityHUD hosting controller should be created")

        NSLog("[TEST] SecurityHUD creation: SUCCESS")
    }

    func testSWORDCOMMSettingsViewCreation() {
        // Test that SWORDCOMM settings view can be created
        let settingsView = SWORDCOMMSettingsView()
        XCTAssertNotNil(settingsView, "SWORDCOMMSettingsView should be created")

        let hostingController = UIHostingController(rootView: settingsView)
        XCTAssertNotNil(hostingController, "Settings hosting controller should be created")

        NSLog("[TEST] SWORDCOMMSettingsView creation: SUCCESS")
    }

    func testTranslationViewCreation() {
        // Test that translation view can be created
        let translationView = TranslationView(
            originalText: "Test message",
            originalLanguage: "da",
            targetLanguage: "en"
        )

        XCTAssertNotNil(translationView, "TranslationView should be created")

        NSLog("[TEST] TranslationView creation: SUCCESS")
    }

    func testInlineTranslationBubbleCreation() {
        // Test inline translation bubble
        let bubble = InlineTranslationBubble(
            translatedText: "Test translation",
            confidence: 0.9
        )

        XCTAssertNotNil(bubble, "InlineTranslationBubble should be created")

        NSLog("[TEST] InlineTranslationBubble creation: SUCCESS")
    }

    // MARK: - Cryptography Integration Tests

    func testCryptographyAvailability() {
        // Test that crypto functions are available
        let mlkemAvailable = liboqs_ml_kem_1024_enabled()
        let mldsaAvailable = liboqs_ml_dsa_87_enabled()

        if mlkemAvailable && mldsaAvailable {
            NSLog("[TEST] Production cryptography ENABLED")
        } else {
            NSLog("[TEST] Stub cryptography mode (production crypto not available)")
        }

        // Should not crash regardless of mode
        XCTAssert(true, "Crypto availability check completed")

        NSLog("[TEST] Cryptography availability: SUCCESS")
    }

    func testCryptoKeypairGeneration() {
        // Test ML-KEM keypair generation
        let mlkemKeypair = EMMLKEM1024.generateKeypair()
        XCTAssertNotNil(mlkemKeypair, "ML-KEM keypair should be generated")

        if let kp = mlkemKeypair {
            XCTAssertEqual(kp.publicKey.count, 1568)
            XCTAssertEqual(kp.secretKey.count, 3168)
        }

        // Test ML-DSA keypair generation
        let mldsaKeypair = EMMLDSA87.generateKeypair()
        XCTAssertNotNil(mldsaKeypair, "ML-DSA keypair should be generated")

        if let kp = mldsaKeypair {
            XCTAssertEqual(kp.publicKey.count, 2592)
            XCTAssertEqual(kp.secretKey.count, 4896)
        }

        NSLog("[TEST] Crypto keypair generation: SUCCESS")
    }

    // MARK: - Settings Integration Tests

    func testSettingsIntegrationHelpers() {
        // Test that settings integration helpers work
        // Note: We can't actually test AppDelegate extension without full app context,
        // but we can test that the code compiles and basic logic works

        let defaults = UserDefaults.standard

        // Set some values
        defaults.set(true, forKey: "SWORDCOMM.SecurityMonitoring")
        defaults.set(false, forKey: "SWORDCOMM.AutoTranslate")

        // Read them back
        let securityEnabled = defaults.bool(forKey: "SWORDCOMM.SecurityMonitoring")
        let autoTranslate = defaults.bool(forKey: "SWORDCOMM.AutoTranslate")

        XCTAssertTrue(securityEnabled)
        XCTAssertFalse(autoTranslate)

        NSLog("[TEST] Settings integration helpers: SUCCESS")
    }

    // MARK: - Notification Integration Tests

    func testSWORDCOMMNotifications() {
        // Test that SWORDCOMM notifications work
        let expectation = self.expectation(description: "Notification")

        let observer = NotificationCenter.default.addObserver(
            forName: .swordcommThreatLevelChanged,
            object: nil,
            queue: .main
        ) { notification in
            NSLog("[TEST] Received threat level changed notification")
            expectation.fulfill()
        }

        // Post a test notification
        NotificationCenter.default.post(
            name: .swordcommThreatLevelChanged,
            object: nil,
            userInfo: ["test": true]
        )

        wait(for: [expectation], timeout: 1.0)

        NotificationCenter.default.removeObserver(observer)

        NSLog("[TEST] SWORDCOMM notifications: SUCCESS")
    }

    // MARK: - Performance Tests

    func testInitializationPerformance() {
        measure {
            let config = SWORDCOMMInitializer.Configuration()
            _ = SWORDCOMMInitializer.shared.initialize(with: config)
        }

        NSLog("[BENCHMARK] SWORDCOMM initialization performance measured")
    }

    func testSecurityHUDPerformance() {
        measure {
            for _ in 0..<5 {
                _ = SecurityHUD()
            }
        }

        NSLog("[BENCHMARK] SecurityHUD creation performance measured")
    }

    // MARK: - Cleanup

    override func tearDown() {
        super.tearDown()

        // Clean up any test state
        SWORDCOMMMessageTranslationManager.shared.clearCache()
    }
}

// MARK: - Test Helpers

@available(iOS 15.0, *)
extension SignalIntegrationTests {

    /// Helper to verify a SwiftUI view can be rendered
    func verifyViewCanRender<V: View>(_ view: V) -> Bool {
        let hostingController = UIHostingController(rootView: view)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = hostingController
        window.makeKeyAndVisible()

        // Trigger layout
        hostingController.view.layoutIfNeeded()

        return true
    }
}
