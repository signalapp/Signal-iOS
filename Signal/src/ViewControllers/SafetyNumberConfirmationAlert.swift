//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation

class SafetyNumberConfirmationAlert: NSObject {

    let TAG = "[SafetyNumberConfirmationAlert]"

    private let contactsManager: OWSContactsManager
    private let storageManager: TSStorageManager

    init(contactsManager: OWSContactsManager) {
        self.contactsManager = contactsManager
        self.storageManager = TSStorageManager.shared()
    }

    public class func presentAlertIfNecessary(recipientId: String, confirmationText: String, contactsManager: OWSContactsManager, verifySeen: Bool, completion: @escaping (Bool) -> Void) -> Bool {
        return self.presentAlertIfNecessary(recipientIds: [recipientId], confirmationText: confirmationText, contactsManager: contactsManager, verifySeen: verifySeen, completion: completion)
    }

    public class func presentAlertIfNecessary(recipientIds: [String], confirmationText: String, contactsManager: OWSContactsManager, verifySeen: Bool, completion: @escaping (Bool) -> Void) -> Bool {
        return SafetyNumberConfirmationAlert(contactsManager: contactsManager).presentIfNecessary(recipientIds: recipientIds,
                                                                                                  confirmationText: confirmationText,
                                                                                                  verifySeen: verifySeen,
                                                                                                  completion: completion)
    }

    /**
     * Shows confirmation dialog if at least one of the recipient id's is not confirmed.
     *
     * @returns true  if an alert was shown
     *          false if there were no unconfirmed identities
     */
    public func presentIfNecessary(recipientIds: [String], confirmationText: String, verifySeen: Bool, completion: @escaping (Bool) -> Void) -> Bool {

        let unconfirmedIdentity = firstUnconfirmedIdentity(recipientIds: recipientIds)

        var unseenIdentity: OWSRecipientIdentity?
        if verifySeen {
            unseenIdentity = firstUnseenIdentity(recipientIds: recipientIds)
        }

        guard let untrustedIdentity = unseenIdentity ?? unconfirmedIdentity else {
            // No identities to confirm/see, so no alert to present.
            return false
        }

        let displayName: String = {
            if let signalAccount = contactsManager.signalAccountMap[untrustedIdentity.recipientId] {
                return contactsManager.displayName(for: signalAccount)
            } else {
                return contactsManager.displayName(forPhoneIdentifier: untrustedIdentity.recipientId)
            }
        }()

        let titleFormat = NSLocalizedString("CONFIRM_SENDING_TO_CHANGED_IDENTITY_TITLE_FORMAT",
                                            comment: "Action sheet title presented when a users's SN have recently changed. Embeds {{contact's name or phone number}}")
        let title = String(format: titleFormat, displayName)

        let bodyFormat = NSLocalizedString("CONFIRM_SENDING_TO_CHANGED_IDENTITY_BODY_FORMAT",
                                           comment: "Action sheet body presented when a user's SN have recently changed. Embeds {{contact's name or phone nubmer}}")
        let body = String(format: bodyFormat, displayName)

        let actionSheetController = UIAlertController(title: title, message:body, preferredStyle: .actionSheet)

        let confirmAction = UIAlertAction(title: confirmationText, style: .default) { _ in
            Logger.info("\(self.TAG) Confirmed identity: \(untrustedIdentity)")

            OWSDispatch.sessionStoreQueue().async {
                self.storageManager.saveRemoteIdentity(untrustedIdentity.identityKey,
                                                       recipientId: untrustedIdentity.recipientId,
                                                       approvedForBlockingUse: true,
                                                       approvedForNonBlockingUse: true)
                MarkIdentityAsSeenJob.run(recipientId: untrustedIdentity.recipientId)
                DispatchQueue.main.async {
                    completion(true)
                }
            }
        }
        actionSheetController.addAction(confirmAction)

        let showSafetyNumberAction = UIAlertAction(title: NSLocalizedString("VERIFY_PRIVACY", comment: "Action sheet item"), style: .default) { _ in
            Logger.info("\(self.TAG) Opted to show Safety Number for identity: \(untrustedIdentity)")

            self.presentSafetyNumberViewController(theirIdentityKey: untrustedIdentity.identityKey,
                                                   theirRecipientId: untrustedIdentity.recipientId,
                                                   theirDisplayName: displayName,
                                                   completion: { completion(false) })

        }
        actionSheetController.addAction(showSafetyNumberAction)

        let dismissAction = UIAlertAction(title: NSLocalizedString("TXT_CANCEL_TITLE", comment: "generic cancel text"), style: .cancel)
        actionSheetController.addAction(dismissAction)

        UIApplication.shared.frontmostViewController?.present(actionSheetController, animated: true)
        return true
    }

    public func presentSafetyNumberViewController(theirIdentityKey: Data, theirRecipientId: String, theirDisplayName: String, completion: (() -> Void)? = nil) {
        let fingerprintViewController = UIStoryboard.instantiateFingerprintViewController()

        let fingerprintBuilder = OWSFingerprintBuilder(storageManager: self.storageManager, contactsManager: self.contactsManager)
        let fingerprint = fingerprintBuilder.fingerprint(withTheirSignalId: theirRecipientId, theirIdentityKey: theirIdentityKey)

        fingerprintViewController.configure(fingerprint: fingerprint, contactName: theirDisplayName)

        UIApplication.shared.frontmostViewController?.present(fingerprintViewController, animated: true, completion: completion)
    }

    private func firstUnconfirmedIdentity(recipientIds: [String]) -> OWSRecipientIdentity? {
        return recipientIds.flatMap {
            self.storageManager.unconfirmedIdentityThatShouldBlockSending(forRecipientId: $0)
        }.first
    }

    private func firstUnseenIdentity(recipientIds: [String]) -> OWSRecipientIdentity? {
        return self.storageManager.unseenIdentityChanges(forRecipientIds: recipientIds).first
    }

}
