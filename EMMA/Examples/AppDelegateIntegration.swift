//
//  AppDelegateIntegration.swift
//  Example: How to integrate EMMA into Signal's AppDelegate
//
//  This file shows concrete examples of EMMA integration into Signal-iOS
//  AppDelegate. Copy and adapt these snippets into your actual AppDelegate.swift
//

import Foundation
import SignalServiceKit
import UIKit

// MARK: - Example 1: Complete AppDelegate.swift with EMMA

/*

File: Signal/AppLaunch/AppDelegate.swift

Add these 3 integration calls to your existing AppDelegate:

*/

class AppDelegate: UIResponder, UIApplicationDelegate {

    // ... existing Signal properties ...

    // ┌──────────────────────────────────┐
    // │ INTEGRATION POINT 1              │
    // │ In: didFinishLaunchingWithOptions│
    // │ When: App launches               │
    // └──────────────────────────────────┘
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // ... existing Signal initialization code ...

        Logger.info("Application started.")

        // ┌──────────────────────────────────┐
        // │ EMMA Integration                  │
        // └──────────────────────────────────┘
        if #available(iOS 15.0, *), isEMMAEnabled {
            initializeEMMA()
        }

        return true
    }

    // ┌──────────────────────────────────┐
    // │ INTEGRATION POINT 2              │
    // │ In: applicationDidBecomeActive   │
    // │ When: App becomes active         │
    // └──────────────────────────────────┘
    func applicationDidBecomeActive(_ application: UIApplication) {

        // ... existing Signal code ...

        // ┌──────────────────────────────────┐
        // │ EMMA Integration                  │
        // └──────────────────────────────────┘
        if #available(iOS 15.0, *), isEMMAEnabled {
            emmaDidBecomeActive()
        }
    }

    // ┌──────────────────────────────────┐
    // │ INTEGRATION POINT 3              │
    // │ In: applicationDidEnterBackground│
    // │ When: App goes to background     │
    // └──────────────────────────────────┘
    func applicationDidEnterBackground(_ application: UIApplication) {

        // ... existing Signal code ...

        // ┌──────────────────────────────────┐
        // │ EMMA Integration                  │
        // └──────────────────────────────────┘
        if #available(iOS 15.0, *), isEMMAEnabled {
            emmaDidEnterBackground()
        }
    }
}


// MARK: - Example 2: Minimal Integration (Just 3 Lines)

/*

If you want the absolute minimal integration, add just these 3 lines:

1. In didFinishLaunchingWithOptions (before return true):
   if #available(iOS 15.0, *), isEMMAEnabled { initializeEMMA() }

2. In applicationDidBecomeActive:
   if #available(iOS 15.0, *), isEMMAEnabled { emmaDidBecomeActive() }

3. In applicationDidEnterBackground:
   if #available(iOS 15.0, *), isEMMAEnabled { emmaDidEnterBackground() }

*/


// MARK: - Example 3: With Detailed Logging

class AppDelegateWithLogging: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Existing Signal initialization...
        Logger.info("Application started.")

        // EMMA with detailed logging
        if #available(iOS 15.0, *) {
            if isEMMAEnabled {
                Logger.info("[EMMA] EMMA is enabled in settings")
                initializeEMMA()

                // Log crypto mode
                if liboqs_ml_kem_1024_enabled() && liboqs_ml_dsa_87_enabled() {
                    Logger.info("[EMMA] ✓ Production cryptography enabled (ML-KEM-1024 + ML-DSA-87)")
                } else {
                    Logger.warn("[EMMA] ⚠️ Running in STUB mode (development only)")
                }

                // Log translation status
                let translationEnabled = UserDefaults.standard.bool(forKey: "EMMA.AutoTranslate")
                if translationEnabled {
                    Logger.info("[EMMA] ✓ Auto-translation enabled")
                } else {
                    Logger.info("[EMMA] Auto-translation disabled")
                }
            } else {
                Logger.info("[EMMA] EMMA is disabled in settings")
            }
        } else {
            Logger.info("[EMMA] EMMA requires iOS 15.0+")
        }

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Logger.info("[EMMA] App became active")

        if #available(iOS 15.0, *), isEMMAEnabled {
            emmaDidBecomeActive()

            // Optional: Log current threat level
            let manager = SecurityManager.shared
            if let analysis = manager.analyzeThreat() {
                Logger.debug("[EMMA] Current threat level: \(analysis.threatLevel)")
            }
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Logger.info("[EMMA] App entered background")

        if #available(iOS 15.0, *), isEMMAEnabled {
            emmaDidEnterBackground()
        }
    }
}


// MARK: - Example 4: With Error Handling

class AppDelegateWithErrorHandling: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Existing Signal initialization...
        Logger.info("Application started.")

        // EMMA with error handling
        if #available(iOS 15.0, *), isEMMAEnabled {
            do {
                initializeEMMA()
                Logger.info("[EMMA] Initialized successfully")
            } catch {
                Logger.error("[EMMA] Failed to initialize: \(error)")

                // Optional: Disable EMMA on error
                UserDefaults.standard.set(false, forKey: "EMMA.SecurityMonitoring")

                // Optional: Show alert to user
                let alert = UIAlertController(
                    title: "EMMA Initialization Failed",
                    message: "Security features have been disabled.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))

                // Show alert when window is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.window?.rootViewController?.present(alert, animated: true)
                }
            }
        }

        return true
    }
}


// MARK: - Example 5: Conditional Integration Based on Build Configuration

#if DEBUG
    let EMMA_ENABLED_BY_DEFAULT = true
#else
    let EMMA_ENABLED_BY_DEFAULT = false
#endif

class AppDelegateConditional: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Existing Signal initialization...
        Logger.info("Application started.")

        // Only enable EMMA in certain builds
        if #available(iOS 15.0, *) {
            #if EMMA_BUILD || DEBUG
                if isEMMAEnabled {
                    initializeEMMA()
                    Logger.info("[EMMA] Initialized (build: \(EMMA_BUILD ? "EMMA" : "DEBUG"))")
                }
            #else
                Logger.info("[EMMA] Not available in this build configuration")
            #endif
        }

        return true
    }
}


// MARK: - Example 6: With Feature Flags

class AppDelegateWithFeatureFlags: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Existing Signal initialization...
        Logger.info("Application started.")

        // Check remote feature flag (if you have a feature flag system)
        if #available(iOS 15.0, *) {
            // Example: Check remote config
            let emmaEnabledRemotely = RemoteConfig.shared.isEMMAEnabled()

            if emmaEnabledRemotely && isEMMAEnabled {
                initializeEMMA()
                Logger.info("[EMMA] Initialized (enabled remotely)")
            } else if !emmaEnabledRemotely {
                Logger.info("[EMMA] Disabled by remote config")
            }
        }

        return true
    }
}


// MARK: - Integration Checklist

/*

Before integrating EMMA into AppDelegate:

☐ 1. Add EMMA frameworks to project
     - EMMASecurityKit.framework
     - EMMATranslationKit.framework

☐ 2. Run `pod install` to install EMMA pods

☐ 3. Add EMMA extension files to Signal target:
     - SignalAppDelegate+EMMA.swift
     - SignalSettingsViewController+EMMA.swift
     - SignalConversationViewController+EMMA.swift (optional)
     - SignalMessageTranslation+EMMA.swift (optional)

☐ 4. Update Objective-C Bridging Header (if needed):
     - Add: #import "liboqs_wrapper.h"

☐ 5. Add EMMA initialization to AppDelegate:
     - initializeEMMA() in didFinishLaunchingWithOptions
     - emmaDidBecomeActive() in applicationDidBecomeActive
     - emmaDidEnterBackground() in applicationDidEnterBackground

☐ 6. Build and test:
     - Clean build folder (⇧⌘K)
     - Build (⌘B)
     - Run on simulator (⌘R)
     - Check console for: "[EMMA] Initialized successfully"

☐ 7. Enable production crypto (optional):
     - Add HAVE_LIBOQS=1 to preprocessor macros
     - Add liboqs.xcframework to project
     - Verify console shows: "PRODUCTION CRYPTO mode"

☐ 8. Test features:
     - Open Settings → EMMA
     - Toggle security monitoring
     - Toggle auto-translation
     - Verify SecurityHUD appears in conversations

*/


// MARK: - Troubleshooting

/*

Common issues and solutions:

1. "Module 'EMMASecurityKit' not found"
   Solution: Run `pod install` and open Signal.xcworkspace (not .xcodeproj)

2. "Undefined symbol: _initializeEMMA"
   Solution: Ensure SignalAppDelegate+EMMA.swift is added to Signal target

3. "EMMA initialized successfully" but features don't work
   Solution: Check UserDefaults settings are enabled:
   - EMMA.SecurityMonitoring
   - EMMA.AutoTranslate
   - EMMA.ShowSecurityHUD

4. Console shows "STUB CRYPTO mode"
   Solution: This is expected without liboqs. To enable production crypto:
   - Run: ./EMMA/Scripts/build_liboqs.sh --minimal
   - Add liboqs.xcframework to project
   - Add HAVE_LIBOQS=1 to preprocessor macros

5. App crashes on launch
   Solution: Check that all EMMA extensions have @available(iOS 15.0, *) checks

6. Translation doesn't work
   Solution:
   - Verify CoreML model is in project
   - Check model is added to Signal target
   - Ensure EMMA.AutoTranslate is enabled in UserDefaults

*/
