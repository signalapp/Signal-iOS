//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import ContactsUI
import MessageUI

@objc
public protocol ContactShareViewHelperDelegate: class {
    func didCreateOrEditContact()
}

@objc
public class ContactShareViewHelper: NSObject, CNContactViewControllerDelegate {

    @objc
    weak var delegate: ContactShareViewHelperDelegate?

    let contactsManager: OWSContactsManager

    @objc
    public required init(contactsManager: OWSContactsManager) {
        AssertIsOnMainThread()

        self.contactsManager = contactsManager

        super.init()
    }

    // MARK: Actions

    @objc
    public func sendMessage(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("")

        presentThreadAndPeform(action: .compose, contactShare: contactShare, fromViewController: fromViewController)
    }

    @objc
    public func audioCall(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("")

        presentThreadAndPeform(action: .audioCall, contactShare: contactShare, fromViewController: fromViewController)
    }

    @objc
    public func videoCall(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("")

        presentThreadAndPeform(action: .videoCall, contactShare: contactShare, fromViewController: fromViewController)
    }

    private func presentThreadAndPeform(action: ConversationViewAction, contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        // TODO: We're taking the first Signal account id. We might
        // want to let the user select if there's more than one.
        let phoneNumbers = contactShare.systemContactsWithSignalAccountPhoneNumbers(contactsManager)
        guard phoneNumbers.count > 0 else {
            owsFailDebug("missing Signal recipient id.")
            return
        }
        guard phoneNumbers.count > 1 else {
            let recipientId = phoneNumbers.first!
            SignalApp.shared().presentConversation(forRecipientId: recipientId, action: action, animated: true)
            return
        }

        showPhoneNumberPicker(phoneNumbers: phoneNumbers, fromViewController: fromViewController, completion: { (recipientId) in
            SignalApp.shared().presentConversation(forRecipientId: recipientId, action: action, animated: true)
        })
    }

    @objc
    public func showInviteContact(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("")

        guard MFMessageComposeViewController.canSendText() else {
            Logger.info("Device cannot send text")
            OWSAlerts.showErrorAlert(message: NSLocalizedString("UNSUPPORTED_FEATURE_ERROR", comment: ""))
            return
        }
        let phoneNumbers = contactShare.e164PhoneNumbers()
        guard phoneNumbers.count > 0 else {
            owsFailDebug("no phone numbers.")
            return
        }

        let inviteFlow =
            InviteFlow(presentingViewController: fromViewController, contactsManager: contactsManager)
        inviteFlow.sendSMSTo(phoneNumbers: phoneNumbers)
    }

    @objc
    func showAddToContacts(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("")

        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("CONVERSATION_SETTINGS_NEW_CONTACT",
                                                                     comment: "Label for 'new contact' button in conversation settings view."),
                                            style: .default) { _ in
                                                self.didPressCreateNewContact(contactShare: contactShare, fromViewController: fromViewController)
        })
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("CONVERSATION_SETTINGS_ADD_TO_EXISTING_CONTACT",
                                                                     comment: "Label for 'new contact' button in conversation settings view."),
                                            style: .default) { _ in
                                                self.didPressAddToExistingContact(contactShare: contactShare, fromViewController: fromViewController)
        })
        actionSheet.addAction(OWSAlerts.cancelAction)

        fromViewController.present(actionSheet, animated: true)
    }

    private func showPhoneNumberPicker(phoneNumbers: [String], fromViewController: UIViewController, completion :@escaping ((String) -> Void)) {

        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        for phoneNumber in phoneNumbers {
            actionSheet.addAction(UIAlertAction(title: PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: phoneNumber),
                                                          style: .default) { _ in
                                                            completion(phoneNumber)
            })
        }
        actionSheet.addAction(OWSAlerts.cancelAction)

        fromViewController.present(actionSheet, animated: true)
    }

    func didPressCreateNewContact(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("")

        presentNewContactView(contactShare: contactShare, fromViewController: fromViewController)
    }

    func didPressAddToExistingContact(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("")

        presentSelectAddToExistingContactView(contactShare: contactShare, fromViewController: fromViewController)
    }

    // MARK: -

    private func presentNewContactView(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        guard contactsManager.supportsContactEditing else {
            owsFailDebug("Contact editing not supported")
            return
        }

        guard let systemContact = OWSContacts.systemContact(for: contactShare.dbRecord, imageData: contactShare.avatarImageData) else {
            owsFailDebug("Could not derive system contact.")
            return
        }

        guard contactsManager.isSystemContactsAuthorized else {
            ContactsViewHelper.presentMissingContactAccessAlertController(from: fromViewController)
            return
        }

        let contactViewController = CNContactViewController(forNewContact: systemContact)
        contactViewController.delegate = self
        contactViewController.allowsActions = false
        contactViewController.allowsEditing = true
        contactViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(title: CommonStrings.cancelButton,
                                                                                 style: .plain,
                                                                                 target: self,
                                                                                 action: #selector(didFinishEditingContact))

        let modal = OWSNavigationController(rootViewController: contactViewController)
        fromViewController.present(modal, animated: true)
    }

    private func presentSelectAddToExistingContactView(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        guard contactsManager.supportsContactEditing else {
            owsFailDebug("Contact editing not supported")
            return
        }

        guard contactsManager.isSystemContactsAuthorized else {
            ContactsViewHelper.presentMissingContactAccessAlertController(from: fromViewController)
            return
        }

        guard let navigationController = fromViewController.navigationController else {
            owsFailDebug("missing navigationController")
            return
        }

        let viewController = AddContactShareToExistingContactViewController(contactShare: contactShare)
        navigationController.pushViewController(viewController, animated: true)
    }

    // MARK: - CNContactViewControllerDelegate

    @objc public func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        Logger.info("")

        guard let delegate = delegate else {
            owsFailDebug("missing delegate")
            return
        }

        delegate.didCreateOrEditContact()
    }

    @objc public func didFinishEditingContact() {
        Logger.info("")

        guard let delegate = delegate else {
            owsFailDebug("missing delegate")
            return
        }

        delegate.didCreateOrEditContact()
    }
}
