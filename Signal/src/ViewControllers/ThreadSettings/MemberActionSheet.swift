//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import ContactsUI
import SignalServiceKit
import SignalUI

struct ProfileSheetSheetCoordinator {
    private let address: SignalServiceAddress
    private let groupViewHelper: GroupViewHelper?
    private let spoilerState: SpoilerRenderState

    init(
        address: SignalServiceAddress,
        groupViewHelper: GroupViewHelper?,
        spoilerState: SpoilerRenderState
    ) {
        self.address = address
        self.groupViewHelper = groupViewHelper
        self.spoilerState = spoilerState
    }

    /// Present a ``MemberActionSheet`` for other users, and present a
    /// ``ContactAboutSheet`` for the local user.
    func presentAppropriateSheet(from viewController: UIViewController) {
        let threadViewModel = MemberActionSheet.fetchThreadViewModel(address: address)
        let thread = threadViewModel.threadRecord

        if thread.isNoteToSelf, let contactThread = thread as? TSContactThread {
            ContactAboutSheet(thread: contactThread, spoilerState: spoilerState)
                .present(from: viewController)
            return
        }

        MemberActionSheet(
            threadViewModel: threadViewModel,
            address: address,
            groupViewHelper: groupViewHelper,
            spoilerState: spoilerState
        )
        .present(from: viewController)
    }
}

final class MemberActionSheet: OWSTableSheetViewController {
    private var groupViewHelper: GroupViewHelper?

    var avatarView: ConversationAvatarView?
    var thread: TSThread { threadViewModel.threadRecord }
    var threadViewModel: ThreadViewModel
    let address: SignalServiceAddress
    let spoilerState: SpoilerRenderState

    fileprivate init(
        threadViewModel: ThreadViewModel,
        address: SignalServiceAddress,
        groupViewHelper: GroupViewHelper?,
        spoilerState: SpoilerRenderState
    ) {
        self.threadViewModel = threadViewModel
        self.groupViewHelper = groupViewHelper
        self.address = address
        self.spoilerState = spoilerState

        super.init()

        tableViewController.defaultSeparatorInsetLeading =
            OWSTableViewController2.cellHInnerMargin + 24 + OWSTableItem.iconSpacing

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(recipientUpdated(notification:)),
            name: .OWSContactsManagerSignalAccountsDidChange,
            object: nil
        )
    }

    fileprivate static func fetchThreadViewModel(address: SignalServiceAddress) -> ThreadViewModel {
        // Avoid opening a write transaction if we can
        guard let threadViewModel: ThreadViewModel = SSKEnvironment.shared.databaseStorageRef.read(block: { transaction in
            guard let thread = TSContactThread.getWithContactAddress(
                address,
                transaction: transaction
            ) else { return nil }
            return ThreadViewModel(
                thread: thread,
                forChatList: false,
                transaction: transaction
            )
        }) else {
            return SSKEnvironment.shared.databaseStorageRef.write { transaction in
                let thread = TSContactThread.getOrCreateThread(
                    withContactAddress: address,
                    transaction: transaction
                )
                return ThreadViewModel(
                    thread: thread,
                    forChatList: false,
                    transaction: transaction
                )
            }
        }
        return threadViewModel
    }

    private weak var fromViewController: UIViewController?

    fileprivate func present(from viewController: UIViewController) {
        fromViewController = viewController
        viewController.present(self, animated: true)
    }

    // When presenting the contact view, we must retain ourselves
    // as we are the delegate. This will get released when contact
    // editing has concluded.
    private var strongSelf: MemberActionSheet?
    public override func updateTableContents(shouldReload: Bool = true) {
        let contents = OWSTableContents()
        defer { tableViewController.setContents(contents, shouldReload: shouldReload) }

        let topSpacerSection = OWSTableSection()
        topSpacerSection.customHeaderHeight = 12
        contents.add(topSpacerSection)

        let section = OWSTableSection()
        contents.add(section)

        section.customHeaderView = ConversationHeaderBuilder.buildHeader(
            for: thread,
            sizeClass: .eighty,
            options: [.message, .videoCall, .audioCall],
            delegate: self
        )

        // If the local user, show no options.
        guard !address.isLocalAddress else { return }

        // Nickname
        section.add(.item(
            icon: .buttonEdit,
            name: OWSLocalizedString(
                "NICKNAME_BUTTON_TITLE",
                comment: "Title for the table cell in conversation settings for presenting the profile nickname editor."
            ),
            actionBlock: { [weak self] in
                guard let self else { return }
                let db = DependenciesBridge.shared.db

                let nicknameEditor = db.read { tx in
                    NicknameEditorViewController.create(
                        for: self.address,
                        context: .init(
                            db: db,
                            nicknameManager: DependenciesBridge.shared.nicknameManager
                        ),
                        tx: tx
                    )
                }
                guard let nicknameEditor else { return }
                let navigationController = OWSNavigationController(rootViewController: nicknameEditor)
                self.presentFormSheet(navigationController, animated: true)
            }
        ))

        // If blocked, only show unblock as an option
        guard !threadViewModel.isBlocked else {
            section.add(.item(
                icon: .chatSettingsBlock,
                name: OWSLocalizedString(
                    "BLOCK_LIST_UNBLOCK_BUTTON",
                    comment: "Button label for the 'unblock' button"
                ),
                accessibilityIdentifier: "MemberActionSheet.unblock",
                actionBlock: { [weak self] in
                    self?.didTapUnblockThread {}
                }
            ))
            return
        }

        section.add(.item(
            icon: .chatSettingsBlock,
            name: OWSLocalizedString(
                "BLOCK_LIST_BLOCK_BUTTON",
                comment: "Button label for the 'block' button"
            ),
            accessibilityIdentifier: "MemberActionSheet.block",
            actionBlock: { [weak self] in
                guard let self = self, let fromViewController = self.fromViewController else { return }
                self.dismiss(animated: true) {
                    BlockListUIUtils.showBlockAddressActionSheet(
                        self.address,
                        from: fromViewController,
                        completion: nil
                    )
                }
            }
        ))

        if let groupViewHelper = self.groupViewHelper, groupViewHelper.isFullOrInvitedMember(address) {
            if groupViewHelper.canRemoveFromGroup(address: address) {
                section.add(.item(
                    icon: .groupMemberRemoveFromGroup,
                    name: OWSLocalizedString(
                        "CONVERSATION_SETTINGS_REMOVE_FROM_GROUP_BUTTON",
                        comment: "Label for 'remove from group' button in conversation settings view."
                    ),
                    accessibilityIdentifier: "MemberActionSheet.removeFromGroup",
                    actionBlock: { [weak self] in
                        guard let self = self else { return }
                        self.dismiss(animated: true) {
                            self.groupViewHelper?.presentRemoveFromGroupActionSheet(address: self.address)
                        }
                    }
                ))
            }
            if groupViewHelper.memberActionSheetCanMakeGroupAdmin(address: address) {
                section.add(.item(
                    icon: .groupMemberMakeGroupAdmin,
                    name: OWSLocalizedString(
                        "CONVERSATION_SETTINGS_MAKE_GROUP_ADMIN_BUTTON",
                        comment: "Label for 'make group admin' button in conversation settings view."
                    ),
                    accessibilityIdentifier: "MemberActionSheet.makeGroupAdmin",
                    actionBlock: { [weak self] in
                        guard let self = self else { return }
                        self.dismiss(animated: true) {
                            self.groupViewHelper?.memberActionSheetMakeGroupAdminWasSelected(address: self.address)
                        }
                    }
                ))
            }
            if groupViewHelper.memberActionSheetCanRevokeGroupAdmin(address: address) {
                section.add(.item(
                    icon: .groupMemberRevokeGroupAdmin,
                    name: OWSLocalizedString(
                        "CONVERSATION_SETTINGS_REVOKE_GROUP_ADMIN_BUTTON",
                        comment: "Label for 'revoke group admin' button in conversation settings view."
                    ),
                    accessibilityIdentifier: "MemberActionSheet.revokeGroupAdmin",
                    actionBlock: { [weak self] in
                        guard let self = self else { return }
                        self.dismiss(animated: true) {
                            self.groupViewHelper?.memberActionSheetRevokeGroupAdminWasSelected(address: self.address)
                        }
                    }
                ))
            }
        }

        section.add(.item(
            icon: .groupMemberAddToGroup,
            name: OWSLocalizedString(
                "ADD_TO_GROUP",
                comment: "Label for button or row which allows users to add to another group."
            ),
            accessibilityIdentifier: "MemberActionSheet.add_to_group",
            actionBlock: { [weak self] in
                guard let self = self, let fromViewController = self.fromViewController else { return }
                self.dismiss(animated: true) {
                    AddToGroupViewController.presentForUser(self.address, from: fromViewController)
                }
            }
        ))

        let isSystemContact = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return SSKEnvironment.shared.contactManagerRef.fetchSignalAccount(for: address, transaction: tx) != nil
        }
        if isSystemContact {
            section.add(.item(
                icon: .contactInfoUserInContacts,
                name: OWSLocalizedString(
                    "CONVERSATION_SETTINGS_VIEW_IS_SYSTEM_CONTACT",
                    comment: "Indicates that user is in the system contacts list."
                ),
                accessibilityIdentifier: "MemberActionSheet.contact",
                actionBlock: { [weak self] in
                    guard let self else { return }
                    self.viewSystemContactDetails(contactAddress: self.address)
                }
            ))
        } else if address.phoneNumber != nil {
            section.add(.item(
                icon: .contactInfoAddToContacts,
                name: OWSLocalizedString(
                    "CONVERSATION_SETTINGS_ADD_TO_SYSTEM_CONTACTS",
                    comment: "button in conversation settings view."
                ),
                accessibilityIdentifier: "MemberActionSheet.add_to_contacts",
                actionBlock: { [weak self] in
                    guard let self else { return }
                    self.showAddToSystemContactsActionSheet(contactAddress: self.address)
                }
            ))
        }

        section.add(.item(
            icon: .contactInfoSafetyNumber,
            name: OWSLocalizedString(
                "VERIFY_PRIVACY",
                comment: "Label for button or row which allows users to verify the safety number of another user."
            ),
            accessibilityIdentifier: "MemberActionSheet.safety_number",
            actionBlock: { [weak self] in
                guard let self = self, let fromViewController = self.fromViewController else { return }
                self.dismiss(animated: true) {
                    FingerprintViewController.present(for: self.address.aci, from: fromViewController)
                }
            }
        ))
    }

    private func viewSystemContactDetails(contactAddress: SignalServiceAddress) {
        guard let viewController = fromViewController else { return }
        let contactsViewHelper = SUIEnvironment.shared.contactsViewHelperRef

        dismiss(animated: true) {
            contactsViewHelper.presentSystemContactsFlow(
                CreateOrEditContactFlow(address: contactAddress, editImmediately: false),
                from: viewController
            )
        }
    }

    private func showAddToSystemContactsActionSheet(contactAddress: SignalServiceAddress) {
        guard let viewController = fromViewController else { return }
        let contactsViewHelper = SUIEnvironment.shared.contactsViewHelperRef

        dismiss(animated: true) {
            let actionSheet = ActionSheetController()
            let createNewTitle = OWSLocalizedString(
                "CONVERSATION_SETTINGS_NEW_CONTACT",
                comment: "Label for 'new contact' button in conversation settings view."
            )
            actionSheet.addAction(ActionSheetAction(
                title: createNewTitle,
                style: .default,
                handler: {_ in
                    contactsViewHelper.presentSystemContactsFlow(
                        CreateOrEditContactFlow(address: contactAddress),
                        from: viewController
                    )
                }
            ))

            let addToExistingTitle = OWSLocalizedString(
                "CONVERSATION_SETTINGS_ADD_TO_EXISTING_CONTACT",
                comment: "Label for 'new contact' button in conversation settings view."
            )
            actionSheet.addAction(ActionSheetAction(
                title: addToExistingTitle,
                style: .default,
                handler: { _ in
                    contactsViewHelper.presentSystemContactsFlow(
                        AddToExistingContactFlow(address: contactAddress),
                        from: viewController
                    )
                }
            ))
            actionSheet.addAction(OWSActionSheets.cancelAction)

            viewController.presentActionSheet(actionSheet)
        }
    }

    @objc
    private func recipientUpdated(notification: NSNotification) {
        guard self.isViewLoaded else { return }
        AssertIsOnMainThread()
        updateTableContents()
    }
}

extension MemberActionSheet: ConversationHeaderDelegate {
    var isGroupV1Thread: Bool { groupViewHelper?.isGroupV1Thread == true }

    func presentStoryViewController() {
        dismiss(animated: true) {
            let vc = StoryPageViewController(context: self.thread.storyContext, spoilerState: self.spoilerState)
            self.fromViewController?.present(vc, animated: true)
        }
    }

    func presentAvatarViewController() {
        guard let avatarView = avatarView, avatarView.primaryImage != nil else { return }
        guard let vc = SSKEnvironment.shared.databaseStorageRef.read(block: { readTx in
            AvatarViewController(address: self.address, renderLocalUserAsNoteToSelf: false, readTx: readTx)
        }) else { return }
        present(vc, animated: true)
    }

    func didTapBadge() {
        guard avatarView != nil else { return }
        let (profile, shortName) = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            return (
                SSKEnvironment.shared.profileManagerRef.userProfile(for: address, tx: transaction),
                SSKEnvironment.shared.contactManagerRef.displayName(for: address, tx: transaction).resolvedValue(useShortNameIfAvailable: true)
            )
        }
        guard let primaryBadge = profile?.primaryBadge?.badge else { return }
        let owner: BadgeDetailsSheet.Owner
        if address.isLocalAddress {
            owner = .local(shortName: shortName)
        } else {
            owner = .remote(shortName: shortName)
        }
        let badgeSheet = BadgeDetailsSheet(focusedBadge: primaryBadge, owner: owner)
        present(badgeSheet, animated: true, completion: nil)
    }
    func tappedConversationSearch() {}
    func didTapUnblockThread(completion: @escaping () -> Void) {
        guard let fromViewController = fromViewController else { return }
        dismiss(animated: true) {
            BlockListUIUtils.showUnblockAddressActionSheet(
                self.address,
                from: fromViewController
            ) { _ in
                completion()
            }
        }
    }
    func tappedButton() {
        dismiss(animated: true)
    }
    func didTapAddGroupDescription() {}
    var canEditConversationAttributes: Bool { false }

    var canTapThreadName: Bool { true }

    func didTapThreadName() {
        guard let contactThread = self.thread as? TSContactThread else {
            owsFailDebug("How is member sheet not showing a contact?")
            return
        }
        let sheet = ContactAboutSheet(thread: contactThread, spoilerState: spoilerState)
        dismiss(animated: true) {
            guard let fromViewController = self.fromViewController else { return }
            sheet.present(from: fromViewController)
        }
    }
}

extension MemberActionSheet: AvatarViewPresentationContextProvider {
    var conversationAvatarView: ConversationAvatarView? { avatarView }
}
