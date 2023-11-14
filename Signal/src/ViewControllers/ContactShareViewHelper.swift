//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import ContactsUI
import MessageUI
import SignalMessaging
import SignalServiceKit
import SignalUI

protocol ContactShareViewHelperDelegate: AnyObject {
    func didCreateOrEditContact()
}

// MARK: -

class ContactShareViewHelper: NSObject, CNContactViewControllerDelegate {

    weak var delegate: ContactShareViewHelperDelegate?

    required override init() {
        AssertIsOnMainThread()

        super.init()
    }

    // MARK: Actions

    func sendMessage(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("")

        presentThreadAndPeform(action: .compose, contactShare: contactShare, fromViewController: fromViewController)
    }

    func audioCall(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("")

        presentThreadAndPeform(action: .audioCall, contactShare: contactShare, fromViewController: fromViewController)
    }

    func videoCall(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
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
            SignalApp.shared.presentConversationForAddress(address, action: action, animated: true)
            return
        }

        showPhoneNumberPicker(phoneNumbers: phoneNumbers, fromViewController: fromViewController, completion: { phoneNumber in
            SignalApp.shared.presentConversationForAddress(SignalServiceAddress(phoneNumber: phoneNumber), action: action, animated: true)
        })
    }

    private var inviteFlow: InviteFlow?

    func showInviteContact(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
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

    func showAddToContacts(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        Logger.info("")

        let actionSheet = ActionSheetController(title: nil, message: nil)

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "CONVERSATION_SETTINGS_NEW_CONTACT",
                comment: "Label for 'new contact' button in conversation settings view."
            ),
            style: .default
        ) { _ in
            self.didPressCreateNewContact(contactShare: contactShare, fromViewController: fromViewController)
        })
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("CONVERSATION_SETTINGS_ADD_TO_EXISTING_CONTACT",
                                      comment: "Label for 'new contact' button in conversation settings view."
                                     ),
            style: .default
        ) { _ in
            self.didPressAddToExistingContact(contactShare: contactShare, fromViewController: fromViewController)
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)

        fromViewController.presentActionSheet(actionSheet)
    }

    private func showPhoneNumberPicker(phoneNumbers: [String], fromViewController: UIViewController, completion: @escaping ((String) -> Void)) {

        let actionSheet = ActionSheetController(title: nil, message: nil)

        for phoneNumber in phoneNumbers {
            actionSheet.addAction(ActionSheetAction(
                title: PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: phoneNumber),
                style: .default
            ) { _ in
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
        contactsViewHelper.checkEditingAuthorization(
            authorizedBehavior: .runAction({
                guard let systemContact = contactShare.dbRecord.buildSystemContact(withImageData: contactShare.avatarImageData) else {
                    owsFailDebug("Could not derive system contact.")
                    return
                }
                let contactViewController = CNContactViewController(forNewContact: systemContact)
                contactViewController.delegate = self
                contactViewController.allowsActions = false
                contactViewController.allowsEditing = true
                contactViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
                    title: CommonStrings.cancelButton,
                    style: .plain,
                    target: self,
                    action: #selector(self.didFinishEditingContact)
                )
                let modal = OWSNavigationController(rootViewController: contactViewController)
                fromViewController.present(modal, animated: true)
            }),
            unauthorizedBehavior: .presentError(from: fromViewController)
        )
    }

    private func presentSelectAddToExistingContactView(contactShare: ContactShareViewModel, fromViewController: UIViewController) {
        guard let navigationController = fromViewController.navigationController else {
            return owsFailDebug("Missing navigationController.")
        }
        contactsViewHelper.checkEditingAuthorization(
            authorizedBehavior: .pushViewController(on: navigationController, viewController: {
                AddContactShareToExistingContactViewController(contactShare: contactShare)
            }),
            unauthorizedBehavior: .presentError(from: fromViewController)
        )
    }

    // MARK: - CNContactViewControllerDelegate

    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        Logger.info("")

        guard let delegate else {
            owsFailDebug("missing delegate")
            return
        }

        delegate.didCreateOrEditContact()
    }

    @objc
    private func didFinishEditingContact() {
        Logger.info("")

        guard let delegate else {
            owsFailDebug("missing delegate")
            return
        }

        delegate.didCreateOrEditContact()
    }
}
