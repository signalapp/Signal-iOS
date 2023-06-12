//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import ContactsUI
import SignalUI

class MemberActionSheet: OWSTableSheetViewController {
    private var groupViewHelper: GroupViewHelper?

    var avatarView: PrimaryImageView?
    var thread: TSThread { threadViewModel.threadRecord }
    var threadViewModel: ThreadViewModel
    let address: SignalServiceAddress

    init(address: SignalServiceAddress, groupViewHelper: GroupViewHelper?) {
        self.threadViewModel = Self.fetchThreadViewModel(address: address)
        self.groupViewHelper = groupViewHelper
        self.address = address

        super.init()

        tableViewController.defaultSeparatorInsetLeading =
            OWSTableViewController2.cellHInnerMargin + 24 + OWSTableItem.iconSpacing
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    static func fetchThreadViewModel(address: SignalServiceAddress) -> ThreadViewModel {
        // Avoid opening a write transaction if we can
        guard let threadViewModel: ThreadViewModel = Self.databaseStorage.read(block: { transaction in
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
            return Self.databaseStorage.write { transaction in
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

    func present(from viewController: UIViewController) {
        fromViewController = viewController
        viewController.present(self, animated: true)
    }

    func reloadThreadViewModel() {
        threadViewModel  = Self.fetchThreadViewModel(address: address)
        updateTableContents()
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

        // If blocked, only show unblock as an option
        guard !threadViewModel.isBlocked else {
            section.add(.item(
                icon: .settingsBlock,
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
            icon: .settingsBlock,
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
                    icon: .settingsViewRemoveFromGroup,
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
                    icon: .settingsViewMakeGroupAdmin,
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
                    icon: .settingsViewRevokeGroupAdmin,
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
            icon: .settingsAddToGroup,
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

        let isSystemContact = databaseStorage.read { transaction in
            contactsManager.isSystemContact(address: address, transaction: transaction)
        }
        if isSystemContact {
            section.add(.item(
                icon: .settingsUserInContacts,
                name: OWSLocalizedString(
                    "CONVERSATION_SETTINGS_VIEW_IS_SYSTEM_CONTACT",
                    comment: "Indicates that user is in the system contacts list."
                ),
                accessibilityIdentifier: "MemberActionSheet.contact",
                actionBlock: { [weak self] in
                    self?.handleContactAction(editImmediately: false)
                }
            ))
        } else {
            section.add(.item(
                icon: .settingsAddToContacts,
                name: OWSLocalizedString(
                    "CONVERSATION_SETTINGS_ADD_TO_SYSTEM_CONTACTS",
                    comment: "button in conversation settings view."
                ),
                accessibilityIdentifier: "MemberActionSheet.add_to_contacts",
                actionBlock: { [weak self] in
                    self?.handleContactAction(editImmediately: true)
                }
            ))
        }

        section.add(.item(
            icon: .settingsViewSafetyNumber,
            name: OWSLocalizedString(
                "VERIFY_PRIVACY",
                comment: "Label for button or row which allows users to verify the safety number of another user."
            ),
            accessibilityIdentifier: "MemberActionSheet.safety_number",
            actionBlock: { [weak self] in
                guard let self = self, let fromViewController = self.fromViewController else { return }
                self.dismiss(animated: true) {
                    FingerprintViewController.present(from: fromViewController, address: self.address)
                }
            }
        ))
    }

    private func handleContactAction(editImmediately: Bool) {
        guard
            let viewController = fromViewController,
            let navigationController = viewController.navigationController
        else {
            return
        }
        self.dismiss(animated: true) {
            self.contactsViewHelper.checkEditingAuthorization(
                authorizedBehavior: .pushViewController(on: navigationController, viewController: {
                    let result = self.contactsViewHelper.contactViewController(
                        for: self.address,
                        editImmediately: editImmediately
                    )
                    self.strongSelf = self
                    result.delegate = self
                    return result
                }),
                unauthorizedBehavior: .presentError(from: viewController)
            )
        }
    }
}

extension MemberActionSheet: ConversationHeaderDelegate {
    var isGroupV1Thread: Bool { groupViewHelper?.isGroupV1Thread == true }

    func presentStoryViewController() {
        dismiss(animated: true) {
            let vc = StoryPageViewController(context: self.thread.storyContext)
            self.fromViewController?.present(vc, animated: true)
        }
    }

    func presentAvatarViewController() {
        guard let avatarView = avatarView, avatarView.primaryImage != nil else { return }
        guard let vc = databaseStorage.read(block: { readTx in
            AvatarViewController(address: self.address, renderLocalUserAsNoteToSelf: false, readTx: readTx)
        }) else { return }
        present(vc, animated: true)
    }

    func didTapBadge() {
        guard avatarView != nil else { return }
        let (profile, shortName) = databaseStorage.read { transaction in
            return (
                profileManager.getUserProfile(for: address, transaction: transaction),
                contactsManager.shortDisplayName(for: address, transaction: transaction)
            )
        }
        guard let primaryBadge = profile?.visibleBadges.first?.badge else { return }
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
}

extension MemberActionSheet: CNContactViewControllerDelegate {
    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        viewController.navigationController?.popViewController(animated: true)
        strongSelf = nil
    }
}

extension MemberActionSheet: MediaPresentationContextProvider {
    func mediaPresentationContext(item: Media, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        let mediaView: UIView
        let mediaViewShape: MediaViewShape
        switch item {
        case .gallery:
            owsFailDebug("Unexpected item")
            return nil
        case .image:
            guard let avatarView = avatarView as? ConversationAvatarView else { return nil }
            mediaView = avatarView
            if case .circular = avatarView.configuration.shape {
                mediaViewShape = .circle
            } else {
                mediaViewShape = .rectangle(0)
            }
        }

        guard let mediaSuperview = mediaView.superview else {
            owsFailDebug("mediaSuperview was unexpectedly nil")
            return nil
        }

        let presentationFrame = coordinateSpace.convert(mediaView.frame, from: mediaSuperview)

        return MediaPresentationContext(
            mediaView: mediaView,
            presentationFrame: presentationFrame,
            mediaViewShape: mediaViewShape
        )
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return nil
    }
}
