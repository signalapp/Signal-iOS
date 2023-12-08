//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import ContactsUI
import SignalServiceKit
import SignalUI

protocol SystemContactsFlow {
    var address: SignalServiceAddress { get }
    var editImmediately: Bool { get }
    var nameComponents: PersonNameComponents? { get }
    var contact: CNContact? { get }
}

class CreateOrEditContactFlow: SystemContactsFlow {
    let address: SignalServiceAddress
    let editImmediately: Bool
    let nameComponents: PersonNameComponents?
    let contact: CNContact?

    init(
        address: SignalServiceAddress,
        contact: CNContact? = nil,
        editImmediately: Bool = true,
        nameComponents: PersonNameComponents? = nil
    ) {
        self.address = address
        self.contact = contact
        self.editImmediately = editImmediately
        self.nameComponents = nameComponents
    }
}

class AddToExistingContactFlow: SystemContactsFlow {
    let address: SignalServiceAddress
    var editImmediately: Bool { true }
    let nameComponents: PersonNameComponents?
    var contact: CNContact?

    init(address: SignalServiceAddress, nameComponents: PersonNameComponents? = nil) {
        self.address = address
        self.nameComponents = nameComponents
    }
}

private class AddToContactsFlowNavigationController: UINavigationController, CNContactViewControllerDelegate, ContactPickerDelegate {

    let flow: SystemContactsFlow
    var completion: (() -> Void)?

    init(flow: SystemContactsFlow, completion: (() -> Void)? = nil) {
        self.flow = flow
        self.completion = completion

        super.init(nibName: nil, bundle: nil)

        switch flow {
        case is CreateOrEditContactFlow:
            let contactViewController = contactsViewHelper.contactViewController(for: flow)
            // CNContactViewController doesn't provide a Cancel button unless in editing mode.
            if !flow.editImmediately {
                contactViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
                    barButtonSystemItem: .cancel,
                    target: self,
                    action: #selector(cancelButtonTapped(sender:))
                )
            }
            pushViewController(contactViewController, animated: false)
        case is AddToExistingContactFlow:
            let contactPicker = ContactPickerViewController(allowsMultipleSelection: false, subtitleCellType: .none)
            contactPicker.title = OWSLocalizedString("CONVERSATION_SETTINGS_ADD_TO_EXISTING_CONTACT", comment: "")
            pushViewController(contactPicker, animated: false)
        default:
            owsFailBeta("Invalid flow")
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        super.pushViewController(viewController, animated: animated)

        if let contactViewController = viewController as? CNContactViewController {
            contactViewController.delegate = self
        }
        if let contactPickerViewController = viewController as? ContactPickerViewController {
            contactPickerViewController.delegate = self
        }
    }

    @objc
    private func cancelButtonTapped(sender: Any) {
        dismiss(animated: true, completion: completion)
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
        guard let addToContactFlow = flow as? AddToExistingContactFlow else {
            owsFailBeta("Invalid flow.")
            return
        }
        addToContactFlow.contact = contactsManager.cnContact(withId: contact.cnContactId)
        let contactViewController = contactsViewHelper.contactViewController(for: addToContactFlow)
        pushViewController(contactViewController, animated: true)
    }

    func contactPicker(_: ContactPickerViewController, didSelectMultiple contacts: [Contact]) {
        owsFailBeta("Invalid configuration")
    }

    func contactPicker(_: ContactPickerViewController, shouldSelect contact: Contact) -> Bool {
        true
    }
}

// MARK: Presenting System Contact Editing UI

extension ContactsViewHelper {

    func presentSystemContactsFlow(
        _ flow: SystemContactsFlow,
        from viewController: UIViewController,
        completion: (() -> Void)? = nil
    ) {
        checkEditAuthorization(
            authorizedBehavior: .runAction({
                let flowNavigationController = AddToContactsFlowNavigationController(flow: flow)
                flowNavigationController.completion = completion
                viewController.present(flowNavigationController, animated: true)
            }),
            unauthorizedBehavior: .presentError(from: viewController)
        )
    }

    fileprivate func contactViewController(for systemContactsFlow: SystemContactsFlow) -> CNContactViewController {
        AssertIsOnMainThread()
        owsAssertDebug(!CurrentAppContext().isNSE)
        owsAssertDebug(contactsManagerImpl.editingAuthorization == .authorized)

        let address = systemContactsFlow.address
        let signalAccount = fetchSignalAccount(for: address)
        var shouldEditImmediately = systemContactsFlow.editImmediately

        var contactViewController: CNContactViewController?
        var cnContact: CNContact?

        if let existingContact = systemContactsFlow.contact {
            // Only add recipientId as a phone number for the existing contact if its not already present.
            if let phoneNumber = address.phoneNumber {
                let phoneNumberExists = existingContact.phoneNumbers.contains {
                    phoneNumber == $0.value.stringValue
                }

                owsAssertBeta(!phoneNumberExists, "We currently only should the 'add to existing contact' UI for phone numbers that don't correspond to an existing user.")

                if !phoneNumberExists {
                    var phoneNumbers = existingContact.phoneNumbers
                    phoneNumbers.append(CNLabeledValue(
                        label: CNLabelPhoneNumberMain,
                        value: CNPhoneNumber(stringValue: phoneNumber)
                    ))
                    let updatedContact = existingContact.mutableCopy() as! CNMutableContact
                    updatedContact.phoneNumbers = phoneNumbers
                    cnContact = updatedContact

                    // When adding a phone number to an existing contact, immediately enter "edit" mode.
                    shouldEditImmediately = true
                }

            }
        }

        if cnContact == nil, let cnContactId = signalAccount?.contact?.cnContactId {
            cnContact = contactsManager.cnContact(withId: cnContactId)
        }

        if let updatedContact = cnContact?.mutableCopy() as? CNMutableContact {
            if let givenName = systemContactsFlow.nameComponents?.givenName {
                updatedContact.givenName = givenName
            }
            if let familyName = systemContactsFlow.nameComponents?.familyName {
                updatedContact.familyName = familyName
            }

            if shouldEditImmediately {
                // Not actually a "new" contact, but this brings up the edit form rather than the "Read" form
                // saving our users a tap in some cases when we already know they want to edit.
                contactViewController = CNContactViewController(forNewContact: updatedContact)

                // Default title is "New Contact". We could give a more descriptive title, but anything
                // seems redundant - the context is sufficiently clear.
                contactViewController?.title = ""
            } else {
                contactViewController = CNContactViewController(for: updatedContact)
            }
        }

        if contactViewController == nil {
            let newContact = CNMutableContact()
            if let phoneNumber = address.phoneNumber {
                newContact.phoneNumbers = [ CNLabeledValue(
                    label: CNLabelPhoneNumberMain,
                    value: CNPhoneNumber(stringValue: phoneNumber)
                )]
            }

            databaseStorage.read { tx in
                if let givenName = profileManagerImpl.givenName(for: address, transaction: tx) {
                    newContact.givenName = givenName
                }
                if let familyName = profileManagerImpl.familyName(for: address, transaction: tx) {
                    newContact.familyName = familyName
                }
                if let profileAvatar = profileManagerImpl.profileAvatar(
                    for: address,
                    downloadIfMissing: true,
                    authedAccount: .implicit(),
                    transaction: tx
                ) {
                    newContact.imageData = profileAvatar.pngData()
                }
            }

            if let givenName = systemContactsFlow.nameComponents?.givenName {
                newContact.givenName = givenName
            }
            if let familyName = systemContactsFlow.nameComponents?.familyName {
                newContact.familyName = familyName
            }
            contactViewController = CNContactViewController(forNewContact: newContact)
        }

        contactViewController?.allowsActions = false
        contactViewController?.allowsEditing = true

        return contactViewController!
    }
}
