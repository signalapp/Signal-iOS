// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import SessionMessagingKit

@objc public class BlockListUIUtils: NSObject {
    // MARK: - Block
    
    /// This method shows an alert to unblock a contact in a ContactThread and will update the `isBlocked` flag of the contact if the user decides to continue
    ///
    /// **Note:** Make sure to force a config sync in the `completionBlock` if the blocked state was successfully changed
    @objc public static func showBlockThreadActionSheet(_ threadId: String, from viewController: UIViewController, completionBlock: ((Bool) -> ())? = nil) {
        let userPublicKey = getUserHexEncodedPublicKey()
        
        guard threadId != userPublicKey else {
            completionBlock?(false)
            return
        }
        
        let displayName: String = Profile.displayName(id: threadId)
        let actionSheet: UIAlertController = UIAlertController(
            title: String(
                format: "BLOCK_LIST_BLOCK_USER_TITLE_FORMAT".localized(),
                self.formatForAlertTitle(displayName: displayName)
            ),
            message: "BLOCK_USER_BEHAVIOR_EXPLANATION".localized(),
            preferredStyle: .actionSheet
        )
        actionSheet.addAction(UIAlertAction(
            title: "BLOCK_LIST_BLOCK_BUTTON".localized(),
            accessibilityIdentifier: "\(type(of: self).self).block",
            style: .destructive,
            handler: { _ in
                Storage.shared.writeAsync(
                    updates: { db in
                        try Contact
                            .fetchOrCreate(db, id: threadId)
                            .with(isBlocked: true)
                            .save(db)
                    },
                    completion: { _, _ in
                        self.showOkAlert(
                            title: "BLOCK_LIST_VIEW_BLOCKED_ALERT_TITLE".localized(),
                            message: String(
                                format: "BLOCK_LIST_VIEW_BLOCKED_ALERT_MESSAGE_FORMAT".localized(),
                                self.formatForAlertMessage(displayName: displayName)
                            ),
                            from: viewController,
                            completionBlock: { _ in completionBlock?(true) }
                        )
                    }
                )
            }
        ))
        actionSheet.addAction(UIAlertAction(
            title: CommonStrings.cancelButton,
            accessibilityIdentifier: "\(type(of: self).self).dismiss",
            style: .cancel,
            handler: { _ in completionBlock?(false) }
        ))
        
        viewController.presentAlert(actionSheet)
    }
    
    // MARK: - Unblock
    
    /// This method shows an alert to unblock a contact in a ContactThread and will update the `isBlocked` flag of the contact if the user decides to continue
    ///
    /// **Note:** Make sure to force a config sync in the `completionBlock` if the blocked state was successfully changed
    @objc public static func showUnblockThreadActionSheet(_ threadId: String, from viewController: UIViewController, completionBlock: ((Bool) -> ())? = nil) {
        let displayName: String = Profile.displayName(id: threadId)
        let actionSheet: UIAlertController = UIAlertController(
            title: String(
                format: "BLOCK_LIST_UNBLOCK_TITLE_FORMAT".localized(),
                self.formatForAlertTitle(displayName: displayName)
            ),
            message: nil,
            preferredStyle: .actionSheet
        )
        actionSheet.addAction(UIAlertAction(
            title: "BLOCK_LIST_UNBLOCK_BUTTON".localized(),
            accessibilityIdentifier: "\(type(of: self).self).unblock",
            style: .destructive,
            handler: { _ in
                Storage.shared.writeAsync(
                    updates: { db in
                        try Contact
                            .fetchOrCreate(db, id: threadId)
                            .with(isBlocked: false)
                            .save(db)
                    },
                    completion: { _, _ in
                        self.showOkAlert(
                            title: String(
                                format: "BLOCK_LIST_VIEW_UNBLOCKED_ALERT_TITLE_FORMAT".localized(),
                                self.formatForAlertMessage(displayName: displayName)
                            ),
                            message: nil,
                            from: viewController,
                            completionBlock: { _ in completionBlock?(false) }
                        )
                    })
            }
        ))
        actionSheet.addAction(UIAlertAction(
            title: CommonStrings.cancelButton,
            accessibilityIdentifier: "\(type(of: self).self).dismiss",
            style: .cancel,
            handler: { _ in completionBlock?(true) }
        ))
        
        viewController.presentAlert(actionSheet)
    }
    
    // MARK: - UI
    
    @objc public static func showOkAlert(title: String, message: String?, from viewController: UIViewController, completionBlock: @escaping (UIAlertAction) -> ()) {
        let alertController: UIAlertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(
            title: "BUTTON_OK".localized(),
            accessibilityIdentifier: "\(type(of: self).self).ok",
            style: .default,
            handler: completionBlock
        ))
        
        viewController.presentAlert(alertController)
    }
    
    @objc public static func formatForAlertTitle(displayName: String) -> String {
        return format(displayName: displayName, maxLength: 20)
    }
    
    @objc public static func formatForAlertMessage(displayName: String) -> String {
        return format(displayName: displayName, maxLength: 127)
    }
    
    @objc public static func format(displayName: String, maxLength: Int) -> String {
        guard displayName.count <= maxLength else {
            return "\(displayName.substring(to: maxLength))…"
        }
        
        return displayName
    }
}
