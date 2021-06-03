//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import MessageUI

// This extension reproduces some of the UITextView link interaction behavior.
// This is how UITextView behaves:
//
// * URL
//   * tap - open URL in safari
//   * long press - preview + open link in safari / add to reading list / copy link / share
// * Event
//   * tap - like long press but action sheet
//   * long press - calendar preview + create event / create reminder / show in calendar / copy event
// * Location Address
//   * tap - open in Apple Maps
//   * long press - apple maps preview + Get directions / open in maps / add to contacts / copy address
// * phone number
//   * tap - action sheet with call.
//   * long press - show phone number + call PSTN / facetime audio / facetime video / send messages / add to contacts / copy
// * email
//   * tap - open in default mail app
//   * long press - show email adress + new email message / facetime audio / facetime video / send message / add to contacts / copy email.
extension ConversationViewController {

    @objc
    public func didTapBodyTextItem(_ item: CVBodyTextLabel.ItemObject) {
        switch item.item {
        case .dataItem(let dataItem):
            switch dataItem.dataType {
            case .link:
                didTapLink(dataItem: dataItem)
            case .address:
                // Open in iOS Maps app using URL.
                //
                // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html
                UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
            case .phoneNumber:
                // Initiate PSTN call using URL.
                //
                // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/PhoneLinks/PhoneLinks.html
                // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/SMSLinks/SMSLinks.html
                // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/FacetimeLinks/FacetimeLinks.html
                UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
            case .date:
                // Open in iOS Calendar app using default URL.
                //
                // I'm not sure if there's official docs around these links.
                UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
            case .transitInformation:
                // Open in iOS maps app using URL.
                //
                // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html
                UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
            case .emailAddress:
                didTapEmail(dataItem: dataItem)
            }
        case .mention(let mentionItem):
            didTapOrLongPressMention(mentionItem.mention)
        }
    }

    @objc
    public func didLongPressBodyTextItem(_ item: CVBodyTextLabel.ItemObject) {
        switch item.item {
        case .dataItem(let dataItem):
            switch dataItem.dataType {
            case .link:
                // TODO: Show action sheet with options for links.
                didTapLink(dataItem: dataItem)
            case .address:
                // Open in iOS Maps app using URL.
                //
                // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html
                //
                // TODO: Show action sheet with options for addresses.
                UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
            case .phoneNumber:
                // Initiate PSTN call using URL.
                //
                // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/PhoneLinks/PhoneLinks.html
                // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/SMSLinks/SMSLinks.html
                // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/FacetimeLinks/FacetimeLinks.html
                //
                // TODO: Show action sheet with options for phone numbers.
                UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
            case .date:
                // Open in iOS Calendar app using default URL.
                //
                // I'm not sure if there's official docs around these links.
                //
                // TODO: Show action sheet with options for dates.
                UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
            case .transitInformation:
                // Open in iOS maps app using URL.
                //
                // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html
                UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
            case .emailAddress:
                didLongPressEmail(dataItem: dataItem)
            }
        case .mention(let mentionItem):
            didTapOrLongPressMention(mentionItem.mention)
        }
    }

    private func didLongPressEmail(dataItem: CVBodyTextLabel.DataItem) {
        let actionSheet = ActionSheetController(title: dataItem.snippet.strippedOrNil)

        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("MESSAGE_ACTION_EMAIL_NEW_MAIL_MESSAGE",
                                                                         comment: "Label for button to compose a new email."),
                                                accessibilityIdentifier: "email_new_mail_message",
                                                style: .default) { [weak self] _ in
            self?.composeEmail(dataItem: dataItem)
        })
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.copyButton,
                                                accessibilityIdentifier: "email_copy",
                                                style: .default) { _ in
            UIPasteboard.general.string = dataItem.snippet
            // TODO: Show toast?
        })

        // TODO: We could show (facetime audio/facetime video/iMessage) actions for this email address.
        //       Ideally we could detect whether this email address supported these actions.
        // TODO: We could show an "add to contact" action for this email address.
        //       Ideally we could detect whether this email address is already in a system contact.
        // TODO: We could show (Send Signal Message/Signal call) actions for this email address.
        //       Ideally we could detect whether this email address corresponds to a system contact
        //       which is a registered Signal user.

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func didTapLink(dataItem: CVBodyTextLabel.DataItem) {
        AssertIsOnMainThread()

        if isMailtoUrl(dataItem.url) {
            didTapEmail(dataItem: dataItem)
        } else {
            // Open in Safari.
            UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
        }
    }

    private func isMailtoUrl(_ url: URL) -> Bool {
        url.absoluteString.lowercased().hasPrefix("mailto:")
    }

    private func didTapEmail(dataItem: CVBodyTextLabel.DataItem) {
        composeEmail(dataItem: dataItem)
    }

    private func composeEmail(dataItem: CVBodyTextLabel.DataItem) {
        AssertIsOnMainThread()
        owsAssertDebug(isMailtoUrl(dataItem.url))

        guard UIApplication.shared.canOpenURL(dataItem.url) else {
            Logger.info("Device cannot send mail")
            OWSActionSheets.showErrorAlert(message: NSLocalizedString("MESSAGE_ACTION_ERROR_EMAIL_NOT_CONFIGURED",
                                                                      comment: "Error show when user tries to send email without email being configured."))
            return
        }
        UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
    }

    // For now, taps and long presses on mentions do the same thing.
    private func didTapOrLongPressMention(_ mention: Mention) {
        AssertIsOnMainThread()

        ImpactHapticFeedback.impactOccured(style: .light)
        let groupViewHelper = GroupViewHelper(threadViewModel: threadViewModel)
        groupViewHelper.delegate = self
        let actionSheet = MemberActionSheet(address: mention.address, groupViewHelper: groupViewHelper)
        actionSheet.present(from: self)
    }
}
