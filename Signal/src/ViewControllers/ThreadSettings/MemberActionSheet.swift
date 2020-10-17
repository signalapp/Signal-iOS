//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import ContactsUI

@objc
class MemberActionSheet: NSObject {

    // MARK: - Dependencies

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private var contactsViewHelper: ContactsViewHelper {
        return Environment.shared.contactsViewHelper
    }

    // MARK: -

    @objc
    let address: SignalServiceAddress

    public var canMakeGroupAdmin = false

    public var groupViewHelper: GroupViewHelper?

    @objc
    init(address: SignalServiceAddress, groupViewHelper: GroupViewHelper?) {
        assert(address.isValid)
        self.address = address
        self.groupViewHelper = groupViewHelper
    }

    // When presenting the contact view, we must retain ourselves
    // as we are the delegate. This will get released when contact
    // editing has concluded.
    private var strongSelf: MemberActionSheet?

    @objc
    func present(fromViewController: UIViewController) {
        guard let navController = fromViewController.navigationController else {
            return owsFailDebug("Must be presented within a nav controller")
        }

        let contactsViewHelper = self.contactsViewHelper

        let actionSheet = ActionSheetController()
        actionSheet.customHeader = MemberHeader(address: address) { [weak actionSheet] in
            actionSheet?.dismiss(animated: true)
        }

        actionSheet.contentAlignment = .leading
        actionSheet.addAction(OWSActionSheets.cancelAction)

        // If the local user, show no options.
        guard !address.isLocalAddress else {
            fromViewController.presentActionSheet(actionSheet)
            return
        }

        // If blocked, only show unblock as an option
        guard !contactsViewHelper.isSignalServiceAddressBlocked(address) else {
            let unblockAction = ActionSheetAction(
                title: NSLocalizedString("BLOCK_LIST_UNBLOCK_BUTTON",
                                         comment: "Button label for the 'unblock' button"),
                accessibilityIdentifier: "MemberActionSheet.unblock"
            ) { _ in
                BlockListUIUtils.showUnblockAddressActionSheet(
                    self.address,
                    from: fromViewController,
                    completionBlock: nil
                )
            }
            unblockAction.leadingIcon = .settingsBlock
            actionSheet.addAction(unblockAction)

            fromViewController.presentActionSheet(actionSheet)
            return
        }

        let blockAction = ActionSheetAction(
            title: NSLocalizedString("BLOCK_LIST_BLOCK_BUTTON",
                                     comment: "Button label for the 'block' button"),
            accessibilityIdentifier: "MemberActionSheet.block"
        ) { _ in
            BlockListUIUtils.showBlockAddressActionSheet(
                self.address,
                from: fromViewController,
                completionBlock: nil
            )
        }
        blockAction.leadingIcon = .settingsBlock
        actionSheet.addAction(blockAction)

        if contactsManager.supportsContactEditing && !contactsManager.isSystemContact(address: address) {
            let addToContactsAction = ActionSheetAction(
                title: NSLocalizedString("CONVERSATION_SETTINGS_ADD_TO_SYSTEM_CONTACTS",
                                         comment: "button in conversation settings view."),
                accessibilityIdentifier: "MemberActionSheet.block"
            ) { _ in
                guard let contactVC = contactsViewHelper.contactViewController(for: self.address, editImmediately: true) else {
                     return owsFailDebug("unexpectedly failed to present contact view")
                 }
                 self.strongSelf = self
                 contactVC.delegate = self
                 navController.pushViewController(contactVC, animated: true)
            }
            addToContactsAction.leadingIcon = .settingsAddToContacts
            actionSheet.addAction(addToContactsAction)
        }

        let addToGroupAction = ActionSheetAction(
            title: NSLocalizedString("ADD_TO_GROUP",
                                     comment: "Label for button or row which allows users to add to another group."),
            accessibilityIdentifier: "MemberActionSheet.addToGroup"
        ) { _ in
            AddToGroupViewController.presentForUser(self.address, from: fromViewController)
        }
        addToGroupAction.leadingIcon = .settingsAddToGroup
        actionSheet.addAction(addToGroupAction)

        let safetyNumberAction = ActionSheetAction(
            title: NSLocalizedString("VERIFY_PRIVACY",
                                     comment: "Label for button or row which allows users to verify the safety number of another user."),
            accessibilityIdentifier: "MemberActionSheet.block"
        ) { _ in
            FingerprintViewController.present(from: fromViewController, address: self.address)
        }
        safetyNumberAction.leadingIcon = .settingsViewSafetyNumber
        actionSheet.addAction(safetyNumberAction)

        let address = self.address
        if let groupViewHelper = self.groupViewHelper,
            groupViewHelper.isFullOrInvitedMember(address) {

            if groupViewHelper.memberActionSheetCanMakeGroupAdmin(address: address) {
                let action = ActionSheetAction(
                    title: NSLocalizedString("CONVERSATION_SETTINGS_MAKE_GROUP_ADMIN_BUTTON",
                                             comment: "Label for 'make group admin' button in conversation settings view."),
                    accessibilityIdentifier: "MemberActionSheet.makeGroupAdmin"
                ) { _ in
                    groupViewHelper.memberActionSheetMakeGroupAdminWasSelected(address: address)
                }
                action.leadingIcon = .settingsViewMakeGroupAdmin
                actionSheet.addAction(action)
            }
            if groupViewHelper.memberActionSheetCanRevokeGroupAdmin(address: address) {
                let action = ActionSheetAction(
                    title: NSLocalizedString("CONVERSATION_SETTINGS_REVOKE_GROUP_ADMIN_BUTTON",
                                             comment: "Label for 'revoke group admin' button in conversation settings view."),
                    accessibilityIdentifier: "MemberActionSheet.revokeGroupAdmin"
                ) { _ in
                    groupViewHelper.memberActionSheetRevokeGroupAdminWasSelected(address: address)
                }
                action.leadingIcon = .settingsViewRevokeGroupAdmin
                actionSheet.addAction(action)
            }
            if groupViewHelper.memberActionSheetCanRemoveFromGroup(address: address) {
                let action = ActionSheetAction(
                    title: NSLocalizedString("CONVERSATION_SETTINGS_REMOVE_FROM_GROUP_BUTTON",
                                             comment: "Label for 'remove from group' button in conversation settings view."),
                    accessibilityIdentifier: "MemberActionSheet.removeFromGroup"
                ) { _ in
                    groupViewHelper.memberActionSheetRemoveFromGroupWasSelected(address: address)
                }
                action.leadingIcon = .settingsViewRemoveFromGroup
                actionSheet.addAction(action)
            }
        }

        fromViewController.presentActionSheet(actionSheet)
    }
}

extension MemberActionSheet: CNContactViewControllerDelegate {
    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        viewController.navigationController?.popViewController(animated: true)
        strongSelf = nil
    }
}

private class MemberHeader: UIStackView {

    private var dismiss: () -> Void

    init(address: SignalServiceAddress, dismiss: @escaping () -> Void) {
        self.dismiss = dismiss

        super.init(frame: .zero)

        addBackgroundView(withBackgroundColor: Theme.actionSheetBackgroundColor)
        axis = .vertical
        spacing = 2
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)

        createViews(address: address)
    }

    func createViews(address: SignalServiceAddress) {
        var fetchedThread: TSContactThread?
        var fetchedDisplayName: String?
        var username: String?

        databaseStorage.read { transaction in
            fetchedThread = TSContactThread.getWithContactAddress(address, transaction: transaction)
            fetchedDisplayName = self.contactsManager.displayName(for: address, transaction: transaction)
            username = self.profileManager.username(for: address, transaction: transaction)
        }

        // Only open a write transaction if we need to create a new thread record.
        if fetchedThread == nil {
            databaseStorage.write { transaction in
                fetchedThread = TSContactThread(contactAddress: address)
                fetchedThread?.anyInsert(transaction: transaction)
            }
        }

        guard let thread = fetchedThread, let displayName = fetchedDisplayName else {
            return owsFailDebug("Unexpectedly missing name and thread")
        }

        let avatarContainer = UIView()
        addArrangedSubview(avatarContainer)

        let avatarDiameter: CGFloat = 80
        let avatarView = AvatarImageView()

        avatarContainer.addSubview(avatarView)
        avatarView.autoHCenterInSuperview()
        avatarView.autoPinEdge(toSuperviewEdge: .top)
        avatarView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 8)
        avatarView.autoSetDimension(.height, toSize: avatarDiameter)

        let avatarBuilder = OWSContactAvatarBuilder(
            address: address,
            colorName: thread.conversationColorName,
            diameter: UInt(avatarDiameter)
        )

        if address.isLocalAddress {
            avatarView.image = OWSProfileManager.shared().localProfileAvatarImage() ?? avatarBuilder.buildDefaultImage()
        } else {
            avatarView.image = avatarBuilder.build()
        }

        let titleLabel = UILabel()
        titleLabel.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        titleLabel.setContentHuggingVerticalHigh()
        titleLabel.setCompressionResistanceVerticalHigh()
        titleLabel.text = displayName
        addArrangedSubview(titleLabel)

        var detailText: String?
        if let phoneNumber = address.phoneNumber {
            let formattedNumber = PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: phoneNumber)
            if displayName != formattedNumber {
                detailText = formattedNumber
            }
        }
        if let username = username {
            if let formattedUsername = CommonFormats.formatUsername(username), displayName != formattedUsername {
                if let existingDetails = detailText {
                    detailText = existingDetails + "\n" + formattedUsername
                } else {
                    detailText = formattedUsername
                }
            }
        }

        if let detailText = detailText {
            let detailsLabel = UILabel()
            detailsLabel.font = .ows_dynamicTypeSubheadline
            detailsLabel.textColor = Theme.secondaryTextAndIconColor
            detailsLabel.numberOfLines = 0
            detailsLabel.lineBreakMode = .byWordWrapping
            detailsLabel.textAlignment = .center
            detailsLabel.setContentHuggingVerticalHigh()
            detailsLabel.setCompressionResistanceVerticalHigh()
            detailsLabel.text = detailText
            addArrangedSubview(detailsLabel)
        }

        let actionsStackView = UIStackView()
        actionsStackView.axis = .horizontal
        actionsStackView.spacing = 36
        actionsStackView.isLayoutMarginsRelativeArrangement = true
        actionsStackView.layoutMargins = UIEdgeInsets(top: 14, leading: 0, bottom: 18, trailing: 0)
        addArrangedSubview(actionsStackView)

        let messageButton = createActionButton(
            icon: .message,
            accessibilityLabel: NSLocalizedString("GROUP_MEMBERS_SEND_MESSAGE",
                                                  comment: "Accessibility label for the 'send message to group member' button"),
            accessibilityIdentifier: "MemberActionSheet.send_message"
        ) { SignalApp.shared().presentConversation(for: address, action: .compose, animated: true) }
        actionsStackView.addArrangedSubview(messageButton)

        let videoCallButton = createActionButton(
            icon: .videoCall,
            accessibilityLabel: NSLocalizedString("GROUP_MEMBERS_VIDEO_CALL",
                                                  comment: "Accessibility label for the 'call group member' button"),
            accessibilityIdentifier: "MemberActionSheet.video_call"
        ) { SignalApp.shared().presentConversation(for: address, action: .videoCall, animated: true) }
        videoCallButton.isEnabled = !address.isLocalAddress
        actionsStackView.addArrangedSubview(videoCallButton)

        let audioCallButton = createActionButton(
            icon: .audioCall,
            accessibilityLabel: NSLocalizedString("GROUP_MEMBERS_CALL",
                                                  comment: "Accessibility label for the 'call group member' button"),
            accessibilityIdentifier: "MemberActionSheet.audio_call"
        ) { SignalApp.shared().presentConversation(for: address, action: .audioCall, animated: true) }
        audioCallButton.isEnabled = !address.isLocalAddress
        actionsStackView.addArrangedSubview(audioCallButton)

        let leftSpacer = UIView.hStretchingSpacer()
        let rightSpacer = UIView.hStretchingSpacer()
        actionsStackView.insertArrangedSubview(leftSpacer, at: 0)
        actionsStackView.addArrangedSubview(rightSpacer)
        leftSpacer.autoMatch(.width, to: .width, of: rightSpacer)

    }

    private func createActionButton(
        icon: ThemeIcon,
        accessibilityLabel: String?,
        accessibilityIdentifier: String?,
        action: @escaping () -> Void
    ) -> UIButton {
        let button = OWSButton { [weak self] in
            guard let self = self else { return }
            action()
            self.dismiss()
        }
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityIdentifier = accessibilityIdentifier
        button.autoSetDimensions(to: CGSize(square: 48))
        button.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray02
        button.layer.cornerRadius = 24
        button.clipsToBounds = true
        button.imageEdgeInsets = UIEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        button.setTemplateImageName(Theme.iconName(icon), tintColor: Theme.accentBlueColor)
        return button
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
