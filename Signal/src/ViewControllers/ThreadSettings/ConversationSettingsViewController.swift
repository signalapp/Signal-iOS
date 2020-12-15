//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import UIKit
import ContactsUI

@objc
public enum ConversationSettingsPresentationMode: UInt {
    case `default`
    case showVerification
    case showMemberRequests
    case showAllMedia
}

// MARK: -

@objc
public protocol ConversationSettingsViewDelegate: class {

    func conversationColorWasUpdated()

    func conversationSettingsDidUpdate()

    func conversationSettingsDidRequestConversationSearch()

    func popAllConversationSettingsViews(completion: (() -> Void)?)
}

// MARK: -

// TODO: We should describe which state updates & when it is committed.
@objc
class ConversationSettingsViewController: OWSTableViewController {

    @objc
    public weak var conversationSettingsViewDelegate: ConversationSettingsViewDelegate?

    private var threadViewModel: ThreadViewModel

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

    @objc
    public var showVerificationOnAppear = false

    var disappearingMessagesConfiguration: OWSDisappearingMessagesConfiguration
    var avatarView: UIImageView?
    let disappearingMessagesDurationLabel = UILabel()

    // This is currently disabled behind a feature flag.
    private var colorPicker: ColorPicker?

    var isShowingAllGroupMembers = false

    @objc
    public required init(threadViewModel: ThreadViewModel) {
        self.threadViewModel = threadViewModel
        groupViewHelper = GroupViewHelper(threadViewModel: threadViewModel)

        disappearingMessagesConfiguration = Self.databaseStorage.read { transaction in
            OWSDisappearingMessagesConfiguration.fetchOrBuildDefault(with: threadViewModel.threadRecord,
                                                                     transaction: transaction)
        }

        super.init()

        contactsViewHelper.addObserver(self)
        groupViewHelper.delegate = self
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(identityStateDidChange(notification:)),
                                               name: .identityStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(otherUsersProfileDidChange(notification:)),
                                               name: .otherUsersProfileDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(profileWhitelistDidChange(notification:)),
                                               name: .profileWhitelistDidChange,
                                               object: nil)
    }

    // MARK: - Accessors

    var canEditConversationAttributes: Bool {
        return groupViewHelper.canEditConversationAttributes
    }

    var canEditConversationMembership: Bool {
        return groupViewHelper.canEditConversationMembership
    }

    // Can local user edit group access.
    var canEditConversationAccess: Bool {
        return groupViewHelper.canEditConversationAccess
    }

    var isLocalUserFullMember: Bool {
        return groupViewHelper.isLocalUserFullMember
    }

    var isLocalUserFullOrInvitedMember: Bool {
        return groupViewHelper.isLocalUserFullOrInvitedMember
    }

    var isGroupThread: Bool {
        return thread.isGroupThread
    }

    var disappearingMessagesDurations: [NSNumber] {
        return OWSDisappearingMessagesConfiguration.validDurationsSeconds()
    }

    class var headerBackgroundColor: UIColor {
        return (Theme.isDarkThemeEnabled ? Theme.tableViewBackgroundColor : Theme.tableCellBackgroundColor)
    }

    // MARK: - View Lifecycle

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        if isGroupThread {
            updateNavigationBar()
        } else {
            self.title = NSLocalizedString(
                "CONVERSATION_SETTINGS_CONTACT_INFO_TITLE", comment: "Navbar title when viewing settings for a 1-on-1 thread")
        }

        self.useThemeBackgroundColors = true
        tableView.estimatedRowHeight = 45
        tableView.rowHeight = UITableView.automaticDimension

        // The header should "extend" offscreen so that we
        // don't see the root view's background color if we scroll down.
        let backgroundTopView = UIView()
        backgroundTopView.backgroundColor = Self.headerBackgroundColor
        tableView.addSubview(backgroundTopView)
        backgroundTopView.autoPinEdge(.leading, to: .leading, of: view, withOffset: 0)
        backgroundTopView.autoPinEdge(.trailing, to: .trailing, of: view, withOffset: 0)
        let backgroundTopSize: CGFloat = 300
        backgroundTopView.autoSetDimension(.height, toSize: backgroundTopSize)
        backgroundTopView.autoPinEdge(.bottom, to: .top, of: tableView, withOffset: 0)

        disappearingMessagesDurationLabel.setAccessibilityIdentifier(in: self, name: "disappearingMessagesDurationLabel")

        if DebugFlags.shouldShowColorPicker {
            let colorPicker = ColorPicker(thread: self.thread)
            colorPicker.delegate = self
            self.colorPicker = colorPicker
        }

        observeNotifications()

        reloadThreadAndUpdateContent()

        updateNavigationBar()
    }

    func updateNavigationBar() {
        if isGroupThread, canEditConversationAttributes {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("CONVERSATION_SETTINGS_EDIT_GROUP",
                                                                                         comment: "Label for the 'edit group' button in conversation settings view."),
                                                                style: .plain, target: self, action: #selector(editGroupButtonWasPressed))
        } else {
            navigationItem.rightBarButtonItem = nil
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

        updateTableContents()
    }

    // MARK: -

    func reloadThreadAndUpdateContent() {
        let didUpdate = self.databaseStorage.read { transaction -> Bool in
            guard let newThread = TSThread.anyFetch(uniqueId: self.thread.uniqueId,
                                                    transaction: transaction) else {
                return false
            }
            let newThreadViewModel = ThreadViewModel(thread: newThread, transaction: transaction)
            self.threadViewModel = newThreadViewModel
            self.groupViewHelper = GroupViewHelper(threadViewModel: newThreadViewModel)
            self.groupViewHelper.delegate = self
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
        let memberActionSheet = MemberActionSheet(address: memberAddress, groupViewHelper: groupViewHelper)
        memberActionSheet.present(fromViewController: self)
    }

    func showAddToSystemContactsActionSheet(contactThread: TSContactThread) {
        let actionSheet = ActionSheetController()
        let createNewTitle = NSLocalizedString("CONVERSATION_SETTINGS_NEW_CONTACT",
                                               comment: "Label for 'new contact' button in conversation settings view.")
        actionSheet.addAction(ActionSheetAction(title: createNewTitle,
                                                style: .default,
                                                handler: { [weak self] _ in
                                                    self?.presentContactViewController()
        }))

        let addToExistingTitle = NSLocalizedString("CONVERSATION_SETTINGS_ADD_TO_EXISTING_CONTACT",
                                                   comment: "Label for 'new contact' button in conversation settings view.")
        actionSheet.addAction(ActionSheetAction(title: addToExistingTitle,
                                                style: .default,
                                                handler: { [weak self] _ in
                                                    self?.presentAddToContactViewController(address:
                                                        contactThread.contactAddress)
        }))

        actionSheet.addAction(OWSActionSheets.cancelAction)

        self.presentActionSheet(actionSheet)
    }

    // MARK: -

    private var hasUnsavedChangesToDisappearingMessagesConfiguration: Bool {
        return databaseStorage.uiRead { transaction in
            if let groupThread = self.thread as? TSGroupThread {
                guard let latestThread = TSGroupThread.fetch(groupId: groupThread.groupModel.groupId, transaction: transaction) else {
                    // Thread no longer exists.
                    return false
                }
                guard latestThread.isLocalUserMemberOfAnyKind else {
                    // Local user is no longer in group, e.g. perhaps they just blocked it.
                    return false
                }
            }
            return self.disappearingMessagesConfiguration.hasChanged(with: transaction)
        }
    }

    // MARK: - Actions

    @objc func conversationNameTouched(sender: UIGestureRecognizer) {
        if !canEditConversationAttributes {
            owsFailDebug("failure: !self.canEditConversationAttributes")
            return
        }
        guard let avatarView = avatarView else {
            owsFailDebug("Missing avatarView.")
            return
        }

        if sender.state == .recognized {
            if isGroupThread {
                if avatarView.containsGestureLocation(sender) {
                    showGroupAttributesView(editAction: .avatar)
                } else {
                    showGroupAttributesView(editAction: .name)
                }
            } else {
                if contactsManager.supportsContactEditing {
                    presentContactViewController()
                }
            }
        }
    }

    func showShareProfileAlert() {
        profileManager.presentAddThread(toProfileWhitelist: thread,
                                        from: self) {
                                            self.updateTableContents()
        }
    }

    func showVerificationView() {
        guard let contactThread = thread as? TSContactThread else {
            owsFailDebug("Invalid thread.")
            return
        }
        let contactAddress = contactThread.contactAddress
        assert(contactAddress.isValid)
        FingerprintViewController.present(from: self, address: contactAddress)
    }

    func showSoundSettingsView() {
        let vc = OWSSoundSettingsViewController()
        vc.thread = thread
        navigationController?.pushViewController(vc, animated: true)
    }

    func showAllGroupMembers() {
        isShowingAllGroupMembers = true
        updateTableContents()
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

    func showGroupAttributesAccessView() {

        guard canEditConversationAccess else {
            owsFailDebug("!canEditConversationAccess")
            return
        }
        guard let groupThread = thread as? TSGroupThread,
            let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
                owsFailDebug("Invalid thread.")
                return
        }

        let currentValue = groupModelV2.access.attributes

        let alert = ActionSheetController(title: NSLocalizedString("CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS",
                                                                   comment: "Label for 'edit attributes access' action in conversation settings view."),
                                          message: NSLocalizedString("CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS_ALERT_DESCRIPTION",
                                                                     comment: "Description for the 'edit group attributes access' alert."))

        let memberAction = ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS_ALERT_MEMBERS_BUTTON",
                                                                      comment: "Label for button that sets 'group attributes access' to 'members-only'."),
                                             accessibilityIdentifier: UIView.accessibilityIdentifier(in: self,
                                                                                                     name: "group_attributes_access_members"),
                                             style: .default) { _ in
                                                self.setGroupAttributesAccess(groupModelV2: groupModelV2,
                                                                              access: .member)
        }
        if currentValue == .member {
            memberAction.trailingIcon = .checkCircle
        }
        alert.addAction(memberAction)

        let adminAction = ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS_ALERT_ADMINISTRATORS_BUTTON",
                                                                     comment: "Label for button that sets 'group attributes access' to 'administrators-only'."),
                                            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self,
                                                                                                    name: "group_attributes_access_administrators"),
                                            style: .default) { _ in
                                                self.setGroupAttributesAccess(groupModelV2: groupModelV2,
                                                                              access: .administrator)
        }
        if currentValue == .administrator {
            adminAction.trailingIcon = .checkCircle
        }
        alert.addAction(adminAction)

        alert.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(alert)
    }

    private func setGroupAttributesAccess(groupModelV2: TSGroupModelV2,
                                          access: GroupV2Access) {
        GroupViewUtils.updateGroupWithActivityIndicator(fromViewController: self,
                                                        updatePromiseBlock: {
                                                            self.setGroupAttributesAccessPromise(groupModelV2: groupModelV2,
                                                                                                 access: access)
        },
                                                        completion: { [weak self] _ in
                                                            self?.reloadThreadAndUpdateContent()
        })
    }

    private func setGroupAttributesAccessPromise(groupModelV2: TSGroupModelV2,
                                                 access: GroupV2Access) -> Promise<Void> {
        let thread = self.thread

        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: thread,
                                                         description: "Update group attributes access")
        }.map(on: .global()) {
            // We're sending a message, so we're accepting any pending message request.
            ThreadUtil.addToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction(thread: thread)
        }.then(on: .global()) {
            GroupManager.changeGroupAttributesAccessV2(groupModel: groupModelV2,
                                                       access: access)
        }.asVoid()
    }

    func showGroupMembershipAccessView() {

        guard canEditConversationAccess else {
            owsFailDebug("!canEditConversationAccess")
            return
        }
        guard let groupThread = thread as? TSGroupThread,
            let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
                owsFailDebug("Invalid thread.")
                return
        }

        let currentValue = groupModelV2.access.members

        let alert = ActionSheetController(title: NSLocalizedString("CONVERSATION_SETTINGS_EDIT_MEMBERSHIP_ACCESS",
                                                                   comment: "Label for 'edit membership access' action in conversation settings view."),
                                          message: NSLocalizedString("CONVERSATION_SETTINGS_EDIT_MEMBERSHIP_ACCESS_ALERT_DESCRIPTION",
                                                                     comment: "Description for the 'edit group membership access' alert."))

        let memberAction = ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_EDIT_MEMBERSHIP_ACCESS_ALERT_MEMBERS_BUTTON",
                                                                      comment: "Label for button that sets 'group membership access' to 'members-only'."),
                                             accessibilityIdentifier: UIView.accessibilityIdentifier(in: self,
                                                                                                     name: "group_membership_access_members"),
                                             style: .default) { _ in
                                                self.setGroupMembershipAccess(groupModelV2: groupModelV2,
                                                                              access: .member)
        }
        if currentValue == .member {
            memberAction.trailingIcon = .checkCircle
        }
        alert.addAction(memberAction)

        let adminAction = ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_EDIT_MEMBERSHIP_ACCESS_ALERT_ADMINISTRATORS_BUTTON",
                                                                     comment: "Label for button that sets 'group membership access' to 'administrators-only'."),
                                            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self,
                                                                                                    name: "group_membership_access_administrators"),
                                            style: .default) { _ in
                                                self.setGroupMembershipAccess(groupModelV2: groupModelV2,
                                                                              access: .administrator)
        }
        if currentValue == .administrator {
            adminAction.trailingIcon = .checkCircle
        }
        alert.addAction(adminAction)

        alert.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(alert)
    }

    private func setGroupMembershipAccess(groupModelV2: TSGroupModelV2,
                                          access: GroupV2Access) {
        GroupViewUtils.updateGroupWithActivityIndicator(fromViewController: self,
                                                        updatePromiseBlock: {
                                                            self.setGroupMembershipAccessPromise(groupModelV2: groupModelV2,
                                                                                                 access: access)
        },
                                                        completion: { [weak self] _ in
                                                            self?.reloadThreadAndUpdateContent()
        })
    }

    private func setGroupMembershipAccessPromise(groupModelV2: TSGroupModelV2,
                                                 access: GroupV2Access) -> Promise<Void> {
        let thread = self.thread

        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: thread,
                                                         description: "Update group membership access")
        }.map(on: .global()) {
            // We're sending a message, so we're accepting any pending message request.
            ThreadUtil.addToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction(thread: thread)
        }.then(on: .global()) {
            GroupManager.changeGroupMembershipAccessV2(groupModel: groupModelV2,
                                                       access: access)
        }.asVoid()
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

    func showMemberRequestsAndInvitesView() {
        guard let viewController = buildMemberRequestsAndInvitesView() else {
            owsFailDebug("Invalid thread.")
            return
        }
        navigationController?.pushViewController(viewController, animated: true)
    }

    @objc
    public func buildMemberRequestsAndInvitesView() -> UIViewController? {
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return nil
        }
        let groupMemberRequestsAndInvitesViewController = GroupMemberRequestsAndInvitesViewController(groupThread: groupThread,
                                                                                                      groupViewHelper: groupViewHelper)
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

    func presentContactViewController() {
        if !contactsManager.supportsContactEditing {
            owsFailDebug("Contact editing not supported")
            return
        }
        guard let contactThread = thread as? TSContactThread else {
            owsFailDebug("Invalid thread.")
            return
        }

        guard let contactViewController =
            contactsViewHelper.contactViewController(for: contactThread.contactAddress, editImmediately: true) else {
                owsFailDebug("Unexpectedly missing contact VC")
                return
        }

        contactViewController.delegate = self
        navigationController?.pushViewController(contactViewController, animated: true)
    }

    private func presentAddToContactViewController(address: SignalServiceAddress) {

        if !contactsManager.supportsContactEditing {
            // Should not expose UI that lets the user get here.
            owsFailDebug("Contact editing not supported.")
            return
        }

        if !contactsManager.isSystemContactsAuthorized {
            contactsViewHelper.presentMissingContactAccessAlertController(from: self)
            return
        }

        let viewController = OWSAddToContactViewController(address: address)
        navigationController?.pushViewController(viewController, animated: true)
    }

    func didTapLeaveGroup() {
        guard canLocalUserLeaveGroupWithoutChoosingNewAdmin else {
            showReplaceAdminAlert()
            return
        }
        showLeaveGroupConfirmAlert()
    }

    func showLeaveGroupConfirmAlert(replacementAdminUuid: UUID? = nil) {
        let alert = ActionSheetController(title: NSLocalizedString("CONFIRM_LEAVE_GROUP_TITLE",
                                                                   comment: "Alert title"),
                                          message: NSLocalizedString("CONFIRM_LEAVE_GROUP_DESCRIPTION",
                                                                     comment: "Alert body"))

        let leaveAction = ActionSheetAction(title: NSLocalizedString("LEAVE_BUTTON_TITLE",
                                                                     comment: "Confirmation button within contextual alert"),
                                            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "leave_group_confirm"),
                                            style: .destructive) { _ in
                                                self.leaveGroup(replacementAdminUuid: replacementAdminUuid)
        }
        alert.addAction(leaveAction)
        alert.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(alert)
    }

    func showReplaceAdminAlert() {
        let candidates = self.replacementAdminCandidates
        guard !candidates.isEmpty else {
            // TODO: We could offer a "delete group locally" option here.
            OWSActionSheets.showErrorAlert(message: NSLocalizedString("GROUPS_CANT_REPLACE_ADMIN_ALERT_MESSAGE",
                                                                      comment: "Message for the 'can't replace group admin' alert."))
            return
        }

        let alert = ActionSheetController(title: NSLocalizedString("GROUPS_REPLACE_ADMIN_ALERT_TITLE",
                                                                   comment: "Title for the 'replace group admin' alert."),
                                          message: NSLocalizedString("GROUPS_REPLACE_ADMIN_ALERT_MESSAGE",
                                                                     comment: "Message for the 'replace group admin' alert."))

        alert.addAction(ActionSheetAction(title: NSLocalizedString("GROUPS_REPLACE_ADMIN_BUTTON",
                                                                   comment: "Label for the 'replace group admin' button."),
                                          accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "replace_admin_alert"),
                                          style: .default) { _ in
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

    private var canLocalUserLeaveGroupWithoutChoosingNewAdmin: Bool {
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return true
        }
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            return true
        }
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("missing local address")
            return true
        }
        return GroupManager.canLocalUserLeaveGroupWithoutChoosingNewAdmin(localAddress: localAddress,
                                                                          groupMembership: groupModelV2.groupMembership)
    }

    private var replacementAdminCandidates: Set<SignalServiceAddress> {
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Invalid thread.")
            return []
        }
        guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
            return []
        }
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("missing local address")
            return []
        }
        var candidates = groupModelV2.groupMembership.fullMembers
        candidates.remove(localAddress)
        return candidates
    }

    private func leaveGroup(replacementAdminUuid: UUID? = nil) {
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
        GroupManager.leaveGroupOrDeclineInviteAsyncWithUI(groupThread: groupThread,
                                                          fromViewController: self,
                                                          replacementAdminUuid: replacementAdminUuid) {
                                                            self.navigationController?.popToViewController(conversationViewController,
                                                                                                           animated: true)
        }
    }

    @objc
    func disappearingMessagesSwitchValueDidChange(_ sender: UISwitch) {
        assert(canEditConversationAttributes)

        toggleDisappearingMessages(sender.isOn)

        updateTableContents()
    }

    func didTapUnblockGroup() {
        let isCurrentlyBlocked = blockingManager.isThreadBlocked(thread)
        if !isCurrentlyBlocked {
            owsFailDebug("Not blocked.")
            return
        }
        BlockListUIUtils.showUnblockThreadActionSheet(thread, from: self) { [weak self] _ in
            self?.updateTableContents()
        }
    }

    func didTapBlockGroup() {
        let isCurrentlyBlocked = blockingManager.isThreadBlocked(thread)
        if isCurrentlyBlocked {
            owsFailDebug("Already blocked.")
            return
        }
        BlockListUIUtils.showBlockThreadActionSheet(thread, from: self) { [weak self] _ in
            self?.updateTableContents()
        }
    }

    private func toggleDisappearingMessages(_ flag: Bool) {
        assert(canEditConversationAttributes)

        self.disappearingMessagesConfiguration = self.disappearingMessagesConfiguration.copy(withIsEnabled: flag)

        updateTableContents()
    }

    @objc
    func durationSliderDidChange(_ slider: UISlider) {
        assert(canEditConversationAttributes)

        let values = self.disappearingMessagesDurations.map { $0.uint32Value }
        let maxValue = values.count - 1
        let index = Int(slider.value + 0.5).clamp(0, maxValue)
        if !slider.isTracking {
            // Snap the slider to a valid value unless the user
            // is still interacting with the control.
            slider.setValue(Float(index), animated: true)
        }
        guard let durationSeconds = values[safe: index] else {
            owsFailDebug("Invalid index: \(index)")
            return
        }
        self.disappearingMessagesConfiguration =
            self.disappearingMessagesConfiguration.copyAsEnabled(withDurationSeconds: durationSeconds)

        updateDisappearingMessagesDurationLabel()
    }

    func updateDisappearingMessagesDurationLabel() {
        if disappearingMessagesConfiguration.isEnabled {
            let keepForFormat = NSLocalizedString("KEEP_MESSAGES_DURATION",
                                                  comment: "Slider label embeds {{TIME_AMOUNT}}, e.g. '2 hours'. See *_TIME_AMOUNT strings for examples.")
            disappearingMessagesDurationLabel.text = String(format: keepForFormat, disappearingMessagesConfiguration.durationString)
        } else {
            disappearingMessagesDurationLabel.text
                = NSLocalizedString("KEEP_MESSAGES_FOREVER", comment: "Slider label when disappearing messages is off")
        }

        disappearingMessagesDurationLabel.setNeedsLayout()
        disappearingMessagesDurationLabel.superview?.setNeedsLayout()
    }

    func showMuteUnmuteActionSheet() {
        // The "unmute" action sheet has no title or message; the
        // action label speaks for itself.
        var title: String?
        var message: String?
        if !thread.isMuted {
            title = NSLocalizedString(
                "CONVERSATION_SETTINGS_MUTE_ACTION_SHEET_TITLE", comment: "Title of the 'mute this thread' action sheet.")
            message = NSLocalizedString(
                "MUTE_BEHAVIOR_EXPLANATION", comment: "An explanation of the consequences of muting a thread.")
        }

        let actionSheet = ActionSheetController(title: title, message: message)

        if thread.isMuted {
            let action =
                ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_UNMUTE_ACTION",
                                                           comment: "Label for button to unmute a thread."),
                                  accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "unmute"),
                                  style: .destructive) { [weak self] _ in
                                    self?.setThreadMutedUntilDate(nil)
            }
            actionSheet.addAction(action)
        } else {
            #if DEBUG
            actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_MUTE_ONE_MINUTE_ACTION",
                                                                             comment: "Label for button to mute a thread for a minute."),
                                                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "mute_1_minute"),
                                                    style: .destructive) { [weak self] _ in
                                                        self?.setThreadMuted {
                                                            var dateComponents = DateComponents()
                                                            dateComponents.minute = 1
                                                            return dateComponents
                                                        }
            })
            #endif
            actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_MUTE_ONE_HOUR_ACTION",
                                                                             comment: "Label for button to mute a thread for a hour."),
                                                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "mute_1_hour"),
                                                    style: .destructive) { [weak self] _ in
                                                        self?.setThreadMuted {
                                                            var dateComponents = DateComponents()
                                                            dateComponents.hour = 1
                                                            return dateComponents
                                                        }
            })
            actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_MUTE_ONE_DAY_ACTION",
                                                                             comment: "Label for button to mute a thread for a day."),
                                                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "mute_1_day"),
                                                    style: .destructive) { [weak self] _ in
                                                        self?.setThreadMuted {
                                                            var dateComponents = DateComponents()
                                                            dateComponents.day = 1
                                                            return dateComponents
                                                        }
            })
            actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_MUTE_ONE_WEEK_ACTION",
                                                                             comment: "Label for button to mute a thread for a week."),
                                                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "mute_1_week"),
                                                    style: .destructive) { [weak self] _ in
                                                        self?.setThreadMuted {
                                                            var dateComponents = DateComponents()
                                                            dateComponents.day = 7
                                                            return dateComponents
                                                        }
            })
            actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("CONVERSATION_SETTINGS_MUTE_ONE_YEAR_ACTION",
                                                                             comment: "Label for button to mute a thread for a year."),
                                                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "mute_1_year"),
                                                    style: .destructive) { [weak self] _ in
                                                        self?.setThreadMuted {
                                                            var dateComponents = DateComponents()
                                                            dateComponents.year = 1
                                                            return dateComponents
                                                        }
            })
        }

        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func setThreadMuted(dateBlock: () -> DateComponents) {
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
        self.setThreadMutedUntilDate(mutedUntilDate)
    }

    private func setThreadMutedUntilDate(_ value: Date?) {
        databaseStorage.write { transaction in
            self.thread.updateWithMuted(until: value, transaction: transaction)
        }

        updateTableContents()
    }

    func showMentionNotificationModeActionSheet() {
        let actionSheet = ActionSheetController(
            title: NSLocalizedString("CONVERSATION_SETTINGS_MENTION_NOTIFICATION_MODE_ACTION_SHEET_TITLE",
                                     comment: "Title of the 'mention notification mode' action sheet.")
        )

        for mode: TSThreadMentionNotificationMode in [.always, .never] {
            let action =
                ActionSheetAction(
                    title: nameForMentionMode(mode),
                    accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: String(describing: mode))
                ) { [weak self] _ in
                    self?.setMentionNotificationMode(mode)
            }
            actionSheet.addAction(action)
        }

        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func setMentionNotificationMode(_ value: TSThreadMentionNotificationMode) {
        databaseStorage.write { transaction in
            self.thread.updateWithMentionNotificationMode(value, transaction: transaction)
        }

        updateTableContents()
    }

    func showMediaGallery() {
        Logger.debug("")

        let tileVC = MediaTileViewController(thread: thread)
        navigationController?.pushViewController(tileVC, animated: true)
    }

    func tappedConversationSearch() {
        conversationSettingsViewDelegate?.conversationSettingsDidRequestConversationSearch()
    }

    @objc
    func editGroupButtonWasPressed(_ sender: Any) {
        showGroupAttributesView(editAction: .none)
    }

    // MARK: - Notifications

    @objc
    private func identityStateDidChange(notification: Notification) {
        AssertIsOnMainThread()

        updateTableContents()
    }

    @objc
    private func otherUsersProfileDidChange(notification: Notification) {
        AssertIsOnMainThread()

        guard let address = notification.userInfo?[kNSNotificationKey_ProfileAddress] as? SignalServiceAddress,
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
        if let address = notification.userInfo?[kNSNotificationKey_ProfileAddress] as? SignalServiceAddress,
            let contactThread = thread as? TSContactThread,
            contactThread.contactAddress == address {
            updateTableContents()
        }

        if let groupId = notification.userInfo?[kNSNotificationKey_ProfileGroupId] as? Data,
            let groupThread = thread as? TSGroupThread,
            groupThread.groupModel.groupId == groupId {
            updateTableContents()
        }
    }
}

// MARK: -

extension ConversationSettingsViewController: ContactsViewHelperObserver {

    func contactsViewHelperDidUpdateContacts() {
        updateTableContents()
    }
}

// MARK: -

extension ConversationSettingsViewController: CNContactViewControllerDelegate {

    public func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        updateTableContents()
        navigationController?.popToViewController(self, animated: true)
    }
}

// MARK: -

extension ConversationSettingsViewController: ColorPickerDelegate {

    func showColorPicker() {
        guard let colorPicker = colorPicker else {
            owsFailDebug("Missing colorPicker.")
            return
        }
        let sheetViewController = colorPicker.sheetViewController
        sheetViewController.delegate = self
        self.present(sheetViewController, animated: true) {
            Logger.info("presented sheet view")
        }
    }

    public func colorPicker(_ colorPicker: ColorPicker, didPickConversationColor conversationColor: OWSConversationColor) {
        Logger.debug("picked color: \(conversationColor.name)")
        databaseStorage.write { transaction in
            self.thread.updateConversationColorName(conversationColor.name, transaction: transaction)
        }

        contactsManager.removeAllFromAvatarCache()
        contactsManager.clearColorNameCache()
        updateTableContents()
        conversationSettingsViewDelegate?.conversationColorWasUpdated()

        DispatchQueue.global().async {
            let operation = ConversationConfigurationSyncOperation(thread: self.thread)
            assert(operation.isReady)
            operation.start()
        }
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

extension ConversationSettingsViewController: SheetViewControllerDelegate {
    public func sheetViewControllerRequestedDismiss(_ sheetViewController: SheetViewController) {
        dismiss(animated: true)
    }
}

// MARK: -

extension ConversationSettingsViewController: OWSNavigationView {

    public func shouldCancelNavigationBack() -> Bool {
        let result = hasUnsavedChangesToDisappearingMessagesConfiguration
        if result {
            self.updateDisappearingMessagesConfigurationAndDismiss()
        }
        return result
    }

    @objc
    public static func showUnsavedChangesActionSheet(from fromViewController: UIViewController,
                                                     saveBlock: @escaping () -> Void,
                                                     discardBlock: @escaping () -> Void) {
        let actionSheet = ActionSheetController(title: NSLocalizedString("CONVERSATION_SETTINGS_UNSAVED_CHANGES_TITLE",
                                                                         comment: "The alert title if user tries to exit conversation settings view without saving changes."),
                                                message: NSLocalizedString("CONVERSATION_SETTINGS_UNSAVED_CHANGES_MESSAGE",
                                                                           comment: "The alert message if user tries to exit conversation settings view without saving changes."))
        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("ALERT_SAVE",
                                                                         comment: "The label for the 'save' button in action sheets."),
                                                accessibilityIdentifier: UIView.accessibilityIdentifier(in: fromViewController, name: "save"),
                                                style: .default) { _ in
                                                    saveBlock()
        })
        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("ALERT_DONT_SAVE",
                                                                         comment: "The label for the 'don't save' button in action sheets."),
                                                accessibilityIdentifier: UIView.accessibilityIdentifier(in: fromViewController, name: "dont_save"),
                                                style: .destructive) { _ in
                                                    discardBlock()
        })
        fromViewController.presentActionSheet(actionSheet)
    }

    private func updateDisappearingMessagesConfigurationAndDismiss() {
        let dmConfiguration: OWSDisappearingMessagesConfiguration = disappearingMessagesConfiguration
        let thread = self.thread
        GroupViewUtils.updateGroupWithActivityIndicator(fromViewController: self,
                                                        updatePromiseBlock: {
                                                            self.updateDisappearingMessagesConfigurationPromise(dmConfiguration,
                                                                                                                thread: thread)
        },
                                                        completion: { [weak self] _ in
                                                            self?.navigationController?.popViewController(animated: true)
        })
    }

    private func updateDisappearingMessagesConfigurationPromise(_ dmConfiguration: OWSDisappearingMessagesConfiguration,
                                                                thread: TSThread) -> Promise<Void> {

        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: thread,
                                                         description: "Update disappearing messages configuration")
        }.map(on: .global()) {
            // We're sending a message, so we're accepting any pending message request.
            ThreadUtil.addToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction(thread: thread)
        }.then(on: .global()) {
            GroupManager.localUpdateDisappearingMessages(thread: thread,
                                                         disappearingMessageToken: dmConfiguration.asToken)
        }
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
    func replaceAdmin(uuid: UUID) {
        showLeaveGroupConfirmAlert(replacementAdminUuid: uuid)
    }
}
