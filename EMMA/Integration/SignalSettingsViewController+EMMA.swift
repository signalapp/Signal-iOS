//
//  SignalSettingsViewController+EMMA.swift
//  Signal-iOS EMMA Settings Integration
//
//  Extension to add EMMA settings to Signal's settings view
//

import Foundation
import SwiftUI
import SignalUI

@available(iOS 15.0, *)
extension AppSettingsViewController {

    /// Create EMMA settings section for Signal Settings
    /// Call this from updateTableContents() to add EMMA settings
    func emmaSettingsSection() -> OWSTableSection {
        let section = OWSTableSection()

        section.add(.disclosureItem(
            icon: .settingsAdvanced, // Using advanced settings icon as placeholder
            withText: "EMMA Security",
            accessibilityIdentifier: "emma_settings",
            actionBlock: { [weak self] in
                self?.showEMMASettings()
            }
        ))

        // Add subtitle/status indicator
        section.customHeaderView = {
            let label = UILabel()
            label.text = "Enterprise Messaging Military-grade Android"
            label.font = .systemFont(ofSize: 13)
            label.textColor = Theme.secondaryTextAndIconColor
            label.textAlignment = .natural
            return label
        }()

        return section
    }

    /// Show EMMA settings view controller
    private func showEMMASettings() {
        let emmaSettings = UIHostingController(rootView: EMMASettingsView())
        emmaSettings.title = "EMMA"

        // Set up navigation bar
        emmaSettings.navigationItem.largeTitleDisplayMode = .never

        // Push onto navigation stack
        self.navigationController?.pushViewController(emmaSettings, animated: true)
    }

    /// Get EMMA status indicator for settings row
    /// Returns emoji or text indicator of current EMMA status
    var emmaStatusIndicator: String {
        // Check if EMMA is enabled
        guard UserDefaults.standard.bool(forKey: "EMMA.SecurityMonitoring") != false else {
            return "" // Disabled
        }

        // Check crypto mode
        if liboqs_ml_kem_1024_enabled() && liboqs_ml_dsa_87_enabled() {
            return "🔒" // Production crypto
        } else {
            return "⚠️" // Stub mode
        }
    }

    /// Get EMMA security status text
    var emmaSecurityStatus: String {
        guard UserDefaults.standard.bool(forKey: "EMMA.SecurityMonitoring") != false else {
            return "Disabled"
        }

        if liboqs_ml_kem_1024_enabled() && liboqs_ml_dsa_87_enabled() {
            return "Production Crypto"
        } else {
            return "Development Mode"
        }
    }
}

// MARK: - Integration Instructions

/*

 To integrate EMMA settings into Signal's AppSettingsViewController:

 1. In AppSettingsViewController.updateTableContents(), add EMMA section:

    func updateTableContents() {
        let isPrimaryDevice = DependenciesBridge.shared.db.read { tx in
            return DependenciesBridge.shared.tsAccountManager
                .registrationState(tx: tx)
                .isPrimaryDevice == true
        }

        let contents = OWSTableContents()

        // ... existing sections (profile, section1, section2) ...

        // ┌──────────────────────────────────┐
        // │ EMMA Settings Section             │
        // └──────────────────────────────────┘
        if #available(iOS 15.0, *) {
            let emmaSection = emmaSettingsSection()
            contents.add(emmaSection)
        }

        // ... rest of existing sections ...

        self.contents = contents
    }

 2. Alternative: Add EMMA to section2 (alongside Privacy, Notifications, etc):

    section2.add(.disclosureItem(
        icon: .settingsAdvanced,
        withText: "EMMA Security",
        accessibilityIdentifier: "emma_settings",
        actionBlock: { [weak self] in
            guard #available(iOS 15.0, *) else { return }
            let emmaSettings = UIHostingController(rootView: EMMASettingsView())
            emmaSettings.title = "EMMA"
            self?.navigationController?.pushViewController(emmaSettings, animated: true)
        }
    ))

 3. To add a status indicator (shows crypto mode):

    section2.add(.init(customCellBlock: { [weak self] in
        guard let self = self else { return UITableViewCell() }
        guard #available(iOS 15.0, *) else { return UITableViewCell() }

        let statusLabel = UILabel()
        statusLabel.text = self.emmaStatusIndicator
        statusLabel.font = .systemFont(ofSize: 24)
        statusLabel.sizeToFit()

        return OWSTableItem.buildCell(
            icon: .settingsAdvanced,
            itemName: "EMMA Security",
            subtitle: self.emmaSecurityStatus,
            accessoryType: .disclosureIndicator,
            accessoryContentView: statusLabel,
            accessibilityIdentifier: "emma_settings"
        )
    }, actionBlock: { [weak self] in
        guard #available(iOS 15.0, *) else { return }
        self?.showEMMASettings()
    }))

 */
