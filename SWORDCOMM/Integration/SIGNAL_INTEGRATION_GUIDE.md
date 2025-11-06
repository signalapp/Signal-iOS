# SWORDCOMM Signal-iOS Integration Guide

**Phase 3B - UI Integration**
**Date**: 2025-11-06

---

## 📦 Integration Steps

### Step 1: Add SWORDCOMM to Podfile

Already done in Phase 2. Verify `Podfile` contains:

```ruby
pod 'SWORDCOMMSecurityKit', :path => './SWORDCOMM'
pod 'SWORDCOMMTranslationKit', :path => './SWORDCOMM'
```

Run `pod install` if not already done.

### Step 2: Add SWORDCOMM Bridging Header

**Option A**: Use SWORDCOMM's bridging header

In Xcode Build Settings for **Signal** target:
- Set **Objective-C Bridging Header** to: `$(PROJECT_DIR)/SWORDCOMM/SWORDCOMM-Bridging-Header.h`

**Option B**: Add to existing Signal bridging header

If Signal already has a bridging header, add these imports:

```objc
// SWORDCOMM Security & Translation
#import "EMSecurityKit.h"
#import "EMTranslationKit.h"
```

### Step 3: Integrate with AppDelegate

**File**: `Signal/AppLaunch/AppDelegate.swift`

#### 3.1: Import SWORDCOMM

At the top of `AppDelegate.swift`:

```swift
// Existing imports...
import UIKit
import SignalServiceKit
// ... etc

// SWORDCOMM Integration
// (No explicit import needed if bridging header is configured)
```

#### 3.2: Initialize SWORDCOMM in `application(_:didFinishLaunchingWithOptions:)`

Find the `application(_:didFinishLaunchingWithOptions:)` method and add SWORDCOMM initialization:

```swift
func application(_ application: UIApplication,
                didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    // Existing Signal initialization code...

    // ┌─────────────────────────────────────────┐
    // │ SWORDCOMM Integration - Initialize           │
    // └─────────────────────────────────────────┘
    if #available(iOS 15.0, *) {
        // Load configuration from user defaults
        let config = UserDefaults.standard.swordcommConfiguration

        // Initialize SWORDCOMM
        if SWORDCOMMInitializer.shared.initialize(with: config) {
            Logger.info("[SWORDCOMM] SWORDCOMM initialized successfully")

            // Perform initial security analysis
            SWORDCOMMInitializer.shared.handleAppLaunch()
        } else {
            Logger.warn("[SWORDCOMM] SWORDCOMM initialization failed")
        }
    }

    // Continue with existing Signal code...

    return true
}
```

#### 3.3: Add Lifecycle Hooks

In `applicationDidBecomeActive(_:)`:

```swift
func applicationDidBecomeActive(_ application: UIApplication) {
    AssertIsOnMainThread()
    if CurrentAppContext().isRunningTests {
        return
    }

    Logger.warn("")

    if didAppLaunchFail {
        return
    }

    // ┌─────────────────────────────────────────┐
    // │ SWORDCOMM Integration - Became Active        │
    // └─────────────────────────────────────────┘
    if #available(iOS 15.0, *) {
        SWORDCOMMInitializer.shared.handleAppBecameActive()
    }

    appReadiness.runNowOrWhenAppDidBecomeReadySync { self.handleActivation() }

    // ... existing code
}
```

In `applicationDidEnterBackground(_:)`:

```swift
func applicationDidEnterBackground(_ application: UIApplication) {
    Logger.warn("")

    // ┌─────────────────────────────────────────┐
    // │ SWORDCOMM Integration - Entered Background   │
    // └─────────────────────────────────────────┘
    if #available(iOS 15.0, *) {
        SWORDCOMMInitializer.shared.handleAppEnteredBackground()
    }

    // ... existing Signal code
}
```

### Step 4: Add SWORDCOMM Settings to Signal Settings

**File**: Find Signal's settings view controller (likely `SignalUI/Settings/AppSettingsViewController.swift` or similar)

Add SWORDCOMM settings row:

```swift
// In the settings table view configuration

// ┌─────────────────────────────────────────┐
// │ SWORDCOMM Settings Section                   │
// └─────────────────────────────────────────┘
if #available(iOS 15.0, *) {
    let emmaSection = Section(
        header: "SWORDCOMM Security",
        items: [
            Item(
                title: "SWORDCOMM Settings",
                accessoryView: {
                    let label = UILabel()
                    label.text = "⚡️"
                    label.font = .systemFont(ofSize: 20)
                    return label
                }(),
                accessibilityIdentifier: "emma_settings",
                actionBlock: { [weak self] in
                    self?.showSWORDCOMMSettings()
                }
            )
        ]
    )

    contents.add(section: emmaSection)
}

// Add method to show SWORDCOMM settings:
@available(iOS 15.0, *)
private func showSWORDCOMMSettings() {
    let emmaSettings = UIHostingController(rootView: SWORDCOMMSettingsView())
    navigationController?.pushViewController(emmaSettings, animated: true)
}
```

### Step 5: Add Security HUD Overlay (Optional)

**File**: Create or modify the main conversation view controller

Add SecurityHUD as an overlay when enabled:

```swift
import SwiftUI

class ConversationViewController: UIViewController {

    private var securityHUDHostingController: UIHostingController<SecurityHUD>?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Existing setup...

        // ┌─────────────────────────────────────────┐
        // │ SWORDCOMM Security HUD Integration           │
        // └─────────────────────────────────────────┘
        if #available(iOS 15.0, *) {
            setupSecurityHUD()
        }
    }

    @available(iOS 15.0, *)
    private func setupSecurityHUD() {
        // Check if security HUD is enabled in settings
        guard UserDefaults.standard.bool(forKey: "SWORDCOMM.ShowSecurityHUD") else {
            return
        }

        let securityHUD = SecurityHUD()
        let hostingController = UIHostingController(rootView: securityHUD)

        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])

        securityHUDHostingController = hostingController
    }
}
```

### Step 6: Add Translation to Message Cells (Optional)

**File**: Find the message cell view (e.g., `CVTextLabel`, `MessageCell`, or similar)

Add translation capability to message cells:

```swift
class MessageCell: UITableViewCell {

    private var translationView: UIHostingController<InlineTranslationBubble>?

    func configure(with message: TSMessage) {
        // Existing configuration...

        // ┌─────────────────────────────────────────┐
        // │ SWORDCOMM Translation Integration            │
        // └─────────────────────────────────────────┘
        if #available(iOS 15.0, *) {
            configureTranslation(for: message)
        }
    }

    @available(iOS 15.0, *)
    private func configureTranslation(for message: TSMessage) {
        // Check if auto-translate is enabled
        guard UserDefaults.standard.bool(forKey: "SWORDCOMM.AutoTranslate") else {
            translationView?.view.removeFromSuperview()
            translationView = nil
            return
        }

        // Detect if message needs translation (e.g., Danish text)
        guard shouldTranslate(message: message) else {
            return
        }

        // Perform translation
        Task {
            if let translation = await translateMessage(message) {
                await MainActor.run {
                    showTranslation(translation)
                }
            }
        }
    }

    private func shouldTranslate(message: TSMessage) -> Bool {
        // Implement language detection logic
        // For now, simple heuristic based on user settings
        return true // Placeholder
    }

    private func translateMessage(_ message: TSMessage) async -> (text: String, confidence: Double)? {
        let engine = EMTranslationEngine.shared()

        guard let result = engine.translateText(
            message.body ?? "",
            fromLanguage: "da",
            toLanguage: "en"
        ) else {
            return nil
        }

        return (result.translatedText, result.confidence)
    }

    private func showTranslation(_ translation: (text: String, confidence: Double)) {
        let bubble = InlineTranslationBubble(
            translatedText: translation.text,
            confidence: translation.confidence
        )

        let hostingController = UIHostingController(rootView: bubble)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 4),
            hostingController.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            hostingController.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])

        translationView = hostingController
    }
}
```

---

## 🧪 Testing the Integration

### Test Security Features

1. **Launch app and check logs**:
   ```
   [SWORDCOMM] Initializing SWORDCOMM Security & Translation
   [SWORDCOMM] Security initialized
   [SWORDCOMM] SWORDCOMM initialized successfully
   [SWORDCOMM] Initial threat analysis:
   [SWORDCOMM]   Threat level: 0.XX
   ```

2. **Navigate to Settings → SWORDCOMM Settings**
   - Verify SWORDCOMM settings panel appears
   - Toggle security monitoring on/off
   - Check threat indicator updates

3. **Test Security HUD** (if enabled):
   - Enable "Show Security HUD" in settings
   - Verify HUD appears at top of conversation view
   - Tap to expand and view detailed metrics

### Test Translation Features

1. **Check model loading**:
   - Go to SWORDCOMM Settings → Translation section
   - Verify "On-device model" status

2. **Test translation**:
   - Send a Danish message to yourself
   - If auto-translate is enabled, translation should appear
   - Tap to expand/collapse translation

### Test PQC Compliance

1. **View compliance status**:
   - SWORDCOMM Settings → Post-Quantum Cryptography
   - Verify all algorithms show "Compliant"
   - Check ML-KEM-1024, ML-DSA-87, AES-256-GCM

---

## 🔧 Build Configuration

### Required Build Settings

Ensure the following are set in Xcode for the **Signal** target:

| Setting | Value |
|---------|-------|
| **Objective-C Bridging Header** | `$(PROJECT_DIR)/SWORDCOMM/SWORDCOMM-Bridging-Header.h` |
| **Swift Compiler - Language** | Swift 5 |
| **C++ Language Dialect** | C++17 (`-std=c++17`) |
| **C++ Standard Library** | libc++ (automatic) |
| **Enable Bitcode** | No |

### Framework Search Paths

Should be automatically configured by CocoaPods:
```
$(inherited)
${PODS_CONFIGURATION_BUILD_DIR}/SWORDCOMMSecurityKit
${PODS_CONFIGURATION_BUILD_DIR}/SWORDCOMMTranslationKit
```

---

## 📊 Monitoring SWORDCOMM

### Notifications

SWORDCOMM posts notifications for security events:

```swift
// Listen for threat level changes
NotificationCenter.default.addObserver(
    forName: .swordcommThreatLevelChanged,
    object: nil,
    queue: .main
) { notification in
    if let analysis = notification.userInfo?["analysis"] as? ThreatAnalysis {
        print("Threat level: \(analysis.threatLevel)")
    }
}

// Listen for high threat detection
NotificationCenter.default.addObserver(
    forName: .swordcommHighThreatDetected,
    object: nil,
    queue: .main
) { notification in
    if let analysis = notification.userInfo?["analysis"] as? ThreatAnalysis {
        print("HIGH THREAT! Level: \(analysis.threatLevel)")
    }
}
```

### Manual Security Checks

```swift
// Get current threat analysis
if let analysis = SecurityManager.shared.analyzeThreat() {
    print("Threat level: \(analysis.threatLevel)")
    print("Hypervisor confidence: \(analysis.hypervisorConfidence)")
    print("Category: \(analysis.category)")
}

// Manually activate countermeasures
SecurityManager.shared.activateCountermeasures(intensity: 0.8)

// Execute code with timing obfuscation
SecurityManager.shared.executeWithObfuscation(chaosPercent: 0.5) {
    // Sensitive operation here
    sendEncryptedMessage()
}
```

---

## 🐛 Troubleshooting

### Issue: "Module 'SWORDCOMMSecurityKit' not found"

**Solution**:
1. Run `pod install`
2. Open `.xcworkspace` (not `.xcodeproj`)
3. Clean build folder: **Product → Clean Build Folder**
4. Rebuild

### Issue: "Use of undeclared identifier 'SecurityManager'"

**Solution**:
1. Verify bridging header is configured correctly
2. Ensure `#import "EMSecurityKit.h"` is in bridging header
3. Clean and rebuild

### Issue: Security HUD not appearing

**Solution**:
1. Check `UserDefaults.standard.bool(forKey: "SWORDCOMM.ShowSecurityHUD")` is `true`
2. Verify iOS version is 15.0+
3. Check console for errors

### Issue: Translation not working

**Solution**:
1. Verify translation model is bundled or network fallback is enabled
2. Check `EMTranslationEngine.shared().isModelLoaded()`
3. Enable network fallback in SWORDCOMM settings

---

## 📝 Next Steps

### Immediate
- [ ] Complete integration in `AppDelegate.swift`
- [ ] Add SWORDCOMM settings to Signal settings menu
- [ ] Test on physical device (security features limited in Simulator)

### Short-term
- [ ] Integrate SecurityHUD into conversation view
- [ ] Add translation to message cells
- [ ] Test cross-platform (iOS ↔ Android) encrypted communication

### Long-term
- [ ] Implement production liboqs for ML-KEM/ML-DSA
- [ ] Convert OPUS-MT model to CoreML
- [ ] Add mDNS for network translation discovery
- [ ] Security audit and penetration testing

---

## 📚 References

- **SWORDCOMM Documentation**: `SWORDCOMM/NIST_PQC_COMPLIANCE.md`
- **Phase 2 Guide**: `SWORDCOMM/PHASE2_INTEGRATION_GUIDE.md`
- **CocoaPods Specs**: `SWORDCOMM/*.podspec`
- **Unit Tests**: `SWORDCOMM/Tests/`

---

**Document Version**: 1.0.0
**Last Updated**: 2025-11-06
**Phase**: 3B - UI Integration
