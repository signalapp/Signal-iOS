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

    weak var delegate: ContactShareViewHelperDelegate?

    let contactShare: ContactShareViewModel
    let contactsManager: OWSContactsManager
    weak var fromViewController: UIViewController?

    public required init(contactShare: ContactShareViewModel, contactsManager: OWSContactsManager, fromViewController: UIViewController, delegate: ContactShareViewHelperDelegate) {
        SwiftAssertIsOnMainThread(#function)

        self.contactShare = contactShare
        self.contactsManager = contactsManager
        self.fromViewController = fromViewController
        self.delegate = delegate

        super.init()
    }

    // MARK: Actions

    @objc
    public func sendMessageToContact() {
        Logger.info("\(logTag) \(#function)")

        presentThreadAndPeform(action: .compose)
    }

    @objc
    public func audioCallToContact() {
        Logger.info("\(logTag) \(#function)")

        presentThreadAndPeform(action: .audioCall)
    }

    @objc
    public func videoCallToContact() {
        Logger.info("\(logTag) \(#function)")

        presentThreadAndPeform(action: .videoCall)
    }

    private func presentThreadAndPeform(action: ConversationViewAction) {
        // TODO: We're taking the first Signal account id. We might
        // want to let the user select if there's more than one.
        let phoneNumbers = contactShare.systemContactsWithSignalAccountPhoneNumbers(contactsManager)
        guard phoneNumbers.count > 0 else {
            owsFail("\(logTag) missing Signal recipient id.")
            return
        }
        guard phoneNumbers.count > 1 else {
            let recipientId = phoneNumbers.first!
            SignalApp.shared().presentConversation(forRecipientId: recipientId, action: action)
            return
        }

        showPhoneNumberPicker(phoneNumbers: phoneNumbers, completion: { (recipientId) in
            SignalApp.shared().presentConversation(forRecipientId: recipientId, action: action)
        })
    }

    @objc
    public func inviteContact() {
        Logger.info("\(logTag) \(#function)")

        guard let fromViewController = fromViewController else {
            owsFail("\(logTag) missing fromViewController")
            return
        }

        guard MFMessageComposeViewController.canSendText() else {
            Logger.info("\(logTag) Device cannot send text")
            OWSAlerts.showErrorAlert(message: NSLocalizedString("UNSUPPORTED_FEATURE_ERROR", comment: ""))
            return
        }
        let phoneNumbers = contactShare.e164PhoneNumbers()
        guard phoneNumbers.count > 0 else {
            owsFail("\(logTag) no phone numbers.")
            return
        }

        let inviteFlow =
            InviteFlow(presentingViewController: fromViewController, contactsManager: contactsManager)
        inviteFlow.sendSMSTo(phoneNumbers: phoneNumbers)
    }

    func addToContacts() {
        Logger.info("\(logTag) \(#function)")

        guard let fromViewController = fromViewController else {
            owsFail("\(logTag) missing fromViewController")
            return
        }

        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("CONVERSATION_SETTINGS_NEW_CONTACT",
                                                                     comment: "Label for 'new contact' button in conversation settings view."),
                                            style: .default) { _ in
                                                self.didPressCreateNewContact()
        })
        actionSheet.addAction(UIAlertAction(title: NSLocalizedString("CONVERSATION_SETTINGS_ADD_TO_EXISTING_CONTACT",
                                                                     comment: "Label for 'new contact' button in conversation settings view."),
                                            style: .default) { _ in
                                                self.didPressAddToExistingContact()
        })
        actionSheet.addAction(OWSAlerts.cancelAction)

        fromViewController.present(actionSheet, animated: true)
    }

    private func showPhoneNumberPicker(phoneNumbers: [String], completion :@escaping ((String) -> Void)) {

        guard let fromViewController = fromViewController else {
            owsFail("\(logTag) missing fromViewController")
            return
        }

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

    func didPressCreateNewContact() {
        Logger.info("\(logTag) \(#function)")

        presentNewContactView()
    }

    func didPressAddToExistingContact() {
        Logger.info("\(logTag) \(#function)")

        presentSelectAddToExistingContactView()
    }

    // MARK: -

    private func presentNewContactView() {

        guard let fromViewController = fromViewController else {
            owsFail("\(logTag) missing fromViewController")
            return
        }

        guard contactsManager.supportsContactEditing else {
            owsFail("\(logTag) Contact editing not supported")
            return
        }

        guard let systemContact = OWSContacts.systemContact(for: contactShare.dbRecord) else {
            owsFail("\(logTag) Could not derive system contact.")
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
        contactViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(title: CommonStrings.cancelButton, style: .plain, target: self, action: #selector(didFinishEditingContact))
        contactViewController.navigationItem.leftBarButtonItem = UIBarButtonItem(title: CommonStrings.cancelButton,
                                                                                 style: .plain,
                                                                                 target: self,
                                                                                 action: #selector(didFinishEditingContact))

        guard let navigationController = fromViewController.navigationController else {
            owsFail("\(logTag) missing navigationController")
            return
        }

        navigationController.pushViewController(contactViewController, animated: true)

        // HACK otherwise CNContactViewController Navbar is shown as black.
        // RADAR rdar://28433898 http://www.openradar.me/28433898
        // CNContactViewController incompatible with opaque navigation bar
        UIUtil.applyDefaultSystemAppearence()
    }

    private func presentSelectAddToExistingContactView() {

        guard let fromViewController = fromViewController else {
            owsFail("\(logTag) missing fromViewController")
            return
        }

        guard contactsManager.supportsContactEditing else {
            owsFail("\(logTag) Contact editing not supported")
            return
        }

        guard contactsManager.isSystemContactsAuthorized else {
            ContactsViewHelper.presentMissingContactAccessAlertController(from: fromViewController)
            return
        }

        // TODO: Revisit this.
        guard let firstPhoneNumber = contactShare.e164PhoneNumbers().first else {
            owsFail("\(logTag) Missing phone number.")
            return
        }

        // TODO: We need to modify OWSAddToContactViewController to take a OWSContact
        // and merge it with an existing CNContact.
        let viewController = OWSAddToContactViewController()
        viewController.configure(withRecipientId: firstPhoneNumber)

        guard let navigationController = fromViewController.navigationController else {
            owsFail("\(logTag) missing navigationController")
            return
        }

        navigationController.pushViewController(viewController, animated: true)
    }

    // MARK: - CNContactViewControllerDelegate

    @objc public func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        Logger.info("\(logTag) \(#function)")

        guard let fromViewController = fromViewController else {
            owsFail("\(logTag) missing fromViewController")
            return
        }

        guard let navigationController = fromViewController.navigationController else {
            owsFail("\(logTag) missing navigationController")
            return
        }

        guard let delegate = delegate else {
            owsFail("\(logTag) missing delegate")
            return
        }

        navigationController.popToViewController(fromViewController, animated: true)

        delegate.didCreateOrEditContact()
    }

    @objc public func didFinishEditingContact() {
        Logger.info("\(logTag) \(#function)")

        guard let fromViewController = fromViewController else {
            owsFail("\(logTag) missing fromViewController")
            return
        }

        guard let navigationController = fromViewController.navigationController else {
            owsFail("\(logTag) missing navigationController")
            return
        }

        guard let delegate = delegate else {
            owsFail("\(logTag) missing delegate")
            return
        }

        navigationController.popToViewController(fromViewController, animated: true)

        delegate.didCreateOrEditContact()
    }
}
