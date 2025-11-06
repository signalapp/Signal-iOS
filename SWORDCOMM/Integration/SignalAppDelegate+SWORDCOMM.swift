//
//  SignalAppDelegate+SWORDCOMM.swift
//  Signal-iOS SWORDCOMM Integration
//
//  Extension to integrate SWORDCOMM into Signal's AppDelegate
//

import Foundation
import UIKit

@available(iOS 15.0, *)
extension AppDelegate {

    /// Initialize SWORDCOMM security and translation features
    /// Call this from application(_:didFinishLaunchingWithOptions:) after basic setup
    func initializeSWORDCOMM() {
        Logger.info("[SWORDCOMM] Initializing SWORDCOMM Security & Translation")

        // Load configuration from UserDefaults
        let config = UserDefaults.standard.swordcommConfiguration

        // Initialize SWORDCOMM
        let success = SWORDCOMMInitializer.shared.initialize(with: config)

        if success {
            Logger.info("[SWORDCOMM] SWORDCOMM initialized successfully")

            // Perform initial security analysis
            SWORDCOMMInitializer.shared.handleAppLaunch()

            // Log crypto mode
            if liboqs_ml_kem_1024_enabled() && liboqs_ml_dsa_87_enabled() {
                Logger.info("[SWORDCOMM] Running in PRODUCTION CRYPTO mode")
            } else {
                Logger.warn("[SWORDCOMM] Running in STUB CRYPTO mode (NOT SECURE FOR PRODUCTION)")
                Logger.warn("[SWORDCOMM] To enable production crypto, integrate liboqs (see SWORDCOMM/LIBOQS_INTEGRATION.md)")
            }
        } else {
            Logger.error("[SWORDCOMM] SWORDCOMM initialization failed")
        }
    }

    /// Handle SWORDCOMM lifecycle when app becomes active
    /// Call this from applicationDidBecomeActive(_:)
    func emmaDidBecomeActive() {
        guard #available(iOS 15.0, *) else { return }

        SWORDCOMMInitializer.shared.handleAppBecameActive()
        Logger.debug("[SWORDCOMM] App became active - monitoring started")
    }

    /// Handle SWORDCOMM lifecycle when app enters background
    /// Call this from applicationDidEnterBackground(_:)
    func emmaDidEnterBackground() {
        guard #available(iOS 15.0, *) else { return }

        SWORDCOMMInitializer.shared.handleAppEnteredBackground()
        Logger.debug("[SWORDCOMM] App entered background - monitoring stopped")
    }

    /// Check if SWORDCOMM should be enabled
    /// Returns false if user has disabled SWORDCOMM or iOS version is too old
    var isSWORDCOMMEnabled: Bool {
        guard #available(iOS 15.0, *) else {
            Logger.warn("[SWORDCOMM] iOS 15.0+ required for SWORDCOMM")
            return false
        }

        // Check if user has disabled SWORDCOMM in settings
        let enabled = UserDefaults.standard.bool(forKey: "SWORDCOMM.SecurityMonitoring") != false // Default true

        if !enabled {
            Logger.info("[SWORDCOMM] SWORDCOMM disabled by user preference")
        }

        return enabled
    }
}

// MARK: - AppDelegate Integration Points

/*

 To integrate SWORDCOMM into Signal's AppDelegate, add the following calls:

 1. In application(_:didFinishLaunchingWithOptions:), after basic setup:

    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // ... existing Signal setup ...

        // ┌──────────────────────────────────┐
        // │ SWORDCOMM Integration - Initialize     │
        // └──────────────────────────────────┘
        if #available(iOS 15.0, *), isSWORDCOMMEnabled {
            initializeSWORDCOMM()
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
        // │ SWORDCOMM Integration - Became Active │
        // └──────────────────────────────────┘
        if #available(iOS 15.0, *), isSWORDCOMMEnabled {
            emmaDidBecomeActive()
        }

        appReadiness.runNowOrWhenAppDidBecomeReadySync { self.handleActivation() }
        // ... existing code ...
    }


 3. In applicationDidEnterBackground(_:):

    func applicationDidEnterBackground(_ application: UIApplication) {
        Logger.info("")

        // ┌──────────────────────────────────┐
        // │ SWORDCOMM Integration - Enter Background │
        // └──────────────────────────────────┘
        if #available(iOS 15.0, *), isSWORDCOMMEnabled {
            emmaDidEnterBackground()
        }

        if shouldKillAppWhenBackgrounded {
            Logger.flush()
            exit(0)
        }
    }

 */
