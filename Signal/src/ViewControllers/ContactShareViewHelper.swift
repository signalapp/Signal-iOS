//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import ContactsUI
import MessageUI
import SignalServiceKit
import SignalUI

protocol ContactShareViewHelperDelegate: AnyObject {
    func didCreateOrEditContact()
}

// MARK: -

final class ContactShareViewHelper: NSObject, CNContactViewControllerDelegate {

    weak var delegate: ContactShareViewHelperDelegate?

    override init() {
        AssertIsOnMainThread()

        super.init()
    }

    // MARK: Actions

    func sendMessage(to phoneNumbers: [String], from viewController: UIViewController) {
        Logger.info("")

        presentThread(performAction: .compose, to: phoneNumbers, from: viewController)
    }

    func audioCall(to phoneNumbers: [String], from viewController: UIViewController) {
        Logger.info("")

        presentThread(performAction: .voiceCall, to: phoneNumbers, from: viewController)
    }

    func videoCall(to phoneNumbers: [String], from viewController: UIViewController) {
        Logger.info("")

        presentThread(performAction: .videoCall, to: phoneNumbers, from: viewController)
    }

    private func presentThread(
        performAction action: ConversationViewAction,
        to phoneNumbers: [String],
        from viewController: UIViewController
    ) {
        guard phoneNumbers.count > 0 else {
            owsFailDebug("No registered phone numbers.")
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
                title: PhoneNumber.bestEffortLocalizedPhoneNumber(e164: phoneNumber),
                style: .default
            ) { _ in
                completion(phoneNumber)
            })
        }
        actionSheet.addAction(OWSActionSheets.cancelAction)

        viewController.presentActionSheet(actionSheet)
    }

    // MARK: Invite

    func showInviteContact(contactShare: ContactShareViewModel, from viewController: UIViewController) {
        Logger.info("")

        guard MFMessageComposeViewController.canSendText() else {
            Logger.info("Device cannot send text")
            OWSActionSheets.showErrorAlert(message: InviteFlow.unsupportedFeatureMessage)
            return
        }
        let phoneNumbers = contactShare.dbRecord.e164PhoneNumbers()
        if phoneNumbers.isEmpty {
            owsFailDebug("no phone numbers.")
            return
        }

        let inviteFlow = InviteFlow(presentingViewController: viewController)
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

        SUIEnvironment.shared.contactsViewHelperRef.checkEditAuthorization(
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

        SUIEnvironment.shared.contactsViewHelperRef.checkEditAuthorization(
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

final private class AddContactShareToContactsFlow {
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
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            let phoneNumber = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber
            let canonicalPhoneNumber = E164(phoneNumber).map(CanonicalPhoneNumber.init(nonCanonicalPhoneNumber:))
            return mergeContact(newContact, into: oldContact, localPhoneNumber: canonicalPhoneNumber)
        }
        return newContact
    }

    private func mergeContact(
        _ newCNContact: CNContact,
        into oldCNContact: CNContact,
        localPhoneNumber: CanonicalPhoneNumber?
    ) -> CNContact {
        let oldContact = SystemContact(cnContact: oldCNContact)
        let mergedCNContact = oldCNContact.mutableCopy() as! CNMutableContact

        // Name (all or nothing -- no piecemeal merges)
        let formattedFullName = SystemContact.formattedFullName(for: mergedCNContact)

        if formattedFullName.isEmpty {
            mergedCNContact.namePrefix = newCNContact.namePrefix.stripped
            mergedCNContact.givenName = newCNContact.givenName.stripped
            mergedCNContact.nickname = newCNContact.nickname.stripped
            mergedCNContact.middleName = newCNContact.middleName.stripped
            mergedCNContact.familyName = newCNContact.familyName.stripped
            mergedCNContact.nameSuffix = newCNContact.nameSuffix.stripped
        }

        if mergedCNContact.organizationName.stripped.isEmpty {
            mergedCNContact.organizationName = newCNContact.organizationName.stripped
        }

        // Phone Numbers
        var existingUserTextPhoneNumbers = Set(oldContact.phoneNumbers.map { $0.value })
        var existingCanonicalPhoneNumbers = Set(FetchedSystemContacts.parsePhoneNumbers(
            for: oldContact,
            phoneNumberUtil: SSKEnvironment.shared.phoneNumberUtilRef,
            localPhoneNumber: localPhoneNumber
        ))
        var mergedPhoneNumbers = mergedCNContact.phoneNumbers
        for labeledPhoneNumber in newCNContact.phoneNumbers {
            let phoneNumber = labeledPhoneNumber.value.stringValue
            guard existingUserTextPhoneNumbers.insert(phoneNumber).inserted else {
                continue
            }
            let canonicalPhoneNumbers = FetchedSystemContacts.parsePhoneNumber(
                phoneNumber,
                phoneNumberUtil: SSKEnvironment.shared.phoneNumberUtilRef,
                localPhoneNumber: localPhoneNumber
            )
            guard existingCanonicalPhoneNumbers.isDisjoint(with: canonicalPhoneNumbers) else {
                continue
            }
            existingCanonicalPhoneNumbers.formUnion(canonicalPhoneNumbers)
            mergedPhoneNumbers.append(labeledPhoneNumber)
        }
        mergedCNContact.phoneNumbers = mergedPhoneNumbers

        // Emails
        var existingEmailAddresses = Set(oldContact.emailAddresses)
        var mergedEmailAddresses = mergedCNContact.emailAddresses
        for labeledEmailAddress in newCNContact.emailAddresses {
            let emailAddress = (labeledEmailAddress.value as String).ows_stripped()
            guard existingEmailAddresses.insert(emailAddress).inserted else {
                continue
            }
            mergedEmailAddresses.append(labeledEmailAddress)
        }
        mergedCNContact.emailAddresses = mergedEmailAddresses

        // Address (all or nothing -- no piecemeal merges)
        if mergedCNContact.postalAddresses.isEmpty {
            mergedCNContact.postalAddresses = newCNContact.postalAddresses
        }

        // Avatar
        if mergedCNContact.imageData == nil {
            mergedCNContact.imageData = newCNContact.imageData
        }

        return mergedCNContact.copy() as! CNContact
    }
}

final private class AddContactShareToContactsFlowNavigationController: UINavigationController, CNContactViewControllerDelegate, ContactPickerDelegate {

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

    func contactPicker(_ contactPicker: ContactPickerViewController, didSelect systemContact: SystemContact) {
        flow.existingContact = SSKEnvironment.shared.contactManagerRef.cnContact(withId: systemContact.cnContactId)
        // Note that CNContactViewController uses Cancel as the left bar button item (not the < back button).
        // Therefore to go back to contact picker CNContactViewControllerDelegate method above
        // would need to be modified to handle contact editing cancellation.
        let contactViewController = buildContactViewController()
        contactViewController.title = nil // Replace "New Contact" with an empty title.
        pushViewController(contactViewController, animated: true)
    }

    func contactPicker(_: ContactPickerViewController, didSelectMultiple systemContacts: [SystemContact]) {
        owsFailBeta("Invalid configuration")
    }

    func contactPicker(_: ContactPickerViewController, shouldSelect systemContact: SystemContact) -> Bool {
        true
    }
}
