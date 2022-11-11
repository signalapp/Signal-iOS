//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import ContactsUI
import Foundation
import MessageUI
import SignalMessaging
import SignalServiceKit

@objc(OWSInviteFlow)
public class InviteFlow: NSObject, MFMessageComposeViewControllerDelegate, MFMailComposeViewControllerDelegate, ContactsPickerDelegate {
    private enum Channel {
        case message, mail, twitter
    }

    private let installUrl = "https://signal.org/install/"
    private let homepageUrl = "https://signal.org"

    private weak var presentingViewController: UIViewController?
    private var modalPresentationViewController: UIViewController?

    private var channel: Channel?

    @objc
    public required init(presentingViewController: UIViewController) {
        self.presentingViewController = presentingViewController

        super.init()
    }

    deinit {
        Logger.verbose("deinit")
    }

    // MARK: - Localized Strings

    public static var unsupportedFeatureMessage: String {
        OWSLocalizedString(
            "UNSUPPORTED_FEATURE_ERROR",
            comment: "When inviting contacts to use Signal, this error is shown if the device doesn't support SMS or if there aren't any registered email accounts."
        )
    }

    // MARK: -

    @objc
    public func present(isAnimated: Bool, completion: (() -> Void)?) {
        let actions = [messageAction(), mailAction()].compactMap { $0 }
        if actions.count > 1 {
            let actionSheetController = ActionSheetController(title: nil, message: nil)
            actionSheetController.addAction(OWSActionSheets.dismissAction)
            for action in actions {
                actionSheetController.addAction(action)
            }
            presentingViewController?.present(actionSheetController, animated: isAnimated, completion: completion)
        } else if messageAction() != nil {
            presentInviteViaSMSFlow()
        } else if mailAction() != nil {
            presentInviteViaMailFlow()
        }
    }

    func presentViewController(_ vc: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        let navController = OWSNavigationController(rootViewController: vc)
        presentingViewController?.presentFormSheet(navController, animated: true)
        modalPresentationViewController = navController
    }

    func popToPresentingViewController(animated: Bool, completion: (() -> Void)? = nil) {
        guard let modalVC = modalPresentationViewController else {
            owsFailDebug("Missing modal view controller")
            return
        }
        modalVC.dismiss(animated: true, completion: completion)
        self.modalPresentationViewController = nil
    }

    // MARK: ContactsPickerDelegate

    public func contactsPicker(_: ContactsPicker, didSelectMultipleContacts contacts: [Contact]) {
        Logger.debug("didSelectContacts:\(contacts)")

        guard let inviteChannel = channel else {
            Logger.error("unexpected nil channel after returning from contact picker.")
            popToPresentingViewController(animated: true)
            return
        }

        switch inviteChannel {
        case .message:
            let phoneNumbers: [String] = contacts.map { $0.userTextPhoneNumbers.first }.filter { $0 != nil }.map { $0! }
            dismissAndSendSMSTo(phoneNumbers: phoneNumbers)
        case .mail:
            let recipients: [String] = contacts.map { $0.emails.first }.filter { $0 != nil }.map { $0! }
            sendMailTo(emails: recipients)
        default:
            Logger.error("unexpected channel after returning from contact picker: \(inviteChannel)")
        }
    }

    public func contactsPicker(_: ContactsPicker, shouldSelectContact contact: Contact) -> Bool {
        guard let inviteChannel = channel else {
            Logger.error("unexpected nil channel in contact picker.")
            return true
        }

        switch inviteChannel {
        case .message:
            return contact.userTextPhoneNumbers.count > 0
        case .mail:
            return contact.emails.count > 0
        default:
            Logger.error("unexpected channel after returning from contact picker: \(inviteChannel)")
        }
        return true
    }

    public func contactsPicker(_: ContactsPicker, contactFetchDidFail error: NSError) {
        Logger.error("with error: \(error)")
        popToPresentingViewController(animated: true) {
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString("ERROR_COULD_NOT_FETCH_CONTACTS", comment: "Error indicating that the phone's contacts could not be retrieved."))
        }
    }

    public func contactsPickerDidCancel(_: ContactsPicker) {
        Logger.debug("")
        popToPresentingViewController(animated: true)
    }

    public func contactsPicker(_: ContactsPicker, didSelectContact contact: Contact) {
        owsFailDebug("InviteFlow only supports multi-select")
        popToPresentingViewController(animated: true)
    }

    // MARK: SMS

    private func messageAction() -> ActionSheetAction? {
        guard MFMessageComposeViewController.canSendText() else {
            Logger.info("Device cannot send text")
            return nil
        }

        let messageTitle = OWSLocalizedString("SHARE_ACTION_MESSAGE", comment: "action sheet item to open native messages app")
        return ActionSheetAction(title: messageTitle, style: .default) { [weak self] _ in
            Logger.debug("Chose message.")
            self?.presentInviteViaSMSFlow()
        }
    }

    private func presentInviteViaSMSFlow() {
        self.channel = .message
        let picker = ContactsPicker(allowsMultipleSelection: true, subtitleCellType: .phoneNumber)
        picker.contactsPickerDelegate = self
        picker.title = OWSLocalizedString("INVITE_FRIENDS_PICKER_TITLE", comment: "Navbar title")

        presentViewController(picker, animated: true)
    }

    public func dismissAndSendSMSTo(phoneNumbers: [String]) {
        popToPresentingViewController(animated: true) {
            if phoneNumbers.count > 1 {
                let warning = ActionSheetController(title: nil,
                                                    message: OWSLocalizedString("INVITE_WARNING_MULTIPLE_INVITES_BY_TEXT",
                                                                                comment: "Alert warning that sending an invite to multiple users will create a group message whose recipients will be able to see each other."))
                warning.addAction(ActionSheetAction(title: CommonStrings.continueButton,
                                                style: .default, handler: { [weak self] _ in
                                                    self?.sendSMSTo(phoneNumbers: phoneNumbers)
                }))
                warning.addAction(OWSActionSheets.cancelAction)

                self.presentingViewController?.presentActionSheet(warning)
            } else {
                self.sendSMSTo(phoneNumbers: phoneNumbers)
            }
        }
    }

    @objc
    public func sendSMSTo(phoneNumbers: [String]) {
        let messageComposeViewController = MFMessageComposeViewController()
        messageComposeViewController.messageComposeDelegate = self
        messageComposeViewController.recipients = phoneNumbers

        let inviteText = OWSLocalizedString("SMS_INVITE_BODY", comment: "body sent to contacts when inviting to Install Signal")
        messageComposeViewController.body = inviteText.appending(" \(self.installUrl)")
        presentingViewController?.present(messageComposeViewController, animated: true)
    }

    // MARK: MessageComposeViewControllerDelegate

    public func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        presentingViewController?.dismiss(animated: true) {
            switch result {
            case .failed:
                let warning = ActionSheetController(title: nil, message: OWSLocalizedString("SEND_INVITE_FAILURE", comment: "Alert body after invite failed"))
                warning.addAction(OWSActionSheets.dismissAction)
                self.presentingViewController?.present(warning, animated: true, completion: nil)
            case .sent:
                Logger.debug("user successfully invited their friends via SMS.")
            case .cancelled:
                Logger.debug("user cancelled message invite")
            @unknown default:
                owsFailDebug("unknown MessageComposeResult: \(result)")
            }
        }
    }

    // MARK: Mail

    private func mailAction() -> ActionSheetAction? {
        guard MFMailComposeViewController.canSendMail() else {
            Logger.info("Device cannot send mail")
            return nil
        }

        let mailActionTitle = OWSLocalizedString("SHARE_ACTION_MAIL", comment: "action sheet item to open native mail app")
        return ActionSheetAction(title: mailActionTitle, style: .default) { [weak self] _ in
            Logger.debug("Chose mail.")
            self?.presentInviteViaMailFlow()
        }
    }

    private func presentInviteViaMailFlow() {
        self.channel = .mail

        let picker = ContactsPicker(allowsMultipleSelection: true, subtitleCellType: .email)
        picker.contactsPickerDelegate = self
        picker.title = OWSLocalizedString("INVITE_FRIENDS_PICKER_TITLE", comment: "Navbar title")

        presentViewController(picker, animated: true)
    }

    private func sendMailTo(emails recipientEmails: [String]) {
        let mailComposeViewController = MFMailComposeViewController()
        mailComposeViewController.mailComposeDelegate = self
        mailComposeViewController.setBccRecipients(recipientEmails)

        let subject = OWSLocalizedString("EMAIL_INVITE_SUBJECT", comment: "subject of email sent to contacts when inviting to install Signal")
        let bodyFormat = OWSLocalizedString("EMAIL_INVITE_BODY", comment: "body of email sent to contacts when inviting to install Signal. Embeds {{link to install Signal}} and {{link to the Signal home page}}")
        let body = String.init(format: bodyFormat, installUrl, homepageUrl)
        mailComposeViewController.setSubject(subject)
        mailComposeViewController.setMessageBody(body, isHTML: false)

        popToPresentingViewController(animated: true) {
            self.presentingViewController?.present(mailComposeViewController, animated: true)
        }
    }

    // MARK: MailComposeViewControllerDelegate

    public func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        presentingViewController?.dismiss(animated: true) {
            switch result {
            case .failed:
                let warning = ActionSheetController(title: nil, message: OWSLocalizedString("SEND_INVITE_FAILURE", comment: "Alert body after invite failed"))
                warning.addAction(OWSActionSheets.dismissAction)
                self.presentingViewController?.present(warning, animated: true, completion: nil)
            case .sent:
                Logger.debug("user successfully invited their friends via mail.")
            case .saved:
                Logger.debug("user saved mail invite.")
            case .cancelled:
                Logger.debug("user cancelled mail invite.")
            @unknown default:
                owsFailDebug("unknown MFMailComposeResult: \(result)")
            }
        }
    }

}
