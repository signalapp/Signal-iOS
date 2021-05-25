//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import ContactsUI

@objc
class MemberActionSheet: InteractiveSheetViewController {
    let tableViewController = OWSTableViewController2()

    private var groupViewHelper: GroupViewHelper?
    private let handleContainer = UIView()

    var avatarView: UIImageView?
    var thread: TSThread { threadViewModel.threadRecord }
    let threadViewModel: ThreadViewModel
    let address: SignalServiceAddress

    override var interactiveScrollViews: [UIScrollView] { [tableViewController.tableView] }
    override var renderExternalHandle: Bool { false }

    var contentSizeHeight: CGFloat {
        tableViewController.tableView.contentSize.height + tableViewController.tableView.adjustedContentInset.totalHeight
    }
    override var minimizedHeight: CGFloat {
        return min(contentSizeHeight, maximizedHeight)
    }
    override var maximizedHeight: CGFloat {
        min(contentSizeHeight, CurrentAppContext().frame.height - (view.safeAreaInsets.top + 32))
    }

    @objc
    init(address: SignalServiceAddress, groupViewHelper: GroupViewHelper?) {
        self.threadViewModel = {
            // Avoid opening a write transaction if we can
            guard let threadViewModel: ThreadViewModel = Self.databaseStorage.read(block: { transaction in
                guard let thread = TSContactThread.getWithContactAddress(
                    address,
                    transaction: transaction
                ) else { return nil }
                return ThreadViewModel(
                    thread: thread,
                    forConversationList: false,
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
                        forConversationList: false,
                        transaction: transaction
                    )
                }
            }
            return threadViewModel
        }()
        self.groupViewHelper = groupViewHelper
        self.address = address
        super.init()

        tableViewController.shouldDeferInitialLoad = false
    }

    public required init() {
        fatalError("init() has not been implemented")
    }

    private weak var fromViewController: UIViewController?
    @objc(presentFromViewController:)
    func present(from viewController: UIViewController) {
        fromViewController = viewController
        viewController.present(self, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableViewController.defaultSeparatorInsetLeading = OWSTableViewController2.cellHInnerMargin + 24 + OWSTableItem.iconSpacing
        addChild(tableViewController)
        contentView.addSubview(tableViewController.view)
        tableViewController.view.autoPinEdgesToSuperviewEdges()

        // We add the handle directly to the content view,
        // so that it doesn't scroll with the table.
        handleContainer.backgroundColor = tableViewController.tableBackgroundColor
        contentView.addSubview(handleContainer)
        handleContainer.autoPinWidthToSuperview()
        handleContainer.autoPinEdge(toSuperviewEdge: .top)

        let handle = UIView()
        handle.backgroundColor = tableViewController.separatorColor
        handle.autoSetDimensions(to: CGSize(width: 36, height: 5))
        handle.layer.cornerRadius = 5 / 2
        handleContainer.addSubview(handle)
        handle.autoPinHeightToSuperview(withMargin: 12)
        handle.autoHCenterInSuperview()

        updateViewState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateViewState()
    }

    private var previousMinimizedHeight: CGFloat?
    private var previousSafeAreaInsets: UIEdgeInsets?
    private func updateViewState() {
        if previousSafeAreaInsets != tableViewController.view.safeAreaInsets {
            updateTableContents()
            previousSafeAreaInsets = tableViewController.view.safeAreaInsets
        }
        if minimizedHeight != previousMinimizedHeight {
            heightConstraint?.constant = minimizedHeight
            previousMinimizedHeight = minimizedHeight
        }
    }

    override func themeDidChange() {
        super.themeDidChange()
        handleContainer.backgroundColor = tableViewController.tableBackgroundColor
        updateTableContents()
    }

    // When presenting the contact view, we must retain ourselves
    // as we are the delegate. This will get released when contact
    // editing has concluded.
    private var strongSelf: MemberActionSheet?
    func updateTableContents(shouldReload: Bool = true) {
        let contents = OWSTableContents()
        defer { tableViewController.setContents(contents, shouldReload: shouldReload) }

        // Leave space at the top for the handle
        let handleSection = OWSTableSection()
        handleSection.customHeaderHeight = 50
        contents.addSection(handleSection)

        let section = OWSTableSection()
        contents.addSection(section)

        section.customHeaderView = ConversationHeaderBuilder.buildHeader(
            for: thread,
            avatarSize: 80,
            options: [.message, .videoCall, .audioCall],
            delegate: self
        )

        // If the local user, show no options.
        guard !address.isLocalAddress else { return }

        // If blocked, only show unblock as an option
        guard !contactsViewHelper.isSignalServiceAddressBlocked(address) else {
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
            if contactsManager.isSystemContact(address: address) {
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
    func tappedAvatar() {
        guard let avatarView = avatarView, avatarView.image != nil else { return }
        guard let vc = databaseStorage.read(block: { readTx in
            AvatarViewController(address: self.address, renderLocalUserAsNoteToSelf: false, readTx: readTx)
        }) else { return }
        present(vc, animated: true)
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

        return MediaPresentationContext(mediaView: mediaView, presentationFrame: presentationFrame, cornerRadius: 0)
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return nil
    }
}
