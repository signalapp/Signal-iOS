//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MessageUI
import SignalCoreKit

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
//   * long press - show email address + new email message / facetime audio / facetime video / send message / add to contacts / copy email.
extension ConversationViewController {

    public func didTapBodyTextItem(_ item: CVTextLabel.Item) {
        AssertIsOnMainThread()

        guard tsAccountManager.isRegisteredAndReady else {
            return
        }

        switch item {
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
        case .referencedUser(let referencedUserItem):
            owsFailDebug("Should never have a referenced user item in body text, but tapped \(referencedUserItem)")
        }
    }

    public func didLongPressBodyTextItem(_ item: CVTextLabel.Item) {
        AssertIsOnMainThread()

        guard tsAccountManager.isRegisteredAndReady else {
            return
        }

        switch item {
        case .dataItem(let dataItem):
            switch dataItem.dataType {
            case .link:
                didLongPressLink(dataItem: dataItem)
            case .address:
                // Open in iOS Maps app using URL.
                //
                // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/MapLinks/MapLinks.html
                //
                // TODO: Show action sheet with options for addresses.
                UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
            case .phoneNumber:
                didLongPressPhoneNumber(dataItem: dataItem)
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
        case .referencedUser(let referencedUserItem):
            owsFailDebug("Should never have a referenced user item in body text, but long pressed \(referencedUserItem)")
        }
    }

    // * URL
    //   * tap - open URL in safari
    //   * long press - preview + open link in safari / add to reading list / copy link / share
    private func didLongPressLink(dataItem: CVTextLabel.DataItem) {
        AssertIsOnMainThread()

        var title: String? = dataItem.snippet.strippedOrNil
        if StickerPackInfo.isStickerPackShare(dataItem.url) {
            title = NSLocalizedString("MESSAGE_ACTION_TITLE_STICKER_PACK",
                                      comment: "Title for message actions for a sticker pack.")
        } else if GroupManager.isPossibleGroupInviteLink(dataItem.url) {
            title = NSLocalizedString("MESSAGE_ACTION_TITLE_GROUP_INVITE",
                                                  comment: "Title for message actions for a group invite link.")
        }

        let actionSheet = ActionSheetController(title: title)

        if StickerPackInfo.isStickerPackShare(dataItem.url) {
            if let stickerPackInfo = StickerPackInfo.parseStickerPackShare(dataItem.url) {
                actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("MESSAGE_ACTION_LINK_OPEN_STICKER_PACK",
                                                                                 comment: "Label for button to open a sticker pack."),
                                                        accessibilityIdentifier: "link_open_sticker_pack",
                                                        style: .default) { [weak self] _ in
                    self?.cvc_didTapStickerPack(stickerPackInfo)
                })
            } else {
                owsFailDebug("Invalid URL: \(dataItem.url)")
            }
        } else if GroupManager.isPossibleGroupInviteLink(dataItem.url) {
            actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("MESSAGE_ACTION_LINK_OPEN_GROUP_INVITE",
                                                                             comment: "Label for button to open a group invite."),
                                                    accessibilityIdentifier: "link_open_group_invite",
                                                    style: .default) { [weak self] _ in
                self?.cvc_didTapGroupInviteLink(url: dataItem.url)
            })
        } else if SignalProxy.isValidProxyLink(dataItem.url) {
            actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("MESSAGE_ACTION_LINK_OPEN_PROXY",
                                                                             comment: "Label for button to open a signal proxy."),
                                                    accessibilityIdentifier: "link_open_proxy",
                                                    style: .default) { [weak self] _ in
                self?.cvc_didTapProxyLink(url: dataItem.url)
            })
        } else {
            actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("MESSAGE_ACTION_LINK_OPEN_LINK",
                                                                             comment: "Label for button to open a link."),
                                                    accessibilityIdentifier: "link_open_link",
                                                    style: .default) { [weak self] _ in
                self?.openLink(dataItem: dataItem)
            })
        }

        actionSheet.addAction(ActionSheetAction(title: CommonStrings.copyButton,
                                                accessibilityIdentifier: "link_copy",
                                                style: .default) { _ in
            UIPasteboard.general.string = dataItem.snippet
            // TODO: Show toast?
        })
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.shareButton,
                                                accessibilityIdentifier: "link_share",
                                                style: .default) { _ in
            AttachmentSharing.showShareUI(for: dataItem.url, sender: self)
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    // * phone number
    //   * tap - action sheet with call.
    //   * long press - show phone number + call PSTN / facetime audio / facetime video / send messages / add to contacts / copy
    private func didLongPressPhoneNumber(dataItem: CVTextLabel.DataItem) {
        guard let snippet = dataItem.snippet.strippedOrNil,
              let phoneNumber = PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: snippet),
              let e164 = phoneNumber.toE164().strippedOrNil else {
            owsFailDebug("Invalid phone number.")
            UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
            return
        }
        let address = SignalServiceAddress(phoneNumber: e164)

        if address.isLocalAddress ||
           Self.contactsManagerImpl.isKnownRegisteredUserWithSneakyTransaction(address: address) {
            showMemberActionSheet(forAddress: address, withHapticFeedback: false)
            return
        }

        let actionSheet = ActionSheetController(title: e164)
        let isBlocked = databaseStorage.read { blockingManager.isAddressBlocked(address, transaction: $0) }

        if isBlocked {
            actionSheet.addAction(
                ActionSheetAction(
                    title: NSLocalizedString("BLOCK_LIST_UNBLOCK_BUTTON", comment: "Button label for the 'unblock' button"),
                    accessibilityIdentifier: "phone_number_unblock",
                    style: .default
                ) { [weak self] _ in
                    guard let self = self else { return }
                    BlockListUIUtils.showUnblockAddressActionSheet(
                        address,
                        from: self,
                        completionBlock: nil)
                })

        } else {
            // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/PhoneLinks/PhoneLinks.html
            actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("MESSAGE_ACTION_PHONE_NUMBER_CALL",
                                                                             comment: "Label for button to call a phone number."),
                                                    accessibilityIdentifier: "phone_number_call",
                                                    style: .default) { _ in
                guard let url = URL(string: "tel:" + e164) else {
                    owsFailDebug("Invalid phone number.")
                    return
                }
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            })
            // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/SMSLinks/SMSLinks.html
            actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("MESSAGE_ACTION_PHONE_NUMBER_SMS",
                                                                             comment: "Label for button to send a text message a phone number."),
                                                    accessibilityIdentifier: "phone_number_text_message",
                                                    style: .default) { _ in
                guard let url = URL(string: "sms:" + e164) else {
                    owsFailDebug("Invalid phone number.")
                    return
                }
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            })
            // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/FacetimeLinks/FacetimeLinks.html
            actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("MESSAGE_ACTION_PHONE_NUMBER_FACETIME_VIDEO",
                                                                             comment: "Label for button to make a FaceTime video call to a phone number."),
                                                    accessibilityIdentifier: "phone_number_facetime_video",
                                                    style: .default) { _ in
                guard let url = URL(string: "facetime:" + e164) else {
                    owsFailDebug("Invalid phone number.")
                    return
                }
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            })
            actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("MESSAGE_ACTION_PHONE_NUMBER_FACETIME_AUDIO",
                                                                             comment: "Label for button to make a FaceTime audio call to a phone number."),
                                                    accessibilityIdentifier: "phone_number_facetime_audio",
                                                    style: .default) { _ in
                guard let url = URL(string: "facetime-audio:" + e164) else {
                    owsFailDebug("Invalid phone number.")
                    return
                }
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            })
            // TODO: We could show an "add to contact" action for this phone number.
            //       Ideally we could detect whether this phone number is already in a system contact.
            // TODO: We could show an "share" action for this phone number.
        }

        actionSheet.addAction(ActionSheetAction(title: CommonStrings.copyButton,
                                                accessibilityIdentifier: "phone_number_copy",
                                                style: .default) { _ in
            UIPasteboard.general.string = dataItem.snippet
            // TODO: Show toast?
        })

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func didLongPressEmail(dataItem: CVTextLabel.DataItem) {
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
        // TODO: We could show an "share" action for this email address.

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func didTapLink(dataItem: CVTextLabel.DataItem) {
        AssertIsOnMainThread()

        openLink(dataItem: dataItem)
    }

    private func openLink(dataItem: CVTextLabel.DataItem) {
        AssertIsOnMainThread()

        if StickerPackInfo.isStickerPackShare(dataItem.url) {
            guard let stickerPackInfo = StickerPackInfo.parseStickerPackShare(dataItem.url) else {
                owsFailDebug("Invalid URL: \(dataItem.url)")
                return
            }
            cvc_didTapStickerPack(stickerPackInfo)
        } else if GroupManager.isPossibleGroupInviteLink(dataItem.url) {
            cvc_didTapGroupInviteLink(url: dataItem.url)
        } else if SignalProxy.isValidProxyLink(dataItem.url) {
            cvc_didTapProxyLink(url: dataItem.url)
        } else if SignalMe.isPossibleUrl(dataItem.url) {
            cvc_didTapSignalMeLink(url: dataItem.url)
        } else if isMailtoUrl(dataItem.url) {
            didTapEmail(dataItem: dataItem)
        } else {
            // Open in Safari.
            UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
        }
    }

    private func isMailtoUrl(_ url: URL) -> Bool {
        url.absoluteString.lowercased().hasPrefix("mailto:")
    }

    private func didTapEmail(dataItem: CVTextLabel.DataItem) {
        composeEmail(dataItem: dataItem)
    }

    private func composeEmail(dataItem: CVTextLabel.DataItem) {
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

        showMemberActionSheet(forAddress: mention.address, withHapticFeedback: true)
    }
}
