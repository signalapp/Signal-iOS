//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import Social
import ContactsUI
import MessageUI
import SignalServiceKit

@objc(OWSInviteFlow)
class InviteFlow: NSObject, MFMessageComposeViewControllerDelegate, MFMailComposeViewControllerDelegate, ContactsPickerDelegate {
    private enum Channel {
        case message, mail, twitter
    }

    private let installUrl = "https://signal.org/install/"
    private let homepageUrl = "https://signal.org"

    private let actionSheetController: UIAlertController
    private let presentingViewController: UIViewController

    private var channel: Channel?

    @objc
    public required init(presentingViewController: UIViewController) {
        self.presentingViewController = presentingViewController
        actionSheetController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        super.init()

        actionSheetController.addAction(dismissAction())

        if let messageAction = messageAction() {
            actionSheetController.addAction(messageAction)
        }

        if let mailAction = mailAction() {
            actionSheetController.addAction(mailAction)
        }

        if let tweetAction = tweetAction() {
            actionSheetController.addAction(tweetAction)
        }
    }

    deinit {
        Logger.verbose("[InviteFlow] deinit")
    }

    // MARK: -

    @objc
    public func present(isAnimated: Bool, completion: (() -> Void)?) {
        // If actions include dismiss + more than one other action, show an interstitial action
        // sheet, othewise show the action directly.
        if actionSheetController.actions.count > 2 {
            presentingViewController.present(actionSheetController, animated: isAnimated, completion: completion)
        } else if messageAction() != nil {
            presentInviteViaSMSFlow()
        } else if mailAction() != nil {
            presentInviteViaMailFlow()
        } else if tweetAction() != nil {
            presentInviteViaTwitterFlow()
        }
    }

    // MARK: Twitter

    private func canTweet() -> Bool {
        return SLComposeViewController.isAvailable(forServiceType: SLServiceTypeTwitter)
    }

    private func tweetAction() -> UIAlertAction? {
        guard canTweet()  else {
            Logger.info("Twitter not supported.")
            return nil
        }

        let tweetTitle = NSLocalizedString("SHARE_ACTION_TWEET", comment: "action sheet item")
        return UIAlertAction(title: tweetTitle, style: .default) { _ in
            Logger.debug("Chose tweet")
            self.presentInviteViaTwitterFlow()
        }
    }

    private func presentInviteViaTwitterFlow() {
        guard let twitterViewController = SLComposeViewController(forServiceType: SLServiceTypeTwitter) else {
            owsFailDebug("twitterViewController was unexpectedly nil")
            return
        }

        let tweetString = NSLocalizedString("SETTINGS_INVITE_TWITTER_TEXT", comment: "content of tweet when inviting via twitter - please do not translate URL")
        twitterViewController.setInitialText(tweetString)

        let tweetUrl = URL(string: installUrl)
        twitterViewController.add(tweetUrl)
        twitterViewController.add(#imageLiteral(resourceName: "twitter_sharing_image"))
        self.presentingViewController.present(twitterViewController, animated: true, completion: nil)
    }

    private func dismissAction() -> UIAlertAction {
        return UIAlertAction(title: CommonStrings.dismissButton, style: .cancel)
    }

    // MARK: ContactsPickerDelegate

    func contactsPicker(_: ContactsPicker, didSelectMultipleContacts contacts: [Contact]) {
        Logger.debug("didSelectContacts:\(contacts)")

        guard let inviteChannel = channel else {
            Logger.error("unexpected nil channel after returning from contact picker.")
            self.presentingViewController.dismiss(animated: true)
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

    func contactsPicker(_: ContactsPicker, shouldSelectContact contact: Contact) -> Bool {
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

    func contactsPicker(_: ContactsPicker, contactFetchDidFail error: NSError) {
        Logger.error("with error: \(error)")
        self.presentingViewController.dismiss(animated: true) {
            OWSAlerts.showErrorAlert(message: NSLocalizedString("ERROR_COULD_NOT_FETCH_CONTACTS", comment: "Error indicating that the phone's contacts could not be retrieved."))
        }
    }

    func contactsPickerDidCancel(_: ContactsPicker) {
        Logger.debug("")
        self.presentingViewController.dismiss(animated: true)
    }

    func contactsPicker(_: ContactsPicker, didSelectContact contact: Contact) {
        owsFailDebug("InviteFlow only supports multi-select")
        self.presentingViewController.dismiss(animated: true)
    }

    // MARK: SMS

    private func messageAction() -> UIAlertAction? {
        guard MFMessageComposeViewController.canSendText() else {
            Logger.info("Device cannot send text")
            return nil
        }

        let messageTitle = NSLocalizedString("SHARE_ACTION_MESSAGE", comment: "action sheet item to open native messages app")
        return UIAlertAction(title: messageTitle, style: .default) { _ in
            Logger.debug("Chose message.")
            self.presentInviteViaSMSFlow()
        }
    }

    private func presentInviteViaSMSFlow() {
        self.channel = .message
        let picker = ContactsPicker(allowsMultipleSelection: true, subtitleCellType: .phoneNumber)
        picker.contactsPickerDelegate = self
        picker.title = NSLocalizedString("INVITE_FRIENDS_PICKER_TITLE", comment: "Navbar title")
        let navigationController = OWSNavigationController(rootViewController: picker)
        self.presentingViewController.present(navigationController, animated: true)
    }

    public func dismissAndSendSMSTo(phoneNumbers: [String]) {
        self.presentingViewController.dismiss(animated: true) {
            if phoneNumbers.count > 1 {
                let warning = UIAlertController(title: nil,
                                                message: NSLocalizedString("INVITE_WARNING_MULTIPLE_INVITES_BY_TEXT",
                                                                                       comment: "Alert warning that sending an invite to multiple users will create a group message whose recipients will be able to see each other."),
                                                preferredStyle: .alert)
                warning.addAction(UIAlertAction(title: NSLocalizedString("BUTTON_CONTINUE",
                                                                         comment: "Label for 'continue' button."),
                                                style: .default, handler: { _ in
                    self.sendSMSTo(phoneNumbers: phoneNumbers)
                }))
                warning.addAction(OWSAlerts.cancelAction)
                self.presentingViewController.presentAlert(warning)
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

        let inviteText = NSLocalizedString("SMS_INVITE_BODY", comment: "body sent to contacts when inviting to Install Signal")
        messageComposeViewController.body = inviteText.appending(" \(self.installUrl)")
        self.presentingViewController.present(messageComposeViewController, animated: true)
    }

    // MARK: MessageComposeViewControllerDelegate

    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        self.presentingViewController.dismiss(animated: true) {
            switch result {
            case .failed:
                let warning = UIAlertController(title: nil, message: NSLocalizedString("SEND_INVITE_FAILURE", comment: "Alert body after invite failed"), preferredStyle: .alert)
                warning.addAction(UIAlertAction(title: CommonStrings.dismissButton, style: .default, handler: nil))
                self.presentingViewController.present(warning, animated: true, completion: nil)
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

    private func mailAction() -> UIAlertAction? {
        guard MFMailComposeViewController.canSendMail() else {
            Logger.info("Device cannot send mail")
            return nil
        }

        let mailActionTitle = NSLocalizedString("SHARE_ACTION_MAIL", comment: "action sheet item to open native mail app")
        return UIAlertAction(title: mailActionTitle, style: .default) { _ in
            Logger.debug("Chose mail.")
            self.presentInviteViaMailFlow()
        }
    }

    private func presentInviteViaMailFlow() {
        self.channel = .mail

        let picker = ContactsPicker(allowsMultipleSelection: true, subtitleCellType: .email)
        picker.contactsPickerDelegate = self
        picker.title = NSLocalizedString("INVITE_FRIENDS_PICKER_TITLE", comment: "Navbar title")
        let navigationController = OWSNavigationController(rootViewController: picker)
        self.presentingViewController.present(navigationController, animated: true)
    }

    private func sendMailTo(emails recipientEmails: [String]) {
        let mailComposeViewController = MFMailComposeViewController()
        mailComposeViewController.mailComposeDelegate = self
        mailComposeViewController.setBccRecipients(recipientEmails)

        let subject = NSLocalizedString("EMAIL_INVITE_SUBJECT", comment: "subject of email sent to contacts when inviting to install Signal")
        let bodyFormat = NSLocalizedString("EMAIL_INVITE_BODY", comment: "body of email sent to contacts when inviting to install Signal. Embeds {{link to install Signal}} and {{link to the Signal home page}}")
        let body = String.init(format: bodyFormat, installUrl, homepageUrl)
        mailComposeViewController.setSubject(subject)
        mailComposeViewController.setMessageBody(body, isHTML: false)

        self.presentingViewController.dismiss(animated: true) {
            self.presentingViewController.present(mailComposeViewController, animated: true)
        }
    }

    // MARK: MailComposeViewControllerDelegate

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        self.presentingViewController.dismiss(animated: true) {
            switch result {
            case .failed:
                let warning = UIAlertController(title: nil, message: NSLocalizedString("SEND_INVITE_FAILURE", comment: "Alert body after invite failed"), preferredStyle: .alert)
                warning.addAction(UIAlertAction(title: CommonStrings.dismissButton, style: .default, handler: nil))
                self.presentingViewController.present(warning, animated: true, completion: nil)
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
