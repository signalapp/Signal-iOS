//
//  SignalAppDelegate+EMMA.swift
//  Signal-iOS EMMA Integration
//
//  Extension to integrate EMMA into Signal's AppDelegate
//

import Foundation
import UIKit

@available(iOS 15.0, *)
extension AppDelegate {

    /// Initialize EMMA security and translation features
    /// Call this from application(_:didFinishLaunchingWithOptions:) after basic setup
    func initializeEMMA() {
        Logger.info("[EMMA] Initializing EMMA Security & Translation")

        // Load configuration from UserDefaults
        let config = UserDefaults.standard.emmaConfiguration

        // Initialize EMMA
        let success = EMMAInitializer.shared.initialize(with: config)

        if success {
            Logger.info("[EMMA] EMMA initialized successfully")

            // Perform initial security analysis
            EMMAInitializer.shared.handleAppLaunch()

            // Log crypto mode
            if liboqs_ml_kem_1024_enabled() && liboqs_ml_dsa_87_enabled() {
                Logger.info("[EMMA] Running in PRODUCTION CRYPTO mode")
            } else {
                Logger.warn("[EMMA] Running in STUB CRYPTO mode (NOT SECURE FOR PRODUCTION)")
                Logger.warn("[EMMA] To enable production crypto, integrate liboqs (see EMMA/LIBOQS_INTEGRATION.md)")
            }
        } else {
            Logger.error("[EMMA] EMMA initialization failed")
        }
    }

    /// Handle EMMA lifecycle when app becomes active
    /// Call this from applicationDidBecomeActive(_:)
    func emmaDidBecomeActive() {
        guard #available(iOS 15.0, *) else { return }

        EMMAInitializer.shared.handleAppBecameActive()
        Logger.debug("[EMMA] App became active - monitoring started")
    }

    /// Handle EMMA lifecycle when app enters background
    /// Call this from applicationDidEnterBackground(_:)
    func emmaDidEnterBackground() {
        guard #available(iOS 15.0, *) else { return }

        EMMAInitializer.shared.handleAppEnteredBackground()
        Logger.debug("[EMMA] App entered background - monitoring stopped")
    }

    /// Check if EMMA should be enabled
    /// Returns false if user has disabled EMMA or iOS version is too old
    var isEMMAEnabled: Bool {
        guard #available(iOS 15.0, *) else {
            Logger.warn("[EMMA] iOS 15.0+ required for EMMA")
            return false
        }

        // Check if user has disabled EMMA in settings
        let enabled = UserDefaults.standard.bool(forKey: "EMMA.SecurityMonitoring") != false // Default true

        if !enabled {
            Logger.info("[EMMA] EMMA disabled by user preference")
        }

        return enabled
    }
}

// MARK: - AppDelegate Integration Points

/*

 To integrate EMMA into Signal's AppDelegate, add the following calls:

 1. In application(_:didFinishLaunchingWithOptions:), after basic setup:

    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // ... existing Signal setup ...

        // ┌──────────────────────────────────┐
        // │ EMMA Integration - Initialize     │
        // └──────────────────────────────────┘
        if #available(iOS 15.0, *), isEMMAEnabled {
            initializeEMMA()
        }

        // ... rest of Signal setup ...
        return true
    }


 2. In applicationDidBecomeActive(_:):

    func applicationDidBecomeActive(_ application: UIApplication) {
        AssertIsOnMainThread()
        if CurrentAppContext().isRunningTests {
            return
        }

        Logger.warn("")

        if didAppLaunchFail {
            return
        }

        // ┌──────────────────────────────────┐
        // │ EMMA Integration - Became Active │
        // └──────────────────────────────────┘
        if #available(iOS 15.0, *), isEMMAEnabled {
            emmaDidBecomeActive()
        }

        appReadiness.runNowOrWhenAppDidBecomeReadySync { self.handleActivation() }
        // ... existing code ...
    }


 3. In applicationDidEnterBackground(_:):

    func applicationDidEnterBackground(_ application: UIApplication) {
        Logger.info("")

        // ┌──────────────────────────────────┐
        // │ EMMA Integration - Enter Background │
        // └──────────────────────────────────┘
        if #available(iOS 15.0, *), isEMMAEnabled {
            emmaDidEnterBackground()
        }

        if shouldKillAppWhenBackgrounded {
            Logger.flush()
            exit(0)
        }
    }

 */
