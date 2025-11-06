//
//  SignalConversationViewController+SWORDCOMM.swift
//  Signal-iOS SWORDCOMM Conversation Integration
//
//  Extension to add SWORDCOMM SecurityHUD to conversation views
//

import Foundation
import SwiftUI
import UIKit

@available(iOS 15.0, *)
extension ConversationViewController {

    /// Security HUD hosting controller
    private static var securityHUDHostingControllerKey: UInt8 = 0

    private var securityHUDHostingController: UIHostingController<SecurityHUD>? {
        get {
            return objc_getAssociatedObject(self, &Self.securityHUDHostingControllerKey) as? UIHostingController<SecurityHUD>
        }
        set {
            objc_setAssociatedObject(self, &Self.securityHUDHostingControllerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// Set up SWORDCOMM SecurityHUD overlay
    /// Call this from viewDidLoad() to add the security HUD to the conversation
    func setupSWORDCOMMSecurityHUD() {
        // Check if security HUD is enabled in settings
        guard UserDefaults.standard.bool(forKey: "SWORDCOMM.ShowSecurityHUD") else {
            return
        }

        // Create SecurityHUD
        let securityHUD = SecurityHUD()
        let hostingController = UIHostingController(rootView: securityHUD)

        // Configure hosting controller
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        // Add as child view controller
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        // Position at top of conversation (below navigation bar)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 8
            ),
            hostingController.view.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: 16
            ),
            hostingController.view.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -16
            )
        ])

        // Store reference
        securityHUDHostingController = hostingController

        Logger.debug("[SWORDCOMM] SecurityHUD added to conversation")
    }

    /// Remove SWORDCOMM SecurityHUD overlay
    /// Call this to remove the HUD (e.g., when user disables it in settings)
    func removeSWORDCOMMSecurityHUD() {
        guard let hostingController = securityHUDHostingController else {
            return
        }

        hostingController.willMove(toParent: nil)
        hostingController.view.removeFromSuperview()
        hostingController.removeFromParent()

        securityHUDHostingController = nil

        Logger.debug("[SWORDCOMM] SecurityHUD removed from conversation")
    }

    /// Toggle SecurityHUD visibility
    func toggleSWORDCOMMSecurityHUD(enabled: Bool) {
        if enabled {
            if securityHUDHostingController == nil {
                setupSWORDCOMMSecurityHUD()
            }
        } else {
            removeSWORDCOMMSecurityHUD()
        }
    }

    /// Check if SecurityHUD is currently displayed
    var isSecurityHUDDisplayed: Bool {
        return securityHUDHostingController != nil
    }
}

// MARK: - Integration Instructions

/*

 To integrate SWORDCOMM SecurityHUD into Signal's ConversationViewController:

 1. In ConversationViewController.viewDidLoad(), add SecurityHUD setup:

    override func viewDidLoad() {
        super.viewDidLoad()

        // ... existing Signal setup ...

        // ┌──────────────────────────────────┐
        // │ SWORDCOMM SecurityHUD Integration     │
        // └──────────────────────────────────┘
        if #available(iOS 15.0, *) {
            setupSWORDCOMMSecurityHUD()
        }

        // ... rest of view setup ...
    }


 2. To observe settings changes and update HUD visibility:

    // In viewDidLoad() or appropriate init method:
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(emmaSettingsDidChange),
        name: NSNotification.Name("SWORDCOMM.SettingsDidChange"),
        object: nil
    )

    @objc
    private func emmaSettingsDidChange() {
        guard #available(iOS 15.0, *) else { return }

        let shouldShow = UserDefaults.standard.bool(forKey: "SWORDCOMM.ShowSecurityHUD")
        toggleSWORDCOMMSecurityHUD(enabled: shouldShow)
    }


 3. Alternative: Conditional HUD based on conversation security level:

    func setupSWORDCOMMSecurityHUD() {
        // Only show HUD for certain conversations (e.g., group chats, unverified contacts)
        guard shouldShowSecurityHUDForCurrentThread() else {
            return
        }

        // ... setup HUD ...
    }

    private func shouldShowSecurityHUDForCurrentThread() -> Bool {
        // Check conversation security properties
        // Return true if HUD should be displayed for this thread
        return UserDefaults.standard.bool(forKey: "SWORDCOMM.ShowSecurityHUD")
    }


 4. To update HUD layout when keyboard appears/dismisses:

    @objc
    private func keyboardWillShow(notification: NSNotification) {
        // Adjust HUD position if needed
        if #available(iOS 15.0, *), let hostingController = securityHUDHostingController {
            // Update constraints or animate HUD
        }
    }

 */
