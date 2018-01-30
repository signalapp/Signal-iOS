//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

class SafetyNumberConfirmationAlert: NSObject {

    let TAG = "[SafetyNumberConfirmationAlert]"

    private let contactsManager: OWSContactsManager
    private let storageManager: TSStorageManager

    init(contactsManager: OWSContactsManager) {
        self.contactsManager = contactsManager
        self.storageManager = TSStorageManager.shared()
    }

    public class func presentAlertIfNecessary(recipientId: String, confirmationText: String, contactsManager: OWSContactsManager, completion: @escaping (Bool) -> Void) -> Bool {
        return self.presentAlertIfNecessary(recipientIds: [recipientId], confirmationText: confirmationText, contactsManager: contactsManager, completion: completion)
    }

    public class func presentAlertIfNecessary(recipientIds: [String], confirmationText: String, contactsManager: OWSContactsManager, completion: @escaping (Bool) -> Void) -> Bool {
        return SafetyNumberConfirmationAlert(contactsManager: contactsManager).presentIfNecessary(recipientIds: recipientIds,
                                                                                                  confirmationText: confirmationText,
                                                                                                  completion: completion)
    }

    /**
     * Shows confirmation dialog if at least one of the recipient id's is not confirmed.
     *
     * @returns true  if an alert was shown
     *          false if there were no unconfirmed identities
     */
    public func presentIfNecessary(recipientIds: [String], confirmationText: String, completion: @escaping (Bool) -> Void) -> Bool {

        guard let untrustedIdentity = untrustedIdentityForSending(recipientIds: recipientIds) else {
            // No identities to confirm, no alert to present.
            return false
        }

        let displayName = contactsManager.displayName(forPhoneIdentifier: untrustedIdentity.recipientId)

        let titleFormat = NSLocalizedString("CONFIRM_SENDING_TO_CHANGED_IDENTITY_TITLE_FORMAT",
                                            comment: "Action sheet title presented when a users's SN have recently changed. Embeds {{contact's name or phone number}}")
        let title = String(format: titleFormat, displayName)

        let bodyFormat = NSLocalizedString("CONFIRM_SENDING_TO_CHANGED_IDENTITY_BODY_FORMAT",
                                           comment: "Action sheet body presented when a user's SN have recently changed. Embeds {{contact's name or phone nubmer}}")
        let body = String(format: bodyFormat, displayName)

        let actionSheetController = UIAlertController(title: title, message:body, preferredStyle: .actionSheet)

        let confirmAction = UIAlertAction(title: confirmationText, style: .default) { _ in
            Logger.info("\(self.TAG) Confirmed identity: \(untrustedIdentity)")

        TSStorageManager.protocolStoreDBConnection().asyncReadWrite { (transaction) in
            OWSIdentityManager.shared().setVerificationState(.default, identityKey: untrustedIdentity.identityKey, recipientId: untrustedIdentity.recipientId, isUserInitiatedChange: true, protocolContext: transaction)
                DispatchQueue.main.async {
                    completion(true)
                }
            }
        }
        actionSheetController.addAction(confirmAction)

        let showSafetyNumberAction = UIAlertAction(title: NSLocalizedString("VERIFY_PRIVACY", comment: "Label for button or row which allows users to verify the safety number of another user."), style: .default) { _ in
            Logger.info("\(self.TAG) Opted to show Safety Number for identity: \(untrustedIdentity)")

            self.presentSafetyNumberViewController(theirIdentityKey: untrustedIdentity.identityKey,
                                                   theirRecipientId: untrustedIdentity.recipientId,
                                                   theirDisplayName: displayName,
                                                   completion: { completion(false) })

        }
        actionSheetController.addAction(showSafetyNumberAction)

        actionSheetController.addAction(OWSAlerts.cancelAction)

        UIApplication.shared.frontmostViewController?.present(actionSheetController, animated: true)
        return true
    }

    public func presentSafetyNumberViewController(theirIdentityKey: Data, theirRecipientId: String, theirDisplayName: String, completion: (() -> Void)? = nil) {
        guard let fromViewController = UIApplication.shared.frontmostViewController else {
            Logger.info("\(self.TAG) Missing frontmostViewController")
            return
        }
        FingerprintViewController.present(from:fromViewController, recipientId:theirRecipientId)
    }

    private func untrustedIdentityForSending(recipientIds: [String]) -> OWSRecipientIdentity? {
        return recipientIds.flatMap {
            OWSIdentityManager.shared().untrustedIdentityForSending(toRecipientId: $0)
        }.first
    }
}
