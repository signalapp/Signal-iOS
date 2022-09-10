//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import ContactsUI
import SignalUI

@objc
class MemberActionSheet: OWSTableSheetViewController {
    private var groupViewHelper: GroupViewHelper?

    var avatarView: PrimaryImageView?
    var thread: TSThread { threadViewModel.threadRecord }
    var threadViewModel: ThreadViewModel
    let address: SignalServiceAddress

    @objc
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
    @objc(presentFromViewController:)
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
        contents.addSection(topSpacerSection)

        let section = OWSTableSection()
        contents.addSection(section)

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
            section.add(.actionItem(
                icon: .settingsBlock,
                name: NSLocalizedString(
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

        section.add(.actionItem(
            icon: .settingsBlock,
            name: NSLocalizedString(
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
                        completionBlock: nil
                    )
                }
            }
        ))

        if let groupViewHelper = self.groupViewHelper, groupViewHelper.isFullOrInvitedMember(address) {
            if groupViewHelper.canRemoveFromGroup(address: address) {
                section.add(.actionItem(
                    icon: .settingsViewRemoveFromGroup,
                    name: NSLocalizedString(
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
                section.add(.actionItem(
                    icon: .settingsViewMakeGroupAdmin,
                    name: NSLocalizedString(
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
                section.add(.actionItem(
                    icon: .settingsViewRevokeGroupAdmin,
                    name: NSLocalizedString(
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

        section.add(.actionItem(
            icon: .settingsAddToGroup,
            name: NSLocalizedString(
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

        if contactsManagerImpl.supportsContactEditing {
            let isSystemContact = databaseStorage.read { transaction in
                contactsManager.isSystemContact(address: address, transaction: transaction)
            }
            if isSystemContact {
                section.add(.actionItem(
                    icon: .settingsUserInContacts,
                    name: NSLocalizedString(
                        "CONVERSATION_SETTINGS_VIEW_IS_SYSTEM_CONTACT",
                        comment: "Indicates that user is in the system contacts list."
                    ),
                    accessibilityIdentifier: "MemberActionSheet.contact",
                    actionBlock: { [weak self] in
                        guard let self = self,
                              let fromViewController = self.fromViewController,
                              let navController = fromViewController.navigationController else { return }
                        self.dismiss(animated: true) {
                            guard let contactVC = self.contactsViewHelper.contactViewController(
                                for: self.address,
                                editImmediately: false
                            ) else {
                                return owsFailDebug("unexpectedly failed to present contact view")
                             }
                             self.strongSelf = self
                             contactVC.delegate = self
                             navController.pushViewController(contactVC, animated: true)
                        }
                    }
                ))
            } else {
                section.add(.actionItem(
                    icon: .settingsAddToContacts,
                    name: NSLocalizedString(
                        "CONVERSATION_SETTINGS_ADD_TO_SYSTEM_CONTACTS",
                                            comment: "button in conversation settings view."
                    ),
                    accessibilityIdentifier: "MemberActionSheet.add_to_contacts",
                    actionBlock: { [weak self] in
                        guard let self = self,
                              let fromViewController = self.fromViewController,
                              let navController = fromViewController.navigationController else { return }
                        self.dismiss(animated: true) {
                            guard let contactVC = self.contactsViewHelper.contactViewController(
                                for: self.address,
                                editImmediately: true
                            ) else {
                                return owsFailDebug("unexpectedly failed to present contact view")
                             }
                             self.strongSelf = self
                             contactVC.delegate = self
                             navController.pushViewController(contactVC, animated: true)
                        }
                    }
                ))
            }
        }

        section.add(.actionItem(
            icon: .settingsViewSafetyNumber,
            name: NSLocalizedString(
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
}

extension MemberActionSheet: ConversationHeaderDelegate {
    var isBlockedByMigration: Bool { groupViewHelper?.isBlockedByMigration == true }
    func didTapAvatar() {
        if threadViewModel.storyState == .none || !StoryManager.areStoriesEnabled {
            presentAvatarViewController()
        } else {
            let vc = StoryPageViewController(context: thread.storyContext)
            presentFullScreen(vc, animated: true)
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
        switch item {
        case .gallery:
            owsFailDebug("Unexpected item")
            return nil
        case .image:
            guard let avatarView = self.avatarView else { return nil }
            mediaView = avatarView
        }

        guard let mediaSuperview = mediaView.superview else {
            owsFailDebug("mediaSuperview was unexpectedly nil")
            return nil
        }

        let presentationFrame = coordinateSpace.convert(mediaView.frame, from: mediaSuperview)

        return MediaPresentationContext(mediaView: mediaView, presentationFrame: presentationFrame, cornerRadius: mediaView.layer.cornerRadius)
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return nil
    }
}
