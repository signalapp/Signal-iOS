//
//  SettingsIntegration.swift
//  Example: How to integrate EMMA settings into Signal's AppSettingsViewController
//
//  This file shows concrete examples of adding EMMA to Signal settings
//

import Foundation
import SignalServiceKit
import SignalUI
import SwiftUI
import UIKit

// MARK: - Example 1: Complete Settings Integration

/*

File: Signal/src/ViewControllers/AppSettings/AppSettingsViewController.swift

Add EMMA section to your settings:

*/

class AppSettingsViewController: OWSTableViewController2 {

    // ... existing Signal code ...

    override func updateTableContents(_ contents: OWSTableContents) {

        // ... existing sections ...

        // Account section
        contents.add(accountSection())

        // Privacy section
        contents.add(privacySection())

        // ┌──────────────────────────────────┐
        // │ EMMA Integration                  │
        // │ Add EMMA section to settings     │
        // └──────────────────────────────────┘
        if #available(iOS 15.0, *) {
            contents.add(emmaSettingsSection())
        }

        // Notifications section
        contents.add(notificationsSection())

        // ... rest of sections ...
    }
}


// MARK: - Example 2: Minimal EMMA Section (1 Line)

/*

Absolute minimal integration - just add this one line in updateTableContents:

if #available(iOS 15.0, *) { contents.add(emmaSettingsSection()) }

*/


// MARK: - Example 3: EMMA Section with Status Indicators

@available(iOS 15.0, *)
extension AppSettingsViewController {

    func emmaSettingsSectionWithStatus() -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = "EMMA Security & Translation"

        // Get current status
        let securityEnabled = UserDefaults.standard.bool(forKey: "EMMA.SecurityMonitoring")
        let translationEnabled = UserDefaults.standard.bool(forKey: "EMMA.AutoTranslate")
        let productionCrypto = liboqs_ml_kem_1024_enabled() && liboqs_ml_dsa_87_enabled()

        // Main EMMA settings item with status
        let statusText: String
        if securityEnabled || translationEnabled {
            statusText = "Active"
        } else {
            statusText = "Disabled"
        }

        section.add(.disclosureItem(
            icon: .settingsAdvanced,
            name: "EMMA Settings",
            accessoryText: statusText,
            accessibilityIdentifier: "emma_settings",
            actionBlock: { [weak self] in
                self?.showEMMASettings()
            }
        ))

        // Show crypto status
        let cryptoStatus = productionCrypto ? "Production" : "Development"
        section.add(.label(
            withText: "Cryptography: \(cryptoStatus)",
            accessibilityIdentifier: "emma_crypto_status"
        ))

        section.footerTitle = "EMMA provides military-grade post-quantum cryptography and on-device translation."

        return section
    }

    private func showEMMASettings() {
        let emmaSettings = UIHostingController(rootView: EMMASettingsView())
        emmaSettings.title = "EMMA"
        self.navigationController?.pushViewController(emmaSettings, animated: true)
    }
}


// MARK: - Example 4: Inline Security Toggle

@available(iOS 15.0, *)
extension AppSettingsViewController {

    func emmaSettingsSectionInline() -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = "EMMA Security & Translation"

        // Security monitoring toggle
        section.add(.switch(
            withText: "Security Monitoring",
            isOn: {
                UserDefaults.standard.bool(forKey: "EMMA.SecurityMonitoring")
            },
            target: self,
            selector: #selector(didToggleSecurityMonitoring)
        ))

        // Auto-translation toggle
        section.add(.switch(
            withText: "Auto-Translate Messages",
            isOn: {
                UserDefaults.standard.bool(forKey: "EMMA.AutoTranslate")
            },
            target: self,
            selector: #selector(didToggleAutoTranslation)
        ))

        // Advanced settings
        section.add(.disclosureItem(
            withText: "Advanced EMMA Settings",
            accessibilityIdentifier: "emma_advanced",
            actionBlock: { [weak self] in
                self?.showEMMASettings()
            }
        ))

        section.footerTitle = "Security monitoring detects side-channel attacks. Translation uses on-device AI (network fallback available)."

        return section
    }

    @objc
    private func didToggleSecurityMonitoring(_ sender: UISwitch) {
        UserDefaults.standard.set(sender.isOn, forKey: "EMMA.SecurityMonitoring")

        // Notify EMMA of settings change
        NotificationCenter.default.post(
            name: NSNotification.Name("EMMA.SettingsDidChange"),
            object: nil
        )

        if sender.isOn {
            SecurityManager.shared.startMonitoring()
            Logger.info("[EMMA] Security monitoring enabled")
        } else {
            SecurityManager.shared.stopMonitoring()
            Logger.info("[EMMA] Security monitoring disabled")
        }
    }

    @objc
    private func didToggleAutoTranslation(_ sender: UISwitch) {
        UserDefaults.standard.set(sender.isOn, forKey: "EMMA.AutoTranslate")

        // Notify EMMA of settings change
        NotificationCenter.default.post(
            name: NSNotification.Name("EMMA.SettingsDidChange"),
            object: nil
        )

        if sender.isOn {
            Logger.info("[EMMA] Auto-translation enabled (on-device primary, network fallback)")
        } else {
            Logger.info("[EMMA] Auto-translation disabled")
        }
    }
}


// MARK: - Example 5: Translation Settings with On-Device Priority

@available(iOS 15.0, *)
extension AppSettingsViewController {

    func translationSettingsSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = "Translation Settings"

        // Auto-translate toggle
        section.add(.switch(
            withText: "Auto-Translate Messages",
            isOn: {
                UserDefaults.standard.bool(forKey: "EMMA.AutoTranslate")
            },
            target: self,
            selector: #selector(didToggleAutoTranslation)
        ))

        // Translation mode
        let translationEngine = EMTranslationEngine.shared()
        let modelLoaded = translationEngine.isModelLoaded()

        let modeText = modelLoaded ? "On-Device (CoreML)" : "Network Fallback"
        section.add(.label(
            withText: "Translation Mode: \(modeText)",
            accessibilityIdentifier: "emma_translation_mode"
        ))

        // Show model download option if not loaded
        if !modelLoaded {
            section.add(.actionItem(
                withText: "Download On-Device Model",
                accessibilityIdentifier: "emma_download_model",
                actionBlock: { [weak self] in
                    self?.downloadTranslationModel()
                }
            ))
        }

        // Language preferences
        section.add(.disclosureItem(
            withText: "Language Preferences",
            accessibilityIdentifier: "emma_language_prefs",
            actionBlock: { [weak self] in
                self?.showLanguagePreferences()
            }
        ))

        section.footerTitle = "On-device translation is private and works offline. Network fallback is used only when needed."

        return section
    }

    private func downloadTranslationModel() {
        let alert = UIAlertController(
            title: "Download Translation Model",
            message: "The on-device translation model is ~78 MB. Download now?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Download", style: .default) { _ in
            // Start download
            Logger.info("[EMMA] Starting translation model download")

            // Show progress
            let progress = UIAlertController(
                title: "Downloading...",
                message: "Downloading translation model",
                preferredStyle: .alert
            )
            self.present(progress, animated: true)

            // Simulate download (in production, use URLSession)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                progress.dismiss(animated: true) {
                    let success = UIAlertController(
                        title: "Download Complete",
                        message: "On-device translation is now available",
                        preferredStyle: .alert
                    )
                    success.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(success, animated: true)
                }
            }
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        self.present(alert, animated: true)
    }

    private func showLanguagePreferences() {
        // Show language selection view
        let languageView = LanguagePreferencesView()
        let hosting = UIHostingController(rootView: languageView)
        hosting.title = "Language Preferences"
        self.navigationController?.pushViewController(hosting, animated: true)
    }
}


// MARK: - Example 6: Cryptography Status Section

@available(iOS 15.0, *)
extension AppSettingsViewController {

    func emmaCryptographySection() -> OWSTableSection {
        let section = OWSTableSection()
        section.headerTitle = "Post-Quantum Cryptography"

        // Check crypto availability
        let mlkemEnabled = liboqs_ml_kem_1024_enabled()
        let mldsaEnabled = liboqs_ml_dsa_87_enabled()
        let productionMode = mlkemEnabled && mldsaEnabled

        // Crypto status
        let statusIcon: String = productionMode ? "✓" : "⚠️"
        let statusText = productionMode ? "Production Mode" : "Development Mode"
        let statusColor: UIColor = productionMode ? .systemGreen : .systemOrange

        section.add(OWSTableItem(
            customCellBlock: {
                let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
                cell.textLabel?.text = "\(statusIcon) Cryptography Status"
                cell.detailTextLabel?.text = statusText
                cell.detailTextLabel?.textColor = statusColor
                cell.selectionStyle = .none
                return cell
            }
        ))

        // Algorithm details
        if productionMode {
            section.add(.label(
                withText: "• ML-KEM-1024 (NIST FIPS 203) - Key Encapsulation",
                accessibilityIdentifier: "emma_mlkem_status"
            ))

            section.add(.label(
                withText: "• ML-DSA-87 (NIST FIPS 204) - Digital Signatures",
                accessibilityIdentifier: "emma_mldsa_status"
            ))

            section.add(.label(
                withText: "• AES-256-GCM - Symmetric Encryption",
                accessibilityIdentifier: "emma_aes_status"
            ))

            section.footerTitle = "Your messages are protected with NIST-standardized post-quantum cryptography."
        } else {
            section.footerTitle = "Development mode uses stub cryptography. Enable production mode by integrating liboqs.xcframework."
        }

        return section
    }
}


// MARK: - Language Preferences SwiftUI View

@available(iOS 15.0, *)
struct LanguagePreferencesView: View {
    @AppStorage("EMMA.SourceLanguage") private var sourceLanguage = "da"
    @AppStorage("EMMA.TargetLanguage") private var targetLanguage = "en"
    @AppStorage("EMMA.NetworkFallbackEnabled") private var networkFallback = true

    let supportedLanguages = [
        ("da", "Danish"),
        ("en", "English"),
        ("de", "German"),
        ("fr", "French"),
        ("es", "Spanish")
    ]

    var body: some View {
        Form {
            Section(header: Text("Translation Direction")) {
                Picker("Source Language", selection: $sourceLanguage) {
                    ForEach(supportedLanguages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }

                Picker("Target Language", selection: $targetLanguage) {
                    ForEach(supportedLanguages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
            }

            Section(header: Text("Translation Method")) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "brain")
                            .foregroundColor(.blue)
                        Text("On-Device Translation")
                            .font(.headline)
                    }

                    Text("Primary translation method using CoreML. Private and works offline.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)

                Toggle("Enable Network Fallback", isOn: $networkFallback)

                if networkFallback {
                    Text("Network translation is used only when on-device translation is unavailable or for unsupported language pairs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Model Information")) {
                let engine = EMTranslationEngine.shared()
                let modelLoaded = engine.isModelLoaded()

                HStack {
                    Text("Model Status")
                    Spacer()
                    Text(modelLoaded ? "Loaded" : "Not Loaded")
                        .foregroundColor(modelLoaded ? .green : .orange)
                }

                if modelLoaded {
                    HStack {
                        Text("Model Type")
                        Spacer()
                        Text("OPUS-MT CoreML")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Model Size")
                        Spacer()
                        Text("~78 MB (INT8)")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Language Preferences")
    }
}


// MARK: - Integration Checklist

/*

To integrate EMMA settings into Signal:

☐ 1. Locate AppSettingsViewController.swift:
     File: Signal/src/ViewControllers/AppSettings/AppSettingsViewController.swift

☐ 2. Find updateTableContents method

☐ 3. Add EMMA section:
     if #available(iOS 15.0, *) { contents.add(emmaSettingsSection()) }

☐ 4. Choose integration style:
     - Minimal: Just the settings button (Example 1)
     - Inline: Quick toggles in settings (Example 4)
     - Detailed: Full status display (Example 3)

☐ 5. Test settings:
     - Open Signal Settings
     - Verify EMMA section appears
     - Tap EMMA → should open full settings view
     - Toggle features and verify they work

☐ 6. Verify translation priority:
     - On-device (CoreML) is primary
     - Network fallback is secondary
     - Check logs show correct mode

*/


// MARK: - Troubleshooting

/*

Common issues:

1. EMMA section doesn't appear in settings
   Solution: Verify iOS 15.0+ check and extension file is in target

2. Settings crash when tapped
   Solution: Ensure EMMASettingsView is imported and compiled

3. Toggles don't persist
   Solution: Check UserDefaults keys match exactly:
   - EMMA.SecurityMonitoring
   - EMMA.AutoTranslate
   - EMMA.ShowSecurityHUD

4. Translation always uses network
   Solution: Verify CoreML model is:
   - Added to Xcode project
   - Included in Signal target
   - Named correctly (EMMATranslation_da_en.mlmodel)

5. On-device translation not available
   Solution:
   - Check model file is in app bundle
   - Run: ./EMMA/Scripts/convert_translation_model.py --quantize
   - Verify model loads: EMTranslationEngine.shared().isModelLoaded()

*/
