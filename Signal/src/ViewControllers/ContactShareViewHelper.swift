//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import ContactsUI
import Foundation
import MessageUI
import SignalMessaging
import SignalServiceKit

@objc
public protocol ContactShareViewHelperDelegate: AnyObject {
    func didCreateOrEditContact()
}

// MARK: -

@objc
public class ContactShareViewHelper: NSObject, CNContactViewControllerDelegate {

    @objc
    weak var delegate: ContactShareViewHelperDelegate?

    @objc
    public required override init() {
        AssertIsOnMainThread()

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
        let phoneNumbers = contactShare.systemContactsWithSignalAccountPhoneNumbers()
        guard phoneNumbers.count > 0 else {
            owsFailDebug("missing Signal recipient id.")
            return
        }
        guard phoneNumbers.count > 1 else {
            let address = SignalServiceAddress(phoneNumber: phoneNumbers.first!)
            SignalApp.shared().presentConversation(for: address, action: action, animated: true)
            return
        }

        showPhoneNumberPicker(phoneNumbers: phoneNumbers, fromViewController: fromViewController, completion: { phoneNumber in
            SignalApp.shared().presentConversation(for: SignalServiceAddress(phoneNumber: phoneNumber), action: action, animated: true)
        })
    }

    private var inviteFlow: InviteFlow?

    @objc
    public func showInviteContact(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("")

        guard MFMessageComposeViewController.canSendText() else {
            Logger.info("Device cannot send text")
            OWSActionSheets.showErrorAlert(message: InviteFlow.unsupportedFeatureMessage)
            return
        }
        let phoneNumbers = contactShare.e164PhoneNumbers()
        guard phoneNumbers.count > 0 else {
            owsFailDebug("no phone numbers.")
            return
        }

        let inviteFlow = InviteFlow(presentingViewController: fromViewController)
        self.inviteFlow = inviteFlow
        inviteFlow.sendSMSTo(phoneNumbers: phoneNumbers)
    }

    @objc
    func showAddToContacts(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("")

        let actionSheet = ActionSheetController(title: nil, message: nil)

        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_NEW_CONTACT",
                                                                     comment: "Label for 'new contact' button in conversation settings view."),
                                            style: .default) { _ in
                                                self.didPressCreateNewContact(contactShare: contactShare, fromViewController: fromViewController)
        })
        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_ADD_TO_EXISTING_CONTACT",
                                                                     comment: "Label for 'new contact' button in conversation settings view."),
                                            style: .default) { _ in
                                                self.didPressAddToExistingContact(contactShare: contactShare, fromViewController: fromViewController)
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)

        fromViewController.presentActionSheet(actionSheet)
    }

    private func showPhoneNumberPicker(phoneNumbers: [String], fromViewController: UIViewController, completion: @escaping ((String) -> Void)) {

        let actionSheet = ActionSheetController(title: nil, message: nil)

        for phoneNumber in phoneNumbers {
            actionSheet.addAction(ActionSheetAction(title: PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: phoneNumber),
                                                          style: .default) { _ in
                                                            completion(phoneNumber)
            })
        }
        actionSheet.addAction(OWSActionSheets.cancelAction)

        fromViewController.presentActionSheet(actionSheet)
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
        guard contactsManagerImpl.supportsContactEditing else {
            owsFailDebug("Contact editing not supported")
            return
        }

        guard let systemContact = OWSContacts.systemContact(for: contactShare.dbRecord, imageData: contactShare.avatarImageData) else {
            owsFailDebug("Could not derive system contact.")
            return
        }

        guard contactsManagerImpl.isSystemContactsAuthorized else {
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
        guard contactsManagerImpl.supportsContactEditing else {
            owsFailDebug("Contact editing not supported")
            return
        }

        guard contactsManagerImpl.isSystemContactsAuthorized else {
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

    @objc
    public func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        Logger.info("")

        guard let delegate = delegate else {
            owsFailDebug("missing delegate")
            return
        }

        delegate.didCreateOrEditContact()
    }

    @objc
    public func didFinishEditingContact() {
        Logger.info("")

        guard let delegate = delegate else {
            owsFailDebug("missing delegate")
            return
        }

        delegate.didCreateOrEditContact()
    }
}
