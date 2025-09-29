//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import ContactsUI
import LibSignalClient
import SignalServiceKit
import SignalUI

public enum ConversationSettingsPresentationMode: UInt {
    case `default`
    case showVerification
    case showMemberRequests
    case showAllMedia
}

// MARK: -

public protocol ConversationSettingsViewDelegate: AnyObject {
    func conversationSettingsDidRequestConversationSearch()
}

// MARK: -

// TODO: We should describe which state updates & when it is committed.
final class ConversationSettingsViewController: OWSTableViewController2, BadgeCollectionDataSource {

    public weak var conversationSettingsViewDelegate: ConversationSettingsViewDelegate?

    private(set) var threadViewModel: ThreadViewModel
    private(set) var isSystemContact: Bool
    let spoilerState: SpoilerRenderState
    let callRecords: [CallRecord]

    var thread: TSThread {
        threadViewModel.threadRecord
    }

    // Group model reflecting the last known group state.
    // This is updated as we change group membership, etc.
    var currentGroupModel: TSGroupModel? {
        guard let groupThread = thread as? TSGroupThread else {
            return nil
        }
        return groupThread.groupModel
    }

    var groupViewHelper: GroupViewHelper

    public var showVerificationOnAppear = false

    var disappearingMessagesConfiguration: OWSDisappearingMessagesConfiguration
    var avatarView: ConversationAvatarView?

    var isShowingAllGroupMembers = false
    var isShowingAllMutualGroups = false

    var shouldRefreshAttachmentsOnReappear = false

    public init(
        threadViewModel: ThreadViewModel,
        isSystemContact: Bool,
        spoilerState: SpoilerRenderState,
        callRecords: [CallRecord] = []
    ) {
        self.threadViewModel = threadViewModel
        self.isSystemContact = isSystemContact
        self.spoilerState = spoilerState
        self.callRecords = callRecords
        groupViewHelper = GroupViewHelper(threadViewModel: threadViewModel)

        disappearingMessagesConfiguration = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
            return dmConfigurationStore.fetchOrBuildDefault(for: .thread(threadViewModel.threadRecord), tx: tx)
        }

        super.init()

        AppEnvironment.shared.callService.callServiceState.addObserver(self, syncStateImmediately: false)
        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)
        SUIEnvironment.shared.contactsViewHelperRef.addObserver(self)
        groupViewHelper.delegate = self
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(identityStateDidChange(notification:)),
                                               name: .identityStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(otherUsersProfileDidChange(notification:)),
                                               name: UserProfileNotifications.otherUsersProfileDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(profileWhitelistDidChange(notification:)),
                                               name: UserProfileNotifications.profileWhitelistDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(blocklistDidChange(notification:)),
                                               name: BlockingManager.blockListDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(attachmentsAddedOrRemoved(notification:)),
            name: MediaGalleryChangeInfo.newAttachmentsAvailableNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(attachmentsAddedOrRemoved(notification:)),
            name: MediaGalleryChangeInfo.didRemoveAttachmentsNotification,
            object: nil
        )
    }

    // MARK: - Accessors

    var isGroupV1Thread: Bool {
        groupViewHelper.isGroupV1Thread
    }

    var canEditConversationAttributes: Bool {
        groupViewHelper.canEditConversationAttributes
    }

    var canEditConversationMembership: Bool {
        groupViewHelper.canEditConversationMembership
    }

    // Can local user edit group access.
    var canEditPermissions: Bool {
        groupViewHelper.canEditPermissions
    }

    var isLocalUserFullMember: Bool {
        groupViewHelper.isLocalUserFullMember
    }

    var isLocalUserFullOrInvitedMember: Bool {
        groupViewHelper.isLocalUserFullOrInvitedMember
    }

    var isGroupThread: Bool {
        thread.isGroupThread
    }

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + 24 + OWSTableItem.iconSpacing

        // The header should "extend" offscreen so that we
        // don't see the root view's background color if we scroll down.
        let backgroundTopView = UIView()
        backgroundTopView.backgroundColor = tableBackgroundColor
        tableView.addSubview(backgroundTopView)
        backgroundTopView.autoPinEdge(.leading, to: .leading, of: view, withOffset: 0)
        backgroundTopView.autoPinEdge(.trailing, to: .trailing, of: view, withOffset: 0)
        let backgroundTopSize: CGFloat = 300
        backgroundTopView.autoSetDimension(.height, toSize: backgroundTopSize)
        backgroundTopView.autoPinEdge(.bottom, to: .top, of: tableView, withOffset: 0)

        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)

        observeNotifications()

        updateRecentAttachments()
        updateMutualGroupThreads()
        reloadThreadAndUpdateContent()

        updateNavigationBar()
    }

    func updateNavigationBar() {
        guard canEditConversationAttributes, isGroupThread else {
            navigationItem.rightBarButtonItem = nil
            return
        }

        navigationItem.rightBarButtonItem = .systemItem(.edit) { [weak self] in
            guard let self else { return }
            owsAssertDebug(self.canEditConversationAttributes)
            self.showGroupAttributesView(editAction: .none)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if showVerificationOnAppear {
            showVerificationOnAppear = false
            if isGroupThread {
                showAllGroupMembers()
            } else {
                showVerificationView()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let selectedPath = tableView.indexPathForSelectedRow {
            // HACK to unselect rows when swiping back
            // http://stackoverflow.com/questions/19379510/uitableviewcell-doesnt-get-deselected-when-swiping-back-quickly
            tableView.deselectRow(at: selectedPath, animated: animated)
        }

        if shouldRefreshAttachmentsOnReappear {
            updateRecentAttachments()
        }
        updateTableContents()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { _ in } completion: { _ in
            self.updateTableContents()
        }
    }

    /// The base implementation of this reloads the table contents, which does
    /// not update header/footer views. Since we need those to be updated, we
    /// instead recreate the table contents wholesale.
    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    /// The base implementation of this reloads the table contents, which does
    /// not update header/footer views. Since we need those to be updated, we
    /// instead recreate the table contents wholesale.
    override func contentSizeCategoryDidChange() {
        super.contentSizeCategoryDidChange()
        updateTableContents()
    }

    // iOS 26 adds a large leading safe area under the side column in split
    // views. The safe area isn't updated right away so the header gets squished
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateTableContents()
    }

    // MARK: -

    private(set) var groupMemberStateMap = [SignalServiceAddress: VerificationState]()
    private(set) var sortedGroupMembers = [SignalServiceAddress]()
    func updateGroupMembers(transaction tx: DBReadTransaction) {
        guard
            let groupModel = currentGroupModel,
            !groupModel.isPlaceholder,
            let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress
        else {
            groupMemberStateMap = [:]
            sortedGroupMembers = []
            return
        }

        let groupMembership = groupModel.groupMembership
        let allMembers = groupMembership.fullMembers
        var allMembersSorted = [SignalServiceAddress]()
        var verificationStateMap = [SignalServiceAddress: VerificationState]()

        let identityManager = DependenciesBridge.shared.identityManager
        for memberAddress in allMembers {
            verificationStateMap[memberAddress] = identityManager.verificationState(for: memberAddress, tx: tx)
        }
        allMembersSorted = SSKEnvironment.shared.contactManagerImplRef.sortSignalServiceAddresses(allMembers, transaction: tx)

        var membersToRender = [SignalServiceAddress]()
        if groupMembership.isFullMember(localAddress) {
            // Make sure local user is first.
            membersToRender.insert(localAddress, at: 0)
        }
        // Admin users are second.
        let adminMembers = allMembersSorted.filter { $0 != localAddress && groupMembership.isFullMemberAndAdministrator($0) }
        membersToRender += adminMembers
        // Non-admin users are third.
        let nonAdminMembers = allMembersSorted.filter { $0 != localAddress && !groupMembership.isFullMemberAndAdministrator($0) }
        membersToRender += nonAdminMembers

        self.groupMemberStateMap = verificationStateMap
        self.sortedGroupMembers = membersToRender
    }

    func reloadThreadAndUpdateContent() {
        let didUpdate = SSKEnvironment.shared.databaseStorageRef.read { tx -> Bool in
            guard let newThread = TSThread.anyFetch(uniqueId: self.thread.uniqueId, transaction: tx) else {
                return false
            }
            let newThreadViewModel = ThreadViewModel(thread: newThread, forChatList: false, transaction: tx)
            self.threadViewModel = newThreadViewModel
            self.isSystemContact = {
                guard let contactThread = newThread as? TSContactThread else {
                    return false
                }
                let address = contactThread.contactAddress
                return SSKEnvironment.shared.contactManagerRef.fetchSignalAccount(for: address, transaction: tx) != nil
            }()
            self.groupViewHelper = GroupViewHelper(threadViewModel: newThreadViewModel)
            self.groupViewHelper.delegate = self

            self.updateGroupMembers(transaction: tx)

            return true
        }

        if !didUpdate {
            owsFailDebug("Invalid thread.")
            navigationController?.popViewController(animated: true)
            return
        }

        updateTableContents()
    }

    var lastContentWidth: CGFloat?

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Reload the table content if this view's width changes.
        var hasContentWidthChanged = false
        if let lastContentWidth = lastContentWidth,
            lastContentWidth != view.width {
            hasContentWidthChanged = true
        }

        if hasContentWidthChanged {
            updateTableContents()
        }
    }

    // MARK: -

    func didSelectGroupMember(_ memberAddress: SignalServiceAddress) {
        guard memberAddress.isValid else {
            owsFailDebug("Invalid address.")
            return
        }
        ProfileSheetSheetCoordinator(
            address: memberAddress,
            groupViewHelper: groupViewHelper,
            spoilerState: spoilerState
        )
        .presentAppropriateSheet(from: self)
    }

    func showAddToSystemContactsActionSheet(contactThread: TSContactThread) {
        let actionSheet = ActionSheetController()
        let createNewTitle = OWSLocalizedString(
            "CONVERSATION_SETTINGS_NEW_CONTACT",
            comment: "Label for 'new contact' button in conversation settings view."
        )
        actionSheet.addAction(ActionSheetAction(
            title: createNewTitle,
            style: .default,
            handler: { [weak self] _ in
                self?.presentCreateOrEditContactViewController(address: contactThread.contactAddress, editImmediately: true)
            }
        ))

        let addToExistingTitle = OWSLocalizedString(
            "CONVERSATION_SETTINGS_ADD_TO_EXISTING_CONTACT",
            comment: "Label for 'new contact' button in conversation settings view."
        )
        actionSheet.addAction(ActionSheetAction(
            title: addToExistingTitle,
            style: .default,
            handler: { [weak self] _ in
                self?.presentAddToExistingContactFlow(address: contactThread.contactAddress)
            }
        ))

        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    // MARK: - Actions

    func presentStoryViewController() {
        let vc = StoryPageViewController(context: thread.storyContext, spoilerState: spoilerState)
        present(vc, animated: true)
    }

    func didTapBadge() {
        guard avatarView != nil else { return }
        presentPrimaryBadgeSheet()
    }

    func showVerificationView() {
        guard let contactThread = thread as? TSContactThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        let contactAddress = contactThread.contactAddress
        FingerprintViewController.present(for: contactAddress.aci, from: self)
    }

    func showColorAndWallpaperSettingsView() {
        let vc = ColorAndWallpaperSettingsViewController(thread: thread)
        navigationController?.pushViewController(vc, animated: true)
    }

    func showSoundAndNotificationsSettingsView() {
        let vc = SoundAndNotificationsSettingsViewController(threadViewModel: threadViewModel)
        navigationController?.pushViewController(vc, animated: true)
    }

    func showPermissionsSettingsView() {
        let vc = GroupPermissionsSettingsViewController(threadViewModel: threadViewModel, delegate: self)
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }

    func showAllGroupMembers(revealingIndices: [IndexPath]? = nil) {
        isShowingAllGroupMembers = true
        updateForSeeAll(revealingIndices: revealingIndices)
    }

    func showAllMutualGroups(revealingIndices: [IndexPath]? = nil) {
        isShowingAllMutualGroups = true
        updateForSeeAll(revealingIndices: revealingIndices)
    }

    func updateForSeeAll(revealingIndices: [IndexPath]? = nil) {
        if let revealingIndices = revealingIndices, !revealingIndices.isEmpty, let firstIndex = revealingIndices.first {
            tableView.beginUpdates()

            // Delete the "See All" row.
            tableView.deleteRows(at: [IndexPath(row: firstIndex.row, section: firstIndex.section)], with: .top)

            // Insert the new rows.
            tableView.insertRows(at: revealingIndices, with: .top)

            updateTableContents(shouldReload: false)
            tableView.endUpdates()
        } else {
            updateTableContents()
        }
    }

    func showGroupAttributesView(editAction: GroupAttributesViewController.EditAction) {
         guard canEditConversationAttributes else {
             owsFailDebug("!canEditConversationAttributes")
             return
         }

         assert(conversationSettingsViewDelegate != nil)

         guard let groupThread = thread as? TSGroupThread else {
             owsFailDebug("Invalid thread.")
             return
         }
         let groupAttributesViewController = GroupAttributesViewController(groupThread: groupThread,
                                                                           editAction: editAction,
                                                                           delegate: self)
         navigationController?.pushViewController(groupAttributesViewController, animated: true)
     }

    func showAddMembersView() {
        guard canEditConversationMembership else {
            owsFailDebug("Can't edit membership.")
            return
        }
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        let addGroupMembersViewController = AddGroupMembersViewController(groupThread: groupThread)
        addGroupMembersViewController.addGroupMembersViewControllerDelegate = self
        navigationController?.pushViewController(addGroupMembersViewController, animated: true)
    }

    func showAddToGroupView() {
        guard let thread = thread as? TSContactThread else {
            return owsFailDebug("Tried to present for unexpected thread")
        }
        let vc = AddToGroupViewController(address: thread.contactAddress)
        presentFormSheet(OWSNavigationController(rootViewController: vc), animated: true)
    }

    func showMemberRequestsAndInvitesView() {
        guard let viewController = buildMemberRequestsAndInvitesView() else {
            owsFailDebug("Invalid thread.")
            return
        }
        navigationController?.pushViewController(viewController, animated: true)
    }

    public func buildMemberRequestsAndInvitesView() -> UIViewController? {
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return nil
        }
        let groupMemberRequestsAndInvitesViewController = GroupMemberRequestsAndInvitesViewController(
            groupThread: groupThread,
            groupViewHelper: groupViewHelper,
            spoilerState: spoilerState
        )
        groupMemberRequestsAndInvitesViewController.groupMemberRequestsAndInvitesViewControllerDelegate = self
        return groupMemberRequestsAndInvitesViewController
    }

    func showGroupLinkView() {
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            owsFailDebug("Invalid groupModel.")
            return
        }
        let groupLinkViewController = GroupLinkViewController(groupModelV2: groupModelV2)
        groupLinkViewController.groupLinkViewControllerDelegate = self
        navigationController?.pushViewController(groupLinkViewController, animated: true)
    }

    func presentCreateOrEditContactViewController(address: SignalServiceAddress, editImmediately: Bool) {
        SUIEnvironment.shared.contactsViewHelperRef.presentSystemContactsFlow(
            CreateOrEditContactFlow(address: address, editImmediately: editImmediately),
            from: self,
            completion: {
                self.updateTableContents()
            }
        )
    }

    func presentAvatarViewController() {
        guard let avatarView = avatarView, avatarView.primaryImage != nil else { return }
        guard let vc = SSKEnvironment.shared.databaseStorageRef.read(block: { readTx in
            AvatarViewController(thread: self.thread, renderLocalUserAsNoteToSelf: true, readTx: readTx)
        }) else {
            return
        }

        present(vc, animated: true)
    }

    func presentPrimaryBadgeSheet() {
        guard let contactAddress = (thread as? TSContactThread)?.contactAddress else { return }
        guard let primaryBadge = availableBadges.first?.badge else { return }
        let contactShortName = SSKEnvironment.shared.databaseStorageRef.read {
            return SSKEnvironment.shared.contactManagerRef.displayName(for: contactAddress, tx: $0).resolvedValue(useShortNameIfAvailable: true)
        }

        let badgeSheet = BadgeDetailsSheet(focusedBadge: primaryBadge, owner: .remote(shortName: contactShortName))
        present(badgeSheet, animated: true, completion: nil)
    }

    private func presentAddToExistingContactFlow(address: SignalServiceAddress) {
        SUIEnvironment.shared.contactsViewHelperRef.presentSystemContactsFlow(
            AddToExistingContactFlow(address: address),
            from: self,
            completion: {
                self.updateTableContents()
            }
        )
    }

    func didTapLeaveGroup() {
        guard canLocalUserLeaveGroupWithoutChoosingNewAdmin else {
            showReplaceAdminAlert()
            return
        }
        showLeaveGroupConfirmAlert()
    }

    func showLeaveGroupConfirmAlert(replacementAdminAci: Aci? = nil) {
        let alert = ActionSheetController(title: OWSLocalizedString("CONFIRM_LEAVE_GROUP_TITLE",
                                                                   comment: "Alert title"),
                                          message: OWSLocalizedString("CONFIRM_LEAVE_GROUP_DESCRIPTION",
                                                                     comment: "Alert body"))

        let leaveAction = ActionSheetAction(
            title: OWSLocalizedString(
                "LEAVE_BUTTON_TITLE",
                comment: "Confirmation button within contextual alert"
            ),
            style: .destructive
        ) { _ in
            self.leaveGroup(replacementAdminAci: replacementAdminAci)
        }
        alert.addAction(leaveAction)
        alert.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(alert)
    }

    func showReplaceAdminAlert() {
        let candidates = self.replacementAdminCandidates
        guard !candidates.isEmpty else {
            // TODO: We could offer a "delete group locally" option here.
            OWSActionSheets.showErrorAlert(message: OWSLocalizedString("GROUPS_CANT_REPLACE_ADMIN_ALERT_MESSAGE",
                                                                      comment: "Message for the 'can't replace group admin' alert."))
            return
        }

        let alert = ActionSheetController(
            title: OWSLocalizedString(
                "GROUPS_REPLACE_ADMIN_ALERT_TITLE",
                comment: "Title for the 'replace group admin' alert."
            ),
            message: OWSLocalizedString(
                "GROUPS_REPLACE_ADMIN_ALERT_MESSAGE",
                comment: "Message for the 'replace group admin' alert."
            )
        )

        alert.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "GROUPS_REPLACE_ADMIN_BUTTON",
                comment: "Label for the 'replace group admin' button."
            ),
            style: .default
        ) { _ in
            self.showReplaceAdminView(candidates: candidates)
        })
        alert.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(alert)
    }

    func showReplaceAdminView(candidates: Set<SignalServiceAddress>) {
        assert(!candidates.isEmpty)
        let replaceAdminViewController = ReplaceAdminViewController(candidates: candidates,
                                                                    replaceAdminViewControllerDelegate: self)
        navigationController?.pushViewController(replaceAdminViewController, animated: true)
    }

    private var canLocalUserLeaveThreadWithoutChoosingNewAdmin: Bool {
        guard thread is TSGroupThread else {
            return true
        }
        return canLocalUserLeaveGroupWithoutChoosingNewAdmin
    }

    private var canLocalUserLeaveGroupWithoutChoosingNewAdmin: Bool {
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return true
        }
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            return true
        }
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
            owsFailDebug("missing local address")
            return true
        }
        return GroupManager.canLocalUserLeaveGroupWithoutChoosingNewAdmin(
            localAci: localAci,
            groupMembership: groupModelV2.groupMembership
        )
    }

    private var replacementAdminCandidates: Set<SignalServiceAddress> {
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return []
        }
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            return []
        }
        guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress else {
            owsFailDebug("missing local address")
            return []
        }
        var candidates = groupModelV2.groupMembership.fullMembers
        candidates.remove(localAddress)
        return candidates
    }

    private func leaveGroup(replacementAdminAci: Aci? = nil) {
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        guard let navigationController = self.navigationController else {
            owsFailDebug("Invalid navigationController.")
            return
        }
        // On success, we want to pop back to the conversation view controller.
        let viewControllers = navigationController.viewControllers
        guard let index = viewControllers.firstIndex(of: self),
            index > 0 else {
                owsFailDebug("Invalid navigation stack.")
                return
        }
        let conversationViewController = viewControllers[index - 1]
        GroupManager.leaveGroupOrDeclineInviteAsyncWithUI(
            groupThread: groupThread,
            fromViewController: self,
            replacementAdminAci: replacementAdminAci
        ) {
            self.navigationController?.popToViewController(conversationViewController, animated: true)
        }
    }

    func didTapUnblockThread(completion: @escaping () -> Void = {}) {
        BlockListUIUtils.showUnblockThreadActionSheet(thread, from: self) { [weak self] _ in
            self?.reloadThreadAndUpdateContent()
            completion()
        }
    }

    func didTapBlockThread() {
        guard canLocalUserLeaveThreadWithoutChoosingNewAdmin else {
            showReplaceAdminAlert()
            return
        }
        BlockListUIUtils.showBlockThreadActionSheet(thread, from: self) { [weak self] _ in
            self?.reloadThreadAndUpdateContent()
        }
    }

    func didTapReportSpam() {
        ReportSpamUIUtils.showReportSpamActionSheet(
            thread,
            isBlocked: threadViewModel.isBlocked,
            from: self
        ) { [weak self] _ in
            self?.reloadThreadAndUpdateContent()
        }
    }

    func didTapInternalSettings() {
        let view = ConversationInternalViewController(thread: thread)
        navigationController?.pushViewController(view, animated: true)
    }

    class func muteUnmuteMenu(for threadViewModel: ThreadViewModel, actionExecuted: @escaping () -> Void) -> UIMenu {
        let menuTitle = muteUnmuteMenuTitle(for: threadViewModel)
        let actions = muteUnmuteActions(for: threadViewModel, actionExecuted: actionExecuted)
        return UIMenu(title: menuTitle ?? "", children: actions)
    }

    private class func muteUnmuteMenuTitle(for threadViewModel: ThreadViewModel) -> String? {
        guard threadViewModel.isMuted else {
            return OWSLocalizedString(
                "CONVERSATION_SETTINGS_MUTE_ACTION_SHEET_TITLE",
                comment: "Title for the mute action sheet"
            )
        }

        guard threadViewModel.mutedUntilTimestamp != ThreadAssociatedData.alwaysMutedTimestamp else {
            return OWSLocalizedString(
                "CONVERSATION_SETTINGS_MUTED_ALWAYS_UNMUTE",
                comment: "Indicates that this thread is muted forever."
            )
        }

        let now = Date()
        guard let mutedUntilDate = threadViewModel.mutedUntilDate, mutedUntilDate > now else {
            return nil
        }

        let calendar = Calendar.current
        let muteUntilComponents = calendar.dateComponents([.year, .month, .day], from: mutedUntilDate)
        let nowComponents = calendar.dateComponents([.year, .month, .day], from: now)
        let dateFormatter = DateFormatter()
        if nowComponents.year != muteUntilComponents.year
            || nowComponents.month != muteUntilComponents.month
            || nowComponents.day != muteUntilComponents.day {

            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
        } else {
            dateFormatter.dateStyle = .none
            dateFormatter.timeStyle = .short
        }

        let formatString = OWSLocalizedString(
            "CONVERSATION_SETTINGS_MUTED_UNTIL_UNMUTE_FORMAT",
            comment: "Indicates that this thread is muted until a given date or time. Embeds {{The date or time which the thread is muted until}}."
        )
        return String(format: formatString, dateFormatter.string(from: mutedUntilDate))
    }

    private class func muteUnmuteActions(
        for threadViewModel: ThreadViewModel,
        actionExecuted: @escaping () -> Void
    ) -> [UIAction] {

        guard !threadViewModel.isMuted else {
            return [UIAction(title: OWSLocalizedString(
                "CONVERSATION_SETTINGS_UNMUTE_ACTION",
                comment: "Label for button to unmute a thread."
            )) { _ in
                setThreadMutedUntilTimestamp(0, threadViewModel: threadViewModel)
                actionExecuted()
            }]
        }

        var actions = [UIAction]()
        actions.append(UIAction(title: OWSLocalizedString(
            "CONVERSATION_SETTINGS_MUTE_ONE_HOUR_ACTION",
            comment: "Label for button to mute a thread for a hour."
        )) { _ in
            setThreadMuted(threadViewModel: threadViewModel) {
                var dateComponents = DateComponents()
                dateComponents.hour = 1
                return dateComponents
            }
            actionExecuted()
        })
        actions.append(UIAction(title: OWSLocalizedString(
            "CONVERSATION_SETTINGS_MUTE_EIGHT_HOUR_ACTION",
            comment: "Label for button to mute a thread for eight hours."
        )) { _ in
            setThreadMuted(threadViewModel: threadViewModel) {
                var dateComponents = DateComponents()
                dateComponents.hour = 8
                return dateComponents
            }
            actionExecuted()
       })
        actions.append(UIAction(title: OWSLocalizedString(
            "CONVERSATION_SETTINGS_MUTE_ONE_DAY_ACTION",
            comment: "Label for button to mute a thread for a day."
        )) { _ in
            setThreadMuted(threadViewModel: threadViewModel) {
                var dateComponents = DateComponents()
                dateComponents.day = 1
                return dateComponents
            }
            actionExecuted()
       })
        actions.append(UIAction(title: OWSLocalizedString(
            "CONVERSATION_SETTINGS_MUTE_ONE_WEEK_ACTION",
            comment: "Label for button to mute a thread for a week."
        )) { _ in
            setThreadMuted(threadViewModel: threadViewModel) {
                var dateComponents = DateComponents()
                dateComponents.day = 7
                return dateComponents
            }
            actionExecuted()
        })
        actions.append(UIAction(title: OWSLocalizedString(
            "CONVERSATION_SETTINGS_MUTE_ALWAYS_ACTION",
            comment: "Label for button to mute a thread forever."
        )) { _ in
            setThreadMutedUntilTimestamp(ThreadAssociatedData.alwaysMutedTimestamp, threadViewModel: threadViewModel)
            actionExecuted()
        })
        return actions
    }

    private class func setThreadMuted(threadViewModel: ThreadViewModel, dateBlock: () -> DateComponents) {
        guard let timeZone = TimeZone(identifier: "UTC") else {
            owsFailDebug("Invalid timezone.")
            return
        }
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let dateComponents = dateBlock()
        guard let mutedUntilDate = calendar.date(byAdding: dateComponents, to: Date()) else {
            owsFailDebug("Couldn't modify date.")
            return
        }
        self.setThreadMutedUntilTimestamp(mutedUntilDate.ows_millisecondsSince1970, threadViewModel: threadViewModel)
    }

    private class func setThreadMutedUntilTimestamp(_ value: UInt64, threadViewModel: ThreadViewModel) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            threadViewModel.associatedData.updateWith(mutedUntilTimestamp: value, updateStorageService: true, transaction: transaction)
        }
    }

    func showMediaGallery() {
        Logger.debug("")

        let tileVC = AllMediaViewController(
            thread: thread,
            spoilerState: spoilerState,
            name: threadViewModel.name
        )
        navigationController?.pushViewController(tileVC, animated: true)
    }

    func showMediaPageView(for attachmentStream: ReferencedAttachmentStream) {
        guard let vc = MediaPageViewController(
            initialMediaAttachment: attachmentStream,
            thread: thread,
            spoilerState: spoilerState
        ) else {
            // Failed to load the item. Could be because it was deleted just as
            // we tried to show it.
            return
        }

        present(vc, animated: true)
    }

    let maximumRecentMedia = 4
    private(set) var recentMedia = OrderedDictionary<
        AttachmentReferenceId,
        (attachment: ReferencedAttachmentStream, imageView: UIImageView)
    >() {
        didSet { AssertIsOnMainThread() }
    }

    private lazy var mediaGalleryFinder = MediaGalleryAttachmentFinder(
        threadId: thread.grdbId!.int64Value,
        filter: .defaultMediaType(for: AllMediaCategory.defaultValue)
    )

    func updateRecentAttachments() {
        let recentAttachments = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            mediaGalleryFinder.recentMediaAttachments(limit: maximumRecentMedia, tx: transaction)
        }
        recentMedia = recentAttachments.reduce(into: OrderedDictionary(), { result, attachment in
            guard let attachmentStream = attachment.asReferencedStream else {
                return owsFailDebug("Unexpected type of attachment")
            }

            let imageView = UIImageView()
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 4
            imageView.contentMode = .scaleAspectFill

            Task {
                imageView.image = await attachmentStream.attachmentStream.thumbnailImage(quality: .small)
            }

            result.append(
                key: attachmentStream.reference.referenceId,
                value: (attachmentStream, imageView)
            )
        })
        shouldRefreshAttachmentsOnReappear = false
    }

    private(set) var mutualGroupThreads = [TSGroupThread]() {
        didSet { AssertIsOnMainThread() }
    }
    private(set) var hasGroupThreads = false {
        didSet { AssertIsOnMainThread() }
    }
    func updateMutualGroupThreads() {
        guard let contactThread = thread as? TSContactThread else { return }
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            self.hasGroupThreads = ThreadFinder().existsGroupThread(transaction: transaction)
            self.mutualGroupThreads = TSGroupThread.groupThreads(
                with: contactThread.contactAddress,
                transaction: transaction
            ).filter { $0.isLocalUserFullMember && $0.shouldThreadBeVisible }
        }
    }

    func tappedConversationSearch() {
        conversationSettingsViewDelegate?.conversationSettingsDidRequestConversationSearch()
    }

    // MARK: - Notifications

    @objc
    private func blocklistDidChange(notification: Notification) {
        AssertIsOnMainThread()
        reloadThreadAndUpdateContent()
    }

    @objc
    private func identityStateDidChange(notification: Notification) {
        AssertIsOnMainThread()

        updateTableContents()
    }

    @objc
    private func otherUsersProfileDidChange(notification: Notification) {
        AssertIsOnMainThread()

        guard let address = notification.userInfo?[UserProfileNotifications.profileAddressKey] as? SignalServiceAddress,
            address.isValid else {
                owsFailDebug("Missing or invalid address.")
                return
        }
        guard let contactThread = thread as? TSContactThread else {
            return
        }

        if contactThread.contactAddress == address {
            updateTableContents()
        }
    }

    @objc
    private func profileWhitelistDidChange(notification: Notification) {
        AssertIsOnMainThread()

        // If profile whitelist just changed, we may need to refresh the view.
        if let address = notification.userInfo?[UserProfileNotifications.profileAddressKey] as? SignalServiceAddress,
            let contactThread = thread as? TSContactThread,
            contactThread.contactAddress == address {
            updateTableContents()
        }

        if let groupId = notification.userInfo?[UserProfileNotifications.profileGroupIdKey] as? Data,
            let groupThread = thread as? TSGroupThread,
            groupThread.groupModel.groupId == groupId {
            updateTableContents()
        }
    }

    @objc
    private func attachmentsAddedOrRemoved(notification: Notification) {
        AssertIsOnMainThread()

        let attachments = notification.object as! [MediaGalleryChangeInfo]
        guard attachments.contains(where: { $0.threadGrdbId == thread.sqliteRowId }) else {
            return
        }

        if view.window == nil {
            // If we're currently hidden (in particular, behind the All Media view), defer this update.
            shouldRefreshAttachmentsOnReappear = true
        } else {
            updateRecentAttachments()
            updateTableContents()
        }
    }

    // MARK: - BadgeCollectionDataSource

    // These are updated when building the table contents
    // Selected badge index is unused, but a protocol requirement.
    // TODO: Adjust ConversationBadgeDataSource to remove requirement for a readwrite selectedBadgeIndex
    // when selection behavior is non-mutating
    var availableBadges: [OWSUserProfileBadgeInfo] = []
    var selectedBadgeIndex = 0
}

// MARK: -

extension ConversationSettingsViewController: ContactsViewHelperObserver {

    func contactsViewHelperDidUpdateContacts() {
        updateTableContents()
    }
}

// MARK: -

extension ConversationSettingsViewController: GroupAttributesViewControllerDelegate {
    func groupAttributesDidUpdate() {
        reloadThreadAndUpdateContent()
    }
}

// MARK: -

extension ConversationSettingsViewController: AddGroupMembersViewControllerDelegate {
    func addGroupMembersViewDidUpdate() {
        reloadThreadAndUpdateContent()
    }
}

// MARK: -

extension ConversationSettingsViewController: GroupMemberRequestsAndInvitesViewControllerDelegate {
    func requestsAndInvitesViewDidUpdate() {
        reloadThreadAndUpdateContent()
    }
}

// MARK: -

extension ConversationSettingsViewController: GroupLinkViewControllerDelegate {
    func groupLinkViewViewDidUpdate() {
        reloadThreadAndUpdateContent()
    }
}

// MARK: -

extension ConversationSettingsViewController: GroupViewHelperDelegate {
    func groupViewHelperDidUpdateGroup() {
        reloadThreadAndUpdateContent()
    }

    var fromViewController: UIViewController? {
        return self
    }
}

// MARK: -

extension ConversationSettingsViewController: ReplaceAdminViewControllerDelegate {
    func replaceAdmin(newAdminAci: Aci) {
        showLeaveGroupConfirmAlert(replacementAdminAci: newAdminAci)
    }
}

extension ConversationSettingsViewController: MediaPresentationContextProvider {
    func mediaPresentationContext(item: Media, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        let mediaView: UIView
        let mediaViewShape: MediaViewShape
        switch item {
        case .gallery(let galleryItem):
            guard let imageView = recentMedia[galleryItem.attachmentStream.reference.referenceId]?.imageView else { return nil }
            mediaView = imageView
            mediaViewShape = .rectangle(imageView.layer.cornerRadius)
        case .image:
            guard let avatarView = avatarView else { return nil }
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
        let clippingAreaInsets = UIEdgeInsets(top: tableView.adjustedContentInset.top, leading: 0, bottom: 0, trailing: 0)

        return MediaPresentationContext(
            mediaView: mediaView,
            presentationFrame: presentationFrame,
            mediaViewShape: mediaViewShape,
            clippingAreaInsets: clippingAreaInsets
        )
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return nil
    }
}

extension ConversationSettingsViewController: GroupPermissionsSettingsDelegate {
    func groupPermissionSettingsDidUpdate() {
        reloadThreadAndUpdateContent()
    }
}

extension ConversationSettingsViewController: DatabaseChangeDelegate {

    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        if databaseChanges.didUpdate(tableName: TSGroupMember.databaseTableName) {
            updateMutualGroupThreads()
            updateTableContents()
        }
    }

    public func databaseChangesDidUpdateExternally() {
        updateRecentAttachments()
        updateMutualGroupThreads()
        updateTableContents()
    }

    public func databaseChangesDidReset() {
        updateRecentAttachments()
        updateMutualGroupThreads()
        updateTableContents()
    }
}

extension ConversationSettingsViewController: CallServiceStateObserver {
    func didUpdateCall(from oldValue: SignalCall?, to newValue: SignalCall?) {
        updateTableContents()
    }
}
