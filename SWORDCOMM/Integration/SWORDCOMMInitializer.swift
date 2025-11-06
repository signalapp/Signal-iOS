//
//  SWORDCOMMInitializer.swift
//  SWORDCOMM Integration Helper
//
//  Centralized initialization for SWORDCOMM security and translation features
//

import Foundation
import UIKit

/// SWORDCOMM initialization and lifecycle manager
@available(iOS 15.0, *)
public final class SWORDCOMMInitializer {

    // MARK: - Singleton

    public static let shared = SWORDCOMMInitializer()

    private init() {}

    // MARK: - State

    private var isInitialized: Bool = false
    private var securityManager: SecurityManager?
    private var translationEngine: EMTranslationEngine?

    // MARK: - Configuration

    public struct Configuration {
        /// Enable security monitoring on startup
        public var enableSecurityMonitoring: Bool = true

        /// Enable translation features on startup
        public var enableTranslation: Bool = true

        /// Automatically activate countermeasures when threat level is high
        public var autoActivateCountermeasures: Bool = false

        /// Countermeasure intensity (0.0 to 1.0)
        public var countermeasureIntensity: Double = 0.5

        /// Show security HUD overlay
        public var showSecurityHUD: Bool = false

        /// Enable network fallback for translation
        public var translationNetworkFallback: Bool = true

        /// Translation model name (if bundled)
        public var translationModelName: String? = "opus-mt-da-en-int8"

        public init() {}
    }

    // MARK: - Public API

    /// Initialize SWORDCOMM with configuration
    /// Call this from AppDelegate.application(_:didFinishLaunchingWithOptions:)
    public func initialize(with configuration: Configuration = Configuration()) -> Bool {
        guard !isInitialized else {
            NSLog("[SWORDCOMM] Already initialized")
            return true
        }

        NSLog("[SWORDCOMM] Initializing SWORDCOMM Security & Translation")

        // Initialize security
        if configuration.enableSecurityMonitoring {
            if !initializeSecurity(configuration: configuration) {
                NSLog("[SWORDCOMM] Security initialization failed")
                return false
            }
        }

        // Initialize translation
        if configuration.enableTranslation {
            initializeTranslation(configuration: configuration)
        }

        isInitialized = true
        NSLog("[SWORDCOMM] SWORDCOMM initialized successfully")

        return true
    }

    /// Start monitoring (call when app becomes active)
    public func startMonitoring() {
        guard isInitialized else {
            NSLog("[SWORDCOMM] Not initialized, call initialize() first")
            return
        }

        securityManager?.startMonitoring()
        NSLog("[SWORDCOMM] Monitoring started")
    }

    /// Stop monitoring (call when app enters background)
    public func stopMonitoring() {
        securityManager?.stopMonitoring()
        NSLog("[SWORDCOMM] Monitoring stopped")
    }

    /// Handle app launch
    /// Call this from AppDelegate.application(_:didFinishLaunchingWithOptions:)
    public func handleAppLaunch() {
        guard isInitialized else { return }

        // Perform initial threat analysis
        if let analysis = securityManager?.analyzeThreat() {
            NSLog("[SWORDCOMM] Initial threat analysis:")
            NSLog("[SWORDCOMM]   Threat level: \(String(format: "%.2f", analysis.threatLevel))")
            NSLog("[SWORDCOMM]   Hypervisor confidence: \(String(format: "%.2f", analysis.hypervisorConfidence))")
            NSLog("[SWORDCOMM]   Category: \(analysis.category)")

            if analysis.threatLevel > 0.7 {
                NSLog("[SWORDCOMM] WARNING: High threat level detected on launch!")
            }
        }
    }

    /// Handle app becoming active
    /// Call this from AppDelegate.applicationDidBecomeActive(_:)
    public func handleAppBecameActive() {
        startMonitoring()
    }

    /// Handle app entering background
    /// Call this from AppDelegate.applicationDidEnterBackground(_:)
    public func handleAppEnteredBackground() {
        stopMonitoring()
    }

    // MARK: - Private Helpers

    private func initializeSecurity(configuration: Configuration) -> Bool {
        securityManager = SecurityManager.shared

        guard let manager = securityManager else {
            NSLog("[SWORDCOMM] Failed to get SecurityManager instance")
            return false
        }

        // Initialize
        guard manager.initialize() else {
            NSLog("[SWORDCOMM] SecurityManager initialization failed")
            return false
        }

        // Set up threat callbacks
        manager.onThreatLevelChanged = { analysis in
            self.handleThreatLevelChanged(analysis)
        }

        manager.onHighThreatDetected = { analysis in
            self.handleHighThreatDetected(analysis, configuration: configuration)
        }

        NSLog("[SWORDCOMM] Security initialized")
        return true
    }

    private func initializeTranslation(configuration: Configuration) {
        translationEngine = EMTranslationEngine.shared()

        guard let engine = translationEngine else {
            NSLog("[SWORDCOMM] Failed to get TranslationEngine instance")
            return
        }

        // Try to load model from bundle
        if let modelName = configuration.translationModelName {
            let success = engine.initialize(fromBundle: modelName)

            if success {
                NSLog("[SWORDCOMM] Translation model '\(modelName)' loaded successfully")
            } else {
                NSLog("[SWORDCOMM] Translation model '\(modelName)' not found")

                if configuration.translationNetworkFallback {
                    engine.networkFallbackEnabled = true
                    NSLog("[SWORDCOMM] Network fallback enabled for translation")
                }
            }
        }
    }

    private func handleThreatLevelChanged(_ analysis: ThreatAnalysis) {
        NSLog("[SWORDCOMM] Threat level changed: \(String(format: "%.2f", analysis.threatLevel))")

        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .swordcommThreatLevelChanged,
            object: nil,
            userInfo: ["analysis": analysis]
        )
    }

    private func handleHighThreatDetected(_ analysis: ThreatAnalysis, configuration: Configuration) {
        NSLog("[SWORDCOMM] HIGH THREAT DETECTED!")
        NSLog("[SWORDCOMM]   Threat level: \(String(format: "%.2f", analysis.threatLevel))")
        NSLog("[SWORDCOMM]   Category: \(analysis.category)")
        NSLog("[SWORDCOMM]   Hypervisor confidence: \(String(format: "%.2f", analysis.hypervisorConfidence))")

        // Auto-activate countermeasures if enabled
        if configuration.autoActivateCountermeasures {
            securityManager?.activateCountermeasures(intensity: configuration.countermeasureIntensity)
            NSLog("[SWORDCOMM] Countermeasures activated (intensity: \(configuration.countermeasureIntensity))")
        }

        // Post notification for UI
        NotificationCenter.default.post(
            name: .swordcommHighThreatDetected,
            object: nil,
            userInfo: ["analysis": analysis]
        )

        // Show user alert if app is active
        if UIApplication.shared.applicationState == .active {
            showHighThreatAlert(analysis: analysis)
        }
    }

    private func showHighThreatAlert(analysis: ThreatAnalysis) {
        DispatchQueue.main.async {
            guard let topViewController = UIApplication.shared.topViewController() else {
                return
            }

            let alert = UIAlertController(
                title: "Security Alert",
                message: "SWORDCOMM has detected a security threat. Threat level: \(Int(analysis.threatLevel * 100))%",
                preferredStyle: .alert
            )

            alert.addAction(UIAlertAction(title: "OK", style: .default))

            alert.addAction(UIAlertAction(title: "Activate Countermeasures", style: .destructive) { _ in
                self.securityManager?.activateCountermeasures(intensity: 0.8)
            })

            topViewController.present(alert, animated: true)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    public static let emmaThreatLevelChanged = Notification.Name("SWORDCOMM.ThreatLevelChanged")
    public static let emmaHighThreatDetected = Notification.Name("SWORDCOMM.HighThreatDetected")
}

// MARK: - UIApplication Extension

extension UIApplication {
    func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let base = base ?? connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController

        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }

        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }

        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }

        return base
    }
}

// MARK: - UserDefaults Extension for SWORDCOMM Settings

extension UserDefaults {
    public var emmaConfiguration: SWORDCOMMInitializer.Configuration {
        get {
            var config = SWORDCOMMInitializer.Configuration()

            config.enableSecurityMonitoring = bool(forKey: "SWORDCOMM.SecurityMonitoring") != false
            config.enableTranslation = bool(forKey: "SWORDCOMM.Translation") != false
            config.autoActivateCountermeasures = bool(forKey: "SWORDCOMM.AutoCountermeasures")
            config.countermeasureIntensity = double(forKey: "SWORDCOMM.CountermeasureIntensity") != 0 ?
                double(forKey: "SWORDCOMM.CountermeasureIntensity") : 0.5
            config.showSecurityHUD = bool(forKey: "SWORDCOMM.ShowSecurityHUD")
            config.translationNetworkFallback = bool(forKey: "SWORDCOMM.NetworkFallback") != false

            if let modelName = string(forKey: "SWORDCOMM.TranslationModelName") {
                config.translationModelName = modelName
            }

            return config
        }
        set {
            set(newValue.enableSecurityMonitoring, forKey: "SWORDCOMM.SecurityMonitoring")
            set(newValue.enableTranslation, forKey: "SWORDCOMM.Translation")
            set(newValue.autoActivateCountermeasures, forKey: "SWORDCOMM.AutoCountermeasures")
            set(newValue.countermeasureIntensity, forKey: "SWORDCOMM.CountermeasureIntensity")
            set(newValue.showSecurityHUD, forKey: "SWORDCOMM.ShowSecurityHUD")
            set(newValue.translationNetworkFallback, forKey: "SWORDCOMM.NetworkFallback")

            if let modelName = newValue.translationModelName {
                set(modelName, forKey: "SWORDCOMM.TranslationModelName")
            }
        }
    }
}
