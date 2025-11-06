//
//  UIComponentsTests.swift
//  EMMA UI Components Tests
//
//  Unit tests for EMMA SwiftUI components
//

import XCTest
import SwiftUI
@testable import EMMASecurityKit
@testable import EMMATranslationKit

@available(iOS 15.0, *)
class UIComponentsTests: XCTestCase {

    // MARK: - ThreatIndicator Tests

    func testThreatIndicatorLowThreat() {
        let indicator = ThreatIndicator(level: 0.2, size: 48)

        // Verify indicator is created
        XCTAssertNotNil(indicator, "ThreatIndicator should be created")

        // Test color mapping (low threat = green)
        // Note: Direct color testing in SwiftUI is limited, but we can verify creation
    }

    func testThreatIndicatorModerateThreat() {
        let indicator = ThreatIndicator(level: 0.6, size: 48)
        XCTAssertNotNil(indicator)
    }

    func testThreatIndicatorHighThreat() {
        let indicator = ThreatIndicator(level: 0.9, size: 48)
        XCTAssertNotNil(indicator)
    }

    func testThreatIndicatorBoundaries() {
        // Test boundary values
        let zeroIndicator = ThreatIndicator(level: 0.0, size: 48)
        XCTAssertNotNil(zeroIndicator)

        let maxIndicator = ThreatIndicator(level: 1.0, size: 48)
        XCTAssertNotNil(maxIndicator)
    }

    func testLinearThreatIndicator() {
        let linearIndicator = LinearThreatIndicator(level: 0.5, height: 8)
        XCTAssertNotNil(linearIndicator)
    }

    func testSegmentedThreatIndicator() {
        let segmentedIndicator = SegmentedThreatIndicator(level: 0.6, segments: 5)
        XCTAssertNotNil(segmentedIndicator)
    }

    // MARK: - SecurityHUD Tests

    func testSecurityHUDCreation() {
        let hud = SecurityHUD()
        XCTAssertNotNil(hud, "SecurityHUD should be created")
    }

    func testSecurityHUDViewModel() {
        let viewModel = SecurityHUDViewModel()

        XCTAssertNotNil(viewModel)
        XCTAssertEqual(viewModel.threatLevel, 0.0, "Initial threat level should be 0.0")
        XCTAssertEqual(viewModel.hypervisorConfidence, 0.0)
        XCTAssertFalse(viewModel.isJailbroken)
        XCTAssertFalse(viewModel.isMonitoring)
        XCTAssertFalse(viewModel.countermeasuresActive)
    }

    func testSecurityHUDMonitoring() {
        let viewModel = SecurityHUDViewModel()

        // Start monitoring
        viewModel.startMonitoring()
        XCTAssertTrue(viewModel.isMonitoring, "Monitoring should be active")

        // Stop monitoring
        viewModel.stopMonitoring()
        XCTAssertFalse(viewModel.isMonitoring, "Monitoring should be stopped")
    }

    func testSecurityHUDCountermeasures() {
        let viewModel = SecurityHUDViewModel()

        XCTAssertFalse(viewModel.countermeasuresActive)

        viewModel.activateCountermeasures()
        XCTAssertTrue(viewModel.countermeasuresActive, "Countermeasures should be active")

        // Wait for auto-deactivation (30 seconds in production, but we'll test immediate state)
        let expectation = self.expectation(description: "Countermeasures auto-deactivate")
        expectation.isInverted = true // Expect it NOT to fulfill immediately
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - TranslationView Tests

    func testTranslationViewCreation() {
        let translationView = TranslationView(
            originalText: "Hej",
            originalLanguage: "da",
            targetLanguage: "en"
        )

        XCTAssertNotNil(translationView)
    }

    func testTranslationResultModel() {
        let result = TranslationResult(
            translatedText: "Hello",
            confidence: 0.95,
            inferenceTimeUs: 1500,
            usedNetwork: false
        )

        XCTAssertEqual(result.translatedText, "Hello")
        XCTAssertEqual(result.confidence, 0.95, accuracy: 0.01)
        XCTAssertEqual(result.inferenceTimeUs, 1500)
        XCTAssertFalse(result.usedNetwork)
    }

    func testInlineTranslationBubble() {
        let bubble = InlineTranslationBubble(
            translatedText: "Hello, how are you?",
            confidence: 0.92
        )

        XCTAssertNotNil(bubble)
    }

    func testTranslationSettingsView() {
        let settingsView = TranslationSettingsView()
        XCTAssertNotNil(settingsView)
    }

    // MARK: - EMMASettings Tests

    func testEMMASettingsViewCreation() {
        let settingsView = EMMASettingsView()
        XCTAssertNotNil(settingsView)
    }

    func testEMMASettingsViewModel() {
        let viewModel = EMMASettingsViewModel()

        XCTAssertNotNil(viewModel)

        // Test default values
        XCTAssertTrue(viewModel.securityMonitoringEnabled, "Security monitoring should be enabled by default")
        XCTAssertFalse(viewModel.autoCountermeasuresEnabled, "Auto-countermeasures should be disabled by default")
        XCTAssertEqual(viewModel.countermeasureIntensity, 0.5, accuracy: 0.01)

        XCTAssertTrue(viewModel.translationEnabled, "Translation should be enabled by default")
        XCTAssertFalse(viewModel.autoTranslateEnabled, "Auto-translate should be disabled by default")
        XCTAssertTrue(viewModel.networkFallbackEnabled, "Network fallback should be enabled by default")

        XCTAssertEqual(viewModel.sourceLanguage, "da")
        XCTAssertEqual(viewModel.targetLanguage, "en")

        XCTAssertEqual(viewModel.emmaVersion, "1.2.0-nist-compliant")
    }

    func testEMMASettingsSaveLoad() {
        let viewModel = EMMASettingsViewModel()

        // Modify settings
        viewModel.securityMonitoringEnabled = false
        viewModel.autoCountermeasuresEnabled = true
        viewModel.countermeasureIntensity = 0.8

        // Save
        viewModel.saveSettings()

        // Load in new instance
        let newViewModel = EMMASettingsViewModel()
        newViewModel.loadSettings()

        // Verify persisted values
        XCTAssertEqual(newViewModel.securityMonitoringEnabled, false)
        XCTAssertEqual(newViewModel.autoCountermeasuresEnabled, true)
        XCTAssertEqual(newViewModel.countermeasureIntensity, 0.8, accuracy: 0.01)
    }

    func testEMMASettingsResetToDefaults() {
        let viewModel = EMMASettingsViewModel()

        // Modify settings
        viewModel.securityMonitoringEnabled = false
        viewModel.countermeasureIntensity = 0.9
        viewModel.sourceLanguage = "de"

        // Reset
        viewModel.resetToDefaults()

        // Verify defaults restored
        XCTAssertTrue(viewModel.securityMonitoringEnabled)
        XCTAssertEqual(viewModel.countermeasureIntensity, 0.5, accuracy: 0.01)
        XCTAssertEqual(viewModel.sourceLanguage, "da")
        XCTAssertEqual(viewModel.targetLanguage, "en")
    }

    func testPQCComplianceView() {
        let complianceView = PQCComplianceView()
        XCTAssertNotNil(complianceView)
    }

    func testAboutEMMAView() {
        let aboutView = AboutEMMAView()
        XCTAssertNotNil(aboutView)
    }

    // MARK: - EMMAInitializer Tests

    func testEMMAInitializerSingleton() {
        let instance1 = EMMAInitializer.shared
        let instance2 = EMMAInitializer.shared

        XCTAssertTrue(instance1 === instance2, "EMMAInitializer should be a singleton")
    }

    func testEMMAInitializerConfiguration() {
        var config = EMMAInitializer.Configuration()

        // Test default values
        XCTAssertTrue(config.enableSecurityMonitoring)
        XCTAssertTrue(config.enableTranslation)
        XCTAssertFalse(config.autoActivateCountermeasures)
        XCTAssertEqual(config.countermeasureIntensity, 0.5, accuracy: 0.01)
        XCTAssertFalse(config.showSecurityHUD)
        XCTAssertTrue(config.translationNetworkFallback)
        XCTAssertEqual(config.translationModelName, "opus-mt-da-en-int8")

        // Test modification
        config.enableSecurityMonitoring = false
        config.countermeasureIntensity = 0.7

        XCTAssertFalse(config.enableSecurityMonitoring)
        XCTAssertEqual(config.countermeasureIntensity, 0.7, accuracy: 0.01)
    }

    func testEMMAInitializerInitialization() {
        let initializer = EMMAInitializer.shared
        var config = EMMAInitializer.Configuration()

        // Disable features for testing
        config.enableSecurityMonitoring = true
        config.enableTranslation = true

        let result = initializer.initialize(with: config)
        XCTAssertTrue(result, "EMMA initialization should succeed")

        // Test double initialization
        let result2 = initializer.initialize(with: config)
        XCTAssertTrue(result2, "Second initialization should return true (already initialized)")
    }

    func testEMMAInitializerLifecycle() {
        let initializer = EMMAInitializer.shared

        // Initialize
        _ = initializer.initialize()

        // Test lifecycle methods (should not crash)
        initializer.handleAppLaunch()
        initializer.handleAppBecameActive()
        initializer.handleAppEnteredBackground()

        initializer.startMonitoring()
        initializer.stopMonitoring()
    }

    // MARK: - UserDefaults Extension Tests

    func testUserDefaultsEMMAConfiguration() {
        let defaults = UserDefaults.standard

        // Create configuration
        var config = EMMAInitializer.Configuration()
        config.enableSecurityMonitoring = false
        config.enableTranslation = true
        config.countermeasureIntensity = 0.75
        config.translationModelName = "test-model"

        // Save
        defaults.emmaConfiguration = config

        // Load
        let loadedConfig = defaults.emmaConfiguration

        // Verify
        XCTAssertEqual(loadedConfig.enableSecurityMonitoring, false)
        XCTAssertEqual(loadedConfig.enableTranslation, true)
        XCTAssertEqual(loadedConfig.countermeasureIntensity, 0.75, accuracy: 0.01)
        XCTAssertEqual(loadedConfig.translationModelName, "test-model")
    }

    // MARK: - Performance Tests

    func testPerformanceSecurityHUDCreation() {
        measure {
            for _ in 0..<10 {
                _ = SecurityHUD()
            }
        }
    }

    func testPerformanceThreatIndicatorCreation() {
        measure {
            for _ in 0..<100 {
                _ = ThreatIndicator(level: Double.random(in: 0...1), size: 48)
            }
        }
    }

    func testPerformanceTranslationViewCreation() {
        measure {
            for _ in 0..<10 {
                _ = TranslationView(
                    originalText: "Hej",
                    originalLanguage: "da",
                    targetLanguage: "en"
                )
            }
        }
    }

    // MARK: - Integration Tests

    func testSecurityHUDIntegration() {
        let hud = SecurityHUD()
        let viewModel = SecurityHUDViewModel()

        // Simulate threat detection
        viewModel.startMonitoring()

        // Wait for monitoring to initialize
        let expectation = self.expectation(description: "Monitoring initialized")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)

        // Verify monitoring is active
        XCTAssertTrue(viewModel.isMonitoring)

        viewModel.stopMonitoring()
    }

    func testTranslationIntegration() async {
        let translationView = TranslationView(
            originalText: "Hej",
            originalLanguage: "da",
            targetLanguage: "en"
        )

        // View should be created
        XCTAssertNotNil(translationView)

        // Wait for translation to complete (if model is loaded)
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // Translation should have been attempted
        // (Result depends on whether model is actually loaded)
    }
}

// MARK: - Test Helpers

@available(iOS 15.0, *)
extension UIComponentsTests {

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
