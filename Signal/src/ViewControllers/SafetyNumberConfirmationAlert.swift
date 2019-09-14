//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
public class SafetyNumberConfirmationAlert: NSObject {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    private let contactsManager: OWSContactsManager

    init(contactsManager: OWSContactsManager) {
        self.contactsManager = contactsManager
    }

    @objc
    public class func presentAlertIfNecessary(address: SignalServiceAddress, confirmationText: String, contactsManager: OWSContactsManager, completion: @escaping (Bool) -> Void) -> Bool {
        return self.presentAlertIfNecessary(addresses: [address], confirmationText: confirmationText, contactsManager: contactsManager, completion: completion, beforePresentationHandler: nil)
    }

    @objc
    public class func presentAlertIfNecessary(address: SignalServiceAddress, confirmationText: String, contactsManager: OWSContactsManager, completion: @escaping (Bool) -> Void, beforePresentationHandler: (() -> Void)? = nil) -> Bool {
        return self.presentAlertIfNecessary(addresses: [address], confirmationText: confirmationText, contactsManager: contactsManager, completion: completion, beforePresentationHandler: beforePresentationHandler)
    }

    @objc
    public class func presentAlertIfNecessary(addresses: [SignalServiceAddress], confirmationText: String, contactsManager: OWSContactsManager, completion: @escaping (Bool) -> Void) -> Bool {
        return self.presentAlertIfNecessary(addresses: addresses, confirmationText: confirmationText, contactsManager: contactsManager, completion: completion, beforePresentationHandler: nil)
    }

    @objc
    public class func presentAlertIfNecessary(addresses: [SignalServiceAddress], confirmationText: String, contactsManager: OWSContactsManager, completion: @escaping (Bool) -> Void, beforePresentationHandler: (() -> Void)? = nil) -> Bool {
        return SafetyNumberConfirmationAlert(contactsManager: contactsManager).presentIfNecessary(addresses: addresses,
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
    public func presentIfNecessary(addresses: [SignalServiceAddress], confirmationText: String, completion: @escaping (Bool) -> Void, beforePresentationHandler: (() -> Void)? = nil) -> Bool {

        guard let (untrustedAddress, untrustedIdentity) = untrustedIdentityForSending(addresses: addresses) else {
            // No identities to confirm, no alert to present.
            return false
        }

        let displayName = contactsManager.displayName(for: untrustedAddress)

        let titleFormat = NSLocalizedString("CONFIRM_SENDING_TO_CHANGED_IDENTITY_TITLE_FORMAT",
                                            comment: "Action sheet title presented when a user's SN has recently changed. Embeds {{contact's name or phone number}}")
        let title = String(format: titleFormat, displayName)

        let bodyFormat = NSLocalizedString("CONFIRM_SENDING_TO_CHANGED_IDENTITY_BODY_FORMAT",
                                           comment: "Action sheet body presented when a user's SN has recently changed. Embeds {{contact's name or phone number}}")
        let body = String(format: bodyFormat, displayName)

        let actionSheet = UIAlertController(title: title, message: body, preferredStyle: .actionSheet)

        let confirmAction = UIAlertAction(title: confirmationText, style: .default) { _ in
            Logger.info("Confirmed identity: \(untrustedIdentity)")

            self.databaseStorage.asyncWrite { (transaction) in
                OWSIdentityManager.shared().setVerificationState(.default, identityKey: untrustedIdentity.identityKey, address: untrustedAddress, isUserInitiatedChange: true, transaction: transaction)

                transaction.addCompletion {
                    completion(true)
                }
            }
        }
        actionSheet.addAction(confirmAction)

        let showSafetyNumberAction = UIAlertAction(title: NSLocalizedString("VERIFY_PRIVACY", comment: "Label for button or row which allows users to verify the safety number of another user."), style: .default) { _ in
            Logger.info("Opted to show Safety Number for identity: \(untrustedIdentity)")

            self.presentSafetyNumberViewController(theirIdentityKey: untrustedIdentity.identityKey,
                                                   theirRecipientAddress: untrustedAddress,
                                                   theirDisplayName: displayName,
                                                   completion: { completion(false) })

        }
        actionSheet.addAction(showSafetyNumberAction)

        // We can't use the default `OWSAlerts.cancelAction` because we need to specify that the completion
        // handler is called.
        let cancelAction = UIAlertAction(title: CommonStrings.cancelButton, style: .cancel) { _ in
            Logger.info("user canceled.")
            completion(false)
        }
        actionSheet.addAction(cancelAction)

        beforePresentationHandler?()

        UIApplication.shared.frontmostViewController?.presentAlert(actionSheet)
        return true
    }

    public func presentSafetyNumberViewController(theirIdentityKey: Data, theirRecipientAddress: SignalServiceAddress, theirDisplayName: String, completion: (() -> Void)? = nil) {
        guard let fromViewController = UIApplication.shared.frontmostViewController else {
            Logger.info("Missing frontmostViewController")
            return
        }
        FingerprintViewController.present(from: fromViewController, address: theirRecipientAddress)
    }

    private func untrustedIdentityForSending(addresses: [SignalServiceAddress]) -> (SignalServiceAddress, OWSRecipientIdentity)? {
        return addresses.compactMap {
            guard let identity = OWSIdentityManager.shared().untrustedIdentityForSending(to: $0) else {
                return nil
            }
            return ($0, identity)
        }.first
    }
}
