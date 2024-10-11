//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import MessageUI
import SignalServiceKit
public import SignalUI

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

        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return
        }

        switch item {
        case .dataItem(let dataItem):
            switch dataItem.dataType {
            case .link:
                openLink(dataItem: dataItem)
            case .address:
                // Treat taps and long-press the same.
                didLongPressAddress(dataItem: dataItem)
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
                UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
            case .emailAddress:
                didTapEmail(dataItem: dataItem)
            }
        case .mention(let mentionItem):
            didTapOrLongPressMention(mentionItem.mentionAci)
        case .unrevealedSpoiler(let unrevealedSpoilerItem):
            didTapOrLongPressUnrevealedSpoiler(unrevealedSpoilerItem)
        case .referencedUser(let referencedUserItem):
            owsFailDebug("Should never have a referenced user item in body text, but tapped \(referencedUserItem)")
        }
    }

    public func didLongPressBodyTextItem(_ item: CVTextLabel.Item) {
        AssertIsOnMainThread()

        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return
        }

        switch item {
        case .dataItem(let dataItem):
            switch dataItem.dataType {
            case .link:
                didLongPressLink(dataItem: dataItem)
            case .address:
                didLongPressAddress(dataItem: dataItem)
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
                UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
            case .emailAddress:
                didLongPressEmail(dataItem: dataItem)
            }
        case .mention(let mentionItem):
            didTapOrLongPressMention(mentionItem.mentionAci)
        case .unrevealedSpoiler(let unrevealedSpoilerItem):
            didTapOrLongPressUnrevealedSpoiler(unrevealedSpoilerItem)
        case .referencedUser(let referencedUserItem):
            owsFailDebug("Should never have a referenced user item in body text, but long pressed \(referencedUserItem)")
        }
    }

    // * URL
    //   * tap - open URL in safari
    //   * long press - preview + open link in safari / add to reading list / copy link / share
    private func didLongPressLink(dataItem: TextCheckingDataItem) {
        AssertIsOnMainThread()

        let title = { () -> String? in
            if StickerPackInfo.isStickerPackShare(dataItem.url) {
                return OWSLocalizedString(
                    "MESSAGE_ACTION_TITLE_STICKER_PACK",
                    comment: "Title for message actions for a sticker pack."
                )
            }
            if GroupManager.isPossibleGroupInviteLink(dataItem.url) {
                return OWSLocalizedString(
                    "MESSAGE_ACTION_TITLE_GROUP_INVITE",
                    comment: "Title for message actions for a group invite link."
                )
            }
            return dataItem.snippet.strippedOrNil
        }()

        let actionSheet = ActionSheetController(title: title)

        if StickerPackInfo.isStickerPackShare(dataItem.url) {
            if let stickerPackInfo = StickerPackInfo.parseStickerPackShare(dataItem.url) {
                actionSheet.addAction(ActionSheetAction(
                    title: OWSLocalizedString("MESSAGE_ACTION_LINK_OPEN_STICKER_PACK", comment: "Label for button to open a sticker pack."),
                    style: .default,
                    handler: { [weak self] _ in
                        self?.didTapStickerPack(stickerPackInfo)
                    }
                ))
            } else {
                owsFailDebug("Invalid URL: \(dataItem.url)")
            }
        } else if GroupManager.isPossibleGroupInviteLink(dataItem.url) {
            actionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString("MESSAGE_ACTION_LINK_OPEN_GROUP_INVITE", comment: "Label for button to open a group invite."),
                style: .default,
                handler: { [weak self] _ in
                    self?.didTapGroupInviteLink(url: dataItem.url)
                }
            ))
        } else if SignalProxy.isValidProxyLink(dataItem.url) {
            actionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString("MESSAGE_ACTION_LINK_OPEN_PROXY", comment: "Label for button to open a signal proxy."),
                style: .default,
                handler: { [weak self] _ in
                    self?.didTapProxyLink(url: dataItem.url)
                }
            ))
        } else if let callLink = CallLink(url: dataItem.url) {
            actionSheet.addAction(ActionSheetAction(
                title: CallStrings.joinGroupCall,
                style: .default,
                handler: { [weak self] _ in
                    self?.didTapCallLink(callLink)
                }
            ))
        } else {
            actionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString("MESSAGE_ACTION_LINK_OPEN_LINK", comment: "Label for button to open a link."),
                style: .default,
                handler: { [weak self] _ in
                    self?.openLink(dataItem: dataItem)
                }
            ))
        }

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.copyButton,
            style: .default,
            handler: { _ in
                UIPasteboard.general.string = dataItem.snippet
                // TODO: Show toast?
            }
        ))
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.shareButton,
            style: .default,
            handler: { _ in
                AttachmentSharing.showShareUI(for: dataItem.url, sender: self)
            }
        ))
        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func didLongPressAddress(dataItem: TextCheckingDataItem) {
        let addressString = dataItem.snippet

        let actionSheet = ActionSheetController(title: addressString)

        // The URL on an address data item is, by default, an Apple Maps URL.
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "MESSAGE_ACTION_LINK_OPEN_ADDRESS_APPLE_MAPS",
                comment: "A label for a button that will open an address in Apple Maps. \"Maps\" is a proper noun referring to the Apple Maps app, and should be translated as such."
            ),
            handler: { _ in
                UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
            }
        ))

        if
            let googleMapsUrl = TextCheckingDataItem.buildAddressQueryUrl(
                appScheme: "comgooglemaps",
                addressToQuery: addressString
            ),
            UIApplication.shared.canOpenURL(googleMapsUrl)
        {
            actionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString(
                    "MESSAGE_ACTION_LINK_OPEN_ADDRESS_GOOGLE_MAPS",
                    comment: "A label for a button that will open an address in Google Maps. \"Google Maps\" is a proper noun referring to the Google Maps app, and should be translated as such."
                ),
                handler: { _ in
                    UIApplication.shared.open(googleMapsUrl, options: [:], completionHandler: nil)
                }
            ))
        }

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.copyButton,
            handler: { _ in
                UIPasteboard.general.string = addressString
            }
        ))

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    // * phone number
    //   * tap - action sheet with call.
    //   * long press - show phone number + call PSTN / facetime audio / facetime video / send messages / add to contacts / copy
    private func didLongPressPhoneNumber(dataItem: TextCheckingDataItem) {
        guard
            let snippet = dataItem.snippet.strippedOrNil,
            let phoneNumberObj = SSKEnvironment.shared.phoneNumberUtilRef.parsePhoneNumber(userSpecifiedText: snippet),
            let phoneNumber = phoneNumberObj.e164.strippedOrNil
        else {
            owsFailDebug("Invalid phone number.")
            UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
            return
        }

        let recipient = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let recipientManager = DependenciesBridge.shared.recipientManager
            return recipientManager.fetchRecipientIfPhoneNumberVisible(phoneNumber, tx: tx.asV2Read)
        }

        if let recipient, recipient.isRegistered {
            showMemberActionSheet(forAddress: recipient.address, withHapticFeedback: false)
            return
        }

        let actionSheet = ActionSheetController(title: phoneNumber)
        let blockedAddress = SignalServiceAddress(phoneNumber: phoneNumber)
        let isBlocked = SSKEnvironment.shared.databaseStorageRef.read {
            SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(blockedAddress, transaction: $0)
        }

        if isBlocked {
            actionSheet.addAction(
                ActionSheetAction(
                    title: OWSLocalizedString("BLOCK_LIST_UNBLOCK_BUTTON", comment: "Button label for the 'unblock' button"),
                    style: .default
                ) { [weak self] _ in
                    guard let self = self else { return }
                    BlockListUIUtils.showUnblockAddressActionSheet(
                        blockedAddress,
                        from: self,
                        completion: nil
                    )
                })

        } else {
            // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/PhoneLinks/PhoneLinks.html
            actionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString(
                    "MESSAGE_ACTION_PHONE_NUMBER_CALL",
                    comment: "Label for button to call a phone number."
                ),
                style: .default) { _ in
                    guard let url = URL(string: "tel:" + phoneNumber) else {
                        owsFailDebug("Invalid phone number.")
                        return
                    }
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            )
            // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/SMSLinks/SMSLinks.html
            actionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString(
                    "MESSAGE_ACTION_PHONE_NUMBER_SMS",
                    comment: "Label for button to send a text message a phone number."
                ),
                style: .default) { _ in
                    guard let url = URL(string: "sms:" + phoneNumber) else {
                        owsFailDebug("Invalid phone number.")
                        return
                    }
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            )
            // https://developer.apple.com/library/archive/featuredarticles/iPhoneURLScheme_Reference/FacetimeLinks/FacetimeLinks.html
            actionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString(
                    "MESSAGE_ACTION_PHONE_NUMBER_FACETIME_VIDEO",
                    comment: "Label for button to make a FaceTime video call to a phone number."
                ),
                style: .default) { _ in
                    guard let url = URL(string: "facetime:" + phoneNumber) else {
                        owsFailDebug("Invalid phone number.")
                        return
                    }
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            )
            actionSheet.addAction(ActionSheetAction(
                title: OWSLocalizedString(
                    "MESSAGE_ACTION_PHONE_NUMBER_FACETIME_AUDIO",
                    comment: "Label for button to make a FaceTime audio call to a phone number."
                ),
                style: .default) { _ in
                    guard let url = URL(string: "facetime-audio:" + phoneNumber) else {
                        owsFailDebug("Invalid phone number.")
                        return
                    }
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            )
            // TODO: We could show an "add to contact" action for this phone number.
            //       Ideally we could detect whether this phone number is already in a system contact.
            // TODO: We could show an "share" action for this phone number.
        }

        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.copyButton,
            style: .default) { _ in
                UIPasteboard.general.string = dataItem.snippet
                // TODO: Show toast?
            }
        )

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    private func didLongPressEmail(dataItem: TextCheckingDataItem) {
        let actionSheet = ActionSheetController(title: dataItem.snippet.strippedOrNil)

        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("MESSAGE_ACTION_EMAIL_NEW_MAIL_MESSAGE", comment: "Label for button to compose a new email."),
            style: .default,
            handler: { [weak self] _ in
                self?.composeEmail(dataItem: dataItem)
            }
        ))
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.copyButton,
            style: .default,
            handler: { _ in
                UIPasteboard.general.string = dataItem.snippet
                // TODO: Show toast?
            }
        ))

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

    private func openLink(dataItem: TextCheckingDataItem) {
        AssertIsOnMainThread()

        if isMailtoUrl(dataItem.url) {
            didTapEmail(dataItem: dataItem)
            return
        }

        self.handleUrl(dataItem.url)
    }

    private func isMailtoUrl(_ url: URL) -> Bool {
        url.absoluteString.lowercased().hasPrefix("mailto:")
    }

    private func didTapEmail(dataItem: TextCheckingDataItem) {
        composeEmail(dataItem: dataItem)
    }

    private func composeEmail(dataItem: TextCheckingDataItem) {
        AssertIsOnMainThread()
        owsAssertDebug(isMailtoUrl(dataItem.url))

        guard UIApplication.shared.canOpenURL(dataItem.url) else {
            Logger.info("Device cannot send mail")
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString(
                "MESSAGE_ACTION_ERROR_EMAIL_NOT_CONFIGURED",
                comment: "Error show when user tries to send email without email being configured."
            ))
            return
        }
        UIApplication.shared.open(dataItem.url, options: [:], completionHandler: nil)
    }

    // For now, taps and long presses on mentions do the same thing.
    private func didTapOrLongPressMention(_ mentionAci: Aci) {
        AssertIsOnMainThread()

        showMemberActionSheet(forAddress: SignalServiceAddress(mentionAci), withHapticFeedback: true)
    }

    // Taps and long presses do the same thing.
    private func didTapOrLongPressUnrevealedSpoiler(_ unrevealedSpoilerItem: CVTextLabel.UnrevealedSpoilerItem) {
        viewState.spoilerState.revealState.setSpoilerRevealed(
            withID: unrevealedSpoilerItem.spoilerId,
            interactionIdentifier: unrevealedSpoilerItem.interactionIdentifier
        )
        self.loadCoordinator.enqueueReload(
            updatedInteractionIds: [unrevealedSpoilerItem.interactionUniqueId],
            deletedInteractionIds: []
        )
    }
}
