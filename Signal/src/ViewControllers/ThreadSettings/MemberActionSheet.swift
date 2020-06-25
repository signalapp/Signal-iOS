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

    // MARK: -

    @objc
    let address: SignalServiceAddress

    private weak var contactsViewHelper: ContactsViewHelper?

    public var canMakeGroupAdmin = false

    public var groupViewHelper: GroupViewHelper?

    @objc
    init(address: SignalServiceAddress, contactsViewHelper: ContactsViewHelper, groupViewHelper: GroupViewHelper?) {
        assert(address.isValid)
        self.address = address
        self.contactsViewHelper = contactsViewHelper
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

        guard let contactsViewHelper = contactsViewHelper else {
            return owsFailDebug("unexpectedly missing contactsViewHelper")
        }

        let actionSheet = ActionSheetController()
        actionSheet.customHeader = MemberHeader(address: address) { [weak actionSheet] in
            actionSheet?.dismiss(animated: true, completion: {
                // If we can edit contacts, present the contact for this user when tapping the header.
                guard self.contactsManager.supportsContactEditing else { return }

                guard let contactVC = contactsViewHelper.contactViewController(for: self.address, editImmediately: true) else {
                    return owsFailDebug("unexpectedly failed to present contact view")
                }
                self.strongSelf = self
                contactVC.delegate = self
                navController.pushViewController(contactVC, animated: true)
            })
        }

        actionSheet.contentAlignment = .leading
        actionSheet.addAction(OWSActionSheets.cancelAction)

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

        let messageAction = ActionSheetAction(
            title: NSLocalizedString("GROUP_MEMBERS_SEND_MESSAGE",
                                     comment: "Button label for the 'send message to group member' button"),
            accessibilityIdentifier: "MemberActionSheet.send_message"
        ) { _ in
            SignalApp.shared().presentConversation(for: self.address, action: .compose, animated: true)
        }
        messageAction.leadingIcon = .message
        actionSheet.addAction(messageAction)

        if FeatureFlags.calling {
            let callAction = ActionSheetAction(
                title: NSLocalizedString("GROUP_MEMBERS_CALL",
                                         comment: "Button label for the 'call group member' button"),
                accessibilityIdentifier: "MemberActionSheet.call"
            ) { _ in
                SignalApp.shared().presentConversation(for: self.address, action: .audioCall, animated: true)
            }
            callAction.leadingIcon = .call
            actionSheet.addAction(callAction)
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

        if let groupViewHelper = self.groupViewHelper {
            let address = self.address
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
    var databaseStorage: SDSDatabaseStorage {
        return .shared
    }

    var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    var profileManager: OWSProfileManager {
        return .shared()
    }

    private var releaseAction: () -> Void

    init(address: SignalServiceAddress, releaseAction: @escaping () -> Void) {
        self.releaseAction = releaseAction

        super.init(frame: .zero)

        addBackgroundView(withBackgroundColor: Theme.actionSheetBackgroundColor)
        axis = .vertical
        spacing = 2
        isLayoutMarginsRelativeArrangement = true
        layoutMargins = UIEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)

        createViews(address: address)

        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTap))
        addGestureRecognizer(tapGestureRecognizer)
    }

    @objc func didTap() {
        releaseAction()
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
        let avatarView = ConversationAvatarImageView(
            thread: thread,
            diameter: UInt(avatarDiameter),
            contactsManager: contactsManager
        )
        avatarContainer.addSubview(avatarView)
        avatarView.autoHCenterInSuperview()
        avatarView.autoPinEdge(toSuperviewEdge: .top)
        avatarView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 8)
        avatarView.autoSetDimension(.height, toSize: avatarDiameter)

        let titleLabel = UILabel()
        titleLabel.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold()
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
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
