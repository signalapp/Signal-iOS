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

    func sendMessage(contactShare: ContactShareViewModel, from viewController: UIViewController) {
        Logger.info("")

        presentThreadAndPeform(action: .compose, contactShare: contactShare, from: viewController)
    }

    func audioCall(contactShare: ContactShareViewModel, from viewController: UIViewController) {
        Logger.info("")

        presentThreadAndPeform(action: .audioCall, contactShare: contactShare, from: viewController)
    }

    func videoCall(contactShare: ContactShareViewModel, from viewController: UIViewController) {
        Logger.info("")

        presentThreadAndPeform(action: .videoCall, contactShare: contactShare, from: viewController)
    }

    private func presentThreadAndPeform(action: ConversationViewAction, contactShare: ContactShareViewModel, from viewController: UIViewController) {
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

        let completion: (String) -> Void = { phoneNumber in
            SignalApp.shared.presentConversationForAddress(
                SignalServiceAddress(phoneNumber: phoneNumber),
                action: action,
                animated: true
            )
        }
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

        viewController.presentActionSheet(actionSheet)
    }

    // MARK: Invite

    private var inviteFlow: InviteFlow?

    func showInviteContact(contactShare: ContactShareViewModel, from viewController: UIViewController) {
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

        let inviteFlow = InviteFlow(presentingViewController: viewController)
        self.inviteFlow = inviteFlow
        inviteFlow.sendSMSTo(phoneNumbers: phoneNumbers)
    }

    // MARK: Add to Contacts

    func showAddToContactsPrompt(contactShare: ContactShareViewModel, from viewController: UIViewController) {
        Logger.info("")

        let actionSheet = ActionSheetController(title: nil, message: nil)

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "CONVERSATION_SETTINGS_NEW_CONTACT",
                comment: "Label for 'new contact' button in conversation settings view."
            ),
            style: .default
        ) { _ in
            self.presentCreateNewContactFlow(contactShare: contactShare, from: viewController)
        })
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("CONVERSATION_SETTINGS_ADD_TO_EXISTING_CONTACT",
                                      comment: "Label for 'new contact' button in conversation settings view."
                                     ),
            style: .default
        ) { _ in
            self.presentAddToExistingContactFlow(contactShare: contactShare, from: viewController)
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)

        viewController.presentActionSheet(actionSheet)
    }

    private func presentCreateNewContactFlow(contactShare: ContactShareViewModel, from viewController: UIViewController) {
        Logger.info("")

        contactsViewHelper.checkEditAuthorization(
            performWhenAllowed: {
                let modalViewController = AddContactShareToContactsFlowNavigationController(
                    flow: .init(contactShare: contactShare, operation: .createNew),
                    completion: {
                        self.delegate?.didCreateOrEditContact()
                    }
                )
                viewController.present(modalViewController, animated: true)
            },
            presentErrorFrom: viewController
        )
    }

    private func presentAddToExistingContactFlow(contactShare: ContactShareViewModel, from viewController: UIViewController) {
        Logger.info("")

        contactsViewHelper.checkEditAuthorization(
            performWhenAllowed: {
                let modalViewController = AddContactShareToContactsFlowNavigationController(
                    flow: .init(contactShare: contactShare, operation: .addToExisting),
                    completion: {
                        self.delegate?.didCreateOrEditContact()
                    }
                )
                viewController.present(modalViewController, animated: true)
            },
            presentErrorFrom: viewController
        )
    }
}

private class AddContactShareToContactsFlow {
    enum Operation {
        case createNew
        case addToExisting
    }

    let contactShare: ContactShareViewModel
    let operation: Operation
    var existingContact: CNContact?

    init(contactShare: ContactShareViewModel, operation: Operation) {
        self.contactShare = contactShare
        self.operation = operation
    }

    func buildContact() -> CNContact {
        guard let newContact = contactShare.dbRecord.buildSystemContact(withImageData: contactShare.avatarImageData) else {
            owsFailDebug("Could not derive system contact.")
            return CNContact()
        }
        if let oldContact = existingContact {
            return Contact.merge(cnContact: oldContact, newCNContact: newContact)
        }
        return newContact
    }
}

private class AddContactShareToContactsFlowNavigationController: UINavigationController, CNContactViewControllerDelegate, ContactPickerDelegate {

    let flow: AddContactShareToContactsFlow
    let completion: (() -> Void)?

    init(flow: AddContactShareToContactsFlow, completion: (() -> Void)? = nil) {
        self.flow = flow
        self.completion = completion

        super.init(nibName: nil, bundle: nil)

        let rootViewController: UIViewController = {
            switch flow.operation {
            case .createNew:
                return buildContactViewController()

            case .addToExisting:
                let contactPicker = ContactPickerViewController(allowsMultipleSelection: false, subtitleCellType: .none)
                contactPicker.delegate = self
                return contactPicker
            }
        }()
        pushViewController(rootViewController, animated: false)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func buildContactViewController() -> CNContactViewController {
        let contactViewController = CNContactViewController(forNewContact: flow.buildContact())
        contactViewController.delegate = self
        contactViewController.allowsActions = false
        contactViewController.allowsEditing = true
        return contactViewController
    }

    // MARK: CNContactViewControllerDelegate

    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        dismiss(animated: true, completion: completion)
    }

    func contactViewController(_ viewController: CNContactViewController, shouldPerformDefaultActionFor property: CNContactProperty) -> Bool {
        return false
    }

    // MARK: ContactPickerDelegate

    func contactPickerDidCancel(_: ContactPickerViewController) {
        dismiss(animated: true, completion: completion)
    }

    func contactPicker(_ contactPicker: ContactPickerViewController, didSelect contact: Contact) {
        flow.existingContact = contactsManager.cnContact(withId: contact.cnContactId)
        // Note that CNContactViewController uses Cancel as the left bar button item (not the < back button).
        // Therefore to go back to contact picker CNContactViewControllerDelegate method above
        // would need to be modified to handle contact editing cancellation.
        let contactViewController = buildContactViewController()
        contactViewController.title = nil // Replace "New Contact" with an empty title.
        pushViewController(contactViewController, animated: true)
    }

    func contactPicker(_: ContactPickerViewController, didSelectMultiple contacts: [Contact]) {
        owsFailBeta("Invalid configuration")
    }

    func contactPicker(_: ContactPickerViewController, shouldSelect contact: Contact) -> Bool {
        true
    }
}
