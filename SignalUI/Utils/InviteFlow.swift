//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import ContactsUI
import Foundation
import MessageUI
import SignalMessaging
import SignalServiceKit

public class InviteFlow: NSObject {
    private enum Channel {
        case message, mail

        var actionTitle: String {
            switch self {
            case .message:
                return OWSLocalizedString("SHARE_ACTION_MESSAGE", comment: "action sheet item to open native messages app")
            case .mail:
                return OWSLocalizedString("SHARE_ACTION_MAIL", comment: "action sheet item to open native mail app")
            }
        }

        var cellSubtitleType: SubtitleCellValue {
            switch self {
            case .message:
                return .phoneNumber
            case .mail:
                return .email
            }
        }
    }

    private let installUrl = "https://signal.org/install/"
    private let homepageUrl = "https://signal.org"

    private weak var presentingViewController: UIViewController?
    private var modalPresentationViewController: UIViewController?

    private var channel: Channel?

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

    public func present(isAnimated: Bool, completion: (() -> Void)?) {
        let channels = [messageChannel(), mailChannel()].compacted()
        if channels.count > 1 {
            let actionSheetController = ActionSheetController(title: nil, message: nil)
            actionSheetController.addAction(OWSActionSheets.dismissAction)
            for channel in channels {
                actionSheetController.addAction(ActionSheetAction(title: channel.actionTitle, style: .default) { [weak self] _ in
                    self?.presentInviteFlow(channel: channel)
                })
            }
            presentingViewController?.present(actionSheetController, animated: isAnimated, completion: completion)
        } else if let supportedChannel = channels.first {
            presentInviteFlow(channel: supportedChannel)
        }
    }

    private func presentViewController(_ vc: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        let navController = OWSNavigationController(rootViewController: vc)
        presentingViewController?.presentFormSheet(navController, animated: true)
        modalPresentationViewController = navController
    }

    private func popToPresentingViewController(animated: Bool, completion: (() -> Void)? = nil) {
        guard let modalVC = modalPresentationViewController else {
            owsFailDebug("Missing modal view controller")
            return
        }
        modalVC.dismiss(animated: true, completion: completion)
        self.modalPresentationViewController = nil
    }

    // MARK: SMS

    private func messageChannel() -> Channel? {
        guard MFMessageComposeViewController.canSendText() else {
            Logger.info("Device cannot send text")
            return nil
        }
        return .message
    }

    private func presentInviteFlow(channel: Channel) {
        guard let presentingViewController else { return }

        self.channel = channel
        contactsViewHelper.checkSharingAuthorization(
            purpose: .invite,
            authorizedBehavior: .runAction({
                let picker = ContactPickerViewController(allowsMultipleSelection: true, subtitleCellType: channel.cellSubtitleType)
                picker.delegate = self
                picker.title = OWSLocalizedString("INVITE_FRIENDS_PICKER_TITLE", comment: "Navbar title")
                self.presentViewController(picker, animated: true)
            }),
            unauthorizedBehavior: .presentError(from: presentingViewController)
        )
    }

    private func dismissAndSendSMSTo(phoneNumbers: [String]) {
        popToPresentingViewController(animated: true) {
            if phoneNumbers.count > 1 {
                let warning = ActionSheetController(
                    title: nil,
                    message: OWSLocalizedString(
                        "INVITE_WARNING_MULTIPLE_INVITES_BY_TEXT",
                        comment: "Alert warning that sending an invite to multiple users will create a group message whose recipients will be able to see each other."
                    )
                )
                warning.addAction(ActionSheetAction(
                    title: CommonStrings.continueButton,
                    style: .default,
                    handler: { [weak self] _ in
                        self?.sendSMSTo(phoneNumbers: phoneNumbers)
                    }
                ))
                warning.addAction(OWSActionSheets.cancelAction)

                self.presentingViewController?.presentActionSheet(warning)
            } else {
                self.sendSMSTo(phoneNumbers: phoneNumbers)
            }
        }
    }

    public func sendSMSTo(phoneNumbers: [String]) {
        let messageComposeViewController = MFMessageComposeViewController()
        messageComposeViewController.messageComposeDelegate = self
        messageComposeViewController.recipients = phoneNumbers

        let inviteText = OWSLocalizedString("SMS_INVITE_BODY", comment: "body sent to contacts when inviting to Install Signal")
        messageComposeViewController.body = inviteText.appending(" \(self.installUrl)")
        presentingViewController?.present(messageComposeViewController, animated: true)
    }

    // MARK: Mail

    private func mailChannel() -> Channel? {
        guard MFMailComposeViewController.canSendMail() else {
            Logger.info("Device cannot send mail")
            return nil
        }
        return .mail
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
}

extension InviteFlow: ContactPickerDelegate {

    public func contactPicker(_: ContactPickerViewController, didSelectMultiple contacts: [Contact]) {
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
        }
    }

    public func contactPicker(_: ContactPickerViewController, shouldSelect contact: Contact) -> Bool {
        guard let inviteChannel = channel else {
            Logger.error("unexpected nil channel in contact picker.")
            return true
        }

        switch inviteChannel {
        case .message:
            return contact.userTextPhoneNumbers.count > 0
        case .mail:
            return contact.emails.count > 0
        }
    }

    public func contactPickerDidCancel(_: ContactPickerViewController) {
        Logger.debug("")
        popToPresentingViewController(animated: true)
    }

    public func contactPicker(_: ContactPickerViewController, didSelect contact: Contact) {
        owsFailDebug("InviteFlow only supports multi-select")
        popToPresentingViewController(animated: true)
    }
}

extension InviteFlow: MFMessageComposeViewControllerDelegate {

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
}

extension InviteFlow: MFMailComposeViewControllerDelegate {

    public func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: Error?
    ) {
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
