//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public class SafetyNumberConfirmationAlert: NSObject {

    private let contactsManager: OWSContactsManager
    private let primaryStorage: OWSPrimaryStorage

    init(contactsManager: OWSContactsManager) {
        self.contactsManager = contactsManager
        self.primaryStorage = OWSPrimaryStorage.shared()
    }

    @objc
    public class func presentAlertIfNecessary(recipientId: String, confirmationText: String, contactsManager: OWSContactsManager, completion: @escaping (Bool) -> Void) -> Bool {
        return self.presentAlertIfNecessary(recipientIds: [recipientId], confirmationText: confirmationText, contactsManager: contactsManager, completion: completion, beforePresentationHandler: nil)
    }

    @objc
    public class func presentAlertIfNecessary(recipientId: String, confirmationText: String, contactsManager: OWSContactsManager, completion: @escaping (Bool) -> Void, beforePresentationHandler: (() -> Void)? = nil) -> Bool {
        return self.presentAlertIfNecessary(recipientIds: [recipientId], confirmationText: confirmationText, contactsManager: contactsManager, completion: completion, beforePresentationHandler: beforePresentationHandler)
    }

    @objc
    public class func presentAlertIfNecessary(recipientIds: [String], confirmationText: String, contactsManager: OWSContactsManager, completion: @escaping (Bool) -> Void) -> Bool {
        return self.presentAlertIfNecessary(recipientIds: recipientIds, confirmationText: confirmationText, contactsManager: contactsManager, completion: completion, beforePresentationHandler: nil)
    }

    @objc
    public class func presentAlertIfNecessary(recipientIds: [String], confirmationText: String, contactsManager: OWSContactsManager, completion: @escaping (Bool) -> Void, beforePresentationHandler: (() -> Void)? = nil) -> Bool {
        return SafetyNumberConfirmationAlert(contactsManager: contactsManager).presentIfNecessary(recipientIds: recipientIds,
                                                                                                  confirmationText: confirmationText,
                                                                                                  completion: completion,
                                                                                                  beforePresentationHandler: beforePresentationHandler)
    }

    /**
     * Shows confirmation dialog if at least one of the recipient id's is not confirmed.
     *
     * @returns true  if an alert was shown
     *          false if there were no unconfirmed identities
     */
    public func presentIfNecessary(recipientIds: [String], confirmationText: String, completion: @escaping (Bool) -> Void, beforePresentationHandler: (() -> Void)? = nil) -> Bool {

        guard let untrustedIdentity = untrustedIdentityForSending(recipientIds: recipientIds) else {
            // No identities to confirm, no alert to present.
            return false
        }

        let displayName = contactsManager.displayName(forPhoneIdentifier: untrustedIdentity.recipientId)

        let titleFormat = NSLocalizedString("CONFIRM_SENDING_TO_CHANGED_IDENTITY_TITLE_FORMAT",
                                            comment: "Action sheet title presented when a user's SN has recently changed. Embeds {{contact's name or phone number}}")
        let title = String(format: titleFormat, displayName)

        let bodyFormat = NSLocalizedString("CONFIRM_SENDING_TO_CHANGED_IDENTITY_BODY_FORMAT",
                                           comment: "Action sheet body presented when a user's SN has recently changed. Embeds {{contact's name or phone number}}")
        let body = String(format: bodyFormat, displayName)

        let actionSheetController = UIAlertController(title: title, message: body, preferredStyle: .actionSheet)

        let confirmAction = UIAlertAction(title: confirmationText, style: .default) { _ in
            Logger.info("Confirmed identity: \(untrustedIdentity)")

        self.primaryStorage.newDatabaseConnection().asyncReadWrite { (transaction) in
            OWSIdentityManager.shared().setVerificationState(.default, identityKey: untrustedIdentity.identityKey, recipientId: untrustedIdentity.recipientId, isUserInitiatedChange: true, transaction: transaction)
                DispatchQueue.main.async {
                    completion(true)
                }
            }
        }
        actionSheetController.addAction(confirmAction)

        let showSafetyNumberAction = UIAlertAction(title: NSLocalizedString("VERIFY_PRIVACY", comment: "Label for button or row which allows users to verify the safety number of another user."), style: .default) { _ in
            Logger.info("Opted to show Safety Number for identity: \(untrustedIdentity)")

            self.presentSafetyNumberViewController(theirIdentityKey: untrustedIdentity.identityKey,
                                                   theirRecipientId: untrustedIdentity.recipientId,
                                                   theirDisplayName: displayName,
                                                   completion: { completion(false) })

        }
        actionSheetController.addAction(showSafetyNumberAction)

        // We can't use the default `OWSAlerts.cancelAction` because we need to specify that the completion
        // handler is called.
        let cancelAction = UIAlertAction(title: CommonStrings.cancelButton, style: .cancel) { _ in
            Logger.info("user canceled.")
            completion(false)
        }
        actionSheetController.addAction(cancelAction)

        beforePresentationHandler?()

        UIApplication.shared.frontmostViewController?.present(actionSheetController, animated: true)
        return true
    }

    public func presentSafetyNumberViewController(theirIdentityKey: Data, theirRecipientId: String, theirDisplayName: String, completion: (() -> Void)? = nil) {
        guard let fromViewController = UIApplication.shared.frontmostViewController else {
            Logger.info("Missing frontmostViewController")
            return
        }
        FingerprintViewController.present(from: fromViewController, recipientId: theirRecipientId)
    }

    private func untrustedIdentityForSending(recipientIds: [String]) -> OWSRecipientIdentity? {
        return recipientIds.compactMap {
            OWSIdentityManager.shared().untrustedIdentityForSending(toRecipientId: $0)
        }.first
    }
}
