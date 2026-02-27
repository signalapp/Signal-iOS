//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol GroupPermissionsSettingsDelegate: AnyObject {
    func groupPermissionSettingsDidUpdate()
}

class GroupPermissionsSettingsViewController: OWSTableViewController2 {
    private var threadViewModel: ThreadViewModel
    private var thread: TSThread { threadViewModel.threadRecord }
    private var groupViewHelper: GroupViewHelper
    private weak var permissionsDelegate: GroupPermissionsSettingsDelegate?

    private var groupModelV2: TSGroupModelV2! {
        thread.groupModelIfGroupThread as? TSGroupModelV2
    }

    private var oldAccessMembers: GroupV2Access { groupModelV2.access.members }
    private var oldAccessAttributes: GroupV2Access { groupModelV2.access.attributes }
    private var oldIsAnnouncementsOnly: Bool { groupModelV2.isAnnouncementsOnly }

    private lazy var newAccessMembers = oldAccessMembers
    private lazy var newAccessAttributes = oldAccessAttributes
    private lazy var newIsAnnouncementsOnly = oldIsAnnouncementsOnly

    init(threadViewModel: ThreadViewModel, delegate: GroupPermissionsSettingsDelegate) {
        owsAssertDebug(threadViewModel.threadRecord.isGroupV2Thread)
        self.threadViewModel = threadViewModel
        self.groupViewHelper = GroupViewHelper(threadViewModel: threadViewModel, memberLabelCoordinator: nil)
        self.permissionsDelegate = delegate

        super.init()

        self.groupViewHelper.delegate = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "CONVERSATION_SETTINGS_PERMISSIONS",
            comment: "Label for 'permissions' action in conversation settings view.",
        )

        navigationItem.leftBarButtonItem = .cancelButton(
            dismissingFrom: self,
            hasUnsavedChanges: { [weak self] in self?.hasUnsavedChanges },
        )

        navigationItem.rightBarButtonItem = .setButton { [weak self] in
            self?.didTapSet()
        }

        updateTableContents()
        updateNavigation()
    }

    private var hasUnsavedChanges: Bool {
        guard groupViewHelper.canEditPermissions else {
            return false
        }

        return oldAccessMembers != newAccessMembers ||
            oldAccessAttributes != newAccessAttributes ||
            oldIsAnnouncementsOnly != newIsAnnouncementsOnly
    }

    // Don't allow interactive dismiss when there are unsaved changes.
    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set {}
    }

    private func updateNavigation() {
        navigationItem.rightBarButtonItem?.isEnabled = hasUnsavedChanges
    }

    func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        let accessMembersSection = OWSTableSection()
        accessMembersSection.headerTitle = OWSLocalizedString(
            "CONVERSATION_SETTINGS_EDIT_MEMBERSHIP_ACCESS",
            comment: "Label for 'edit membership access' action in conversation settings view.",
        )
        accessMembersSection.footerTitle = OWSLocalizedString(
            "CONVERSATION_SETTINGS_EDIT_MEMBERSHIP_ACCESS_FOOTER",
            comment: "Description for the 'edit membership access'.",
        )

        accessMembersSection.add(.init(
            text: OWSLocalizedString(
                "CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS_ALERT_MEMBERS_BUTTON",
                comment: "Label for button that sets 'group attributes access' to 'members-only'.",
            ),
            actionBlock: { [weak self] in
                self?.tryToSetAccessMembers(.member)
            },
            accessoryType: newAccessMembers == .member ? .checkmark : .none,
        ))
        accessMembersSection.add(.init(
            text: OWSLocalizedString(
                "CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS_ALERT_ADMINISTRATORS_BUTTON",
                comment: "Label for button that sets 'group attributes access' to 'administrators-only'.",
            ),
            actionBlock: { [weak self] in
                self?.tryToSetAccessMembers(.administrator)
            },
            accessoryType: newAccessMembers == .administrator ? .checkmark : .none,
        ))

        contents.add(accessMembersSection)

        let accessAttributesSection = OWSTableSection()
        accessAttributesSection.headerTitle = OWSLocalizedString(
            "CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS",
            comment: "Label for 'edit attributes access' action in conversation settings view.",
        )
        if BuildFlags.MemberLabel.send {
            accessAttributesSection.footerTitle = OWSLocalizedString(
                "CONVERSATION_SETTINGS_ATTRIBUTES_ACCESS_SECTION_FOOTER_V3",
                comment: "Footer for the 'attributes access' section in conversation settings view with member labels added.",
            )
        } else {
            accessAttributesSection.footerTitle = OWSLocalizedString(
                "CONVERSATION_SETTINGS_ATTRIBUTES_ACCESS_SECTION_FOOTER_V2",
                comment: "Footer for the 'attributes access' section in conversation settings view with pinned messages added.",
            )
        }

        accessAttributesSection.add(.init(
            text: OWSLocalizedString(
                "CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS_ALERT_MEMBERS_BUTTON",
                comment: "Label for button that sets 'group attributes access' to 'members-only'.",
            ),
            actionBlock: { [weak self] in
                self?.tryToSetAccessAttributes(.member)
            },
            accessoryType: newAccessAttributes == .member ? .checkmark : .none,
        ))
        accessAttributesSection.add(.init(
            text: OWSLocalizedString(
                "CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS_ALERT_ADMINISTRATORS_BUTTON",
                comment: "Label for button that sets 'group attributes access' to 'administrators-only'.",
            ),
            actionBlock: { [weak self] in
                self?.tryToSetAccessAttributes(.administrator)
            },
            accessoryType: newAccessAttributes == .administrator ? .checkmark : .none,
        ))

        contents.add(accessAttributesSection)

        let isAnnouncementsOnly = self.newIsAnnouncementsOnly

        let announcementOnlySection = OWSTableSection()
        announcementOnlySection.headerTitle = OWSLocalizedString(
            "CONVERSATION_SETTINGS_SEND_MESSAGES_SECTION_HEADER",
            comment: "Label for 'send messages' action in conversation settings permissions view.",
        )
        announcementOnlySection.footerTitle = OWSLocalizedString(
            "CONVERSATION_SETTINGS_SEND_MESSAGES_SECTION_FOOTER",
            comment: "Footer for the 'send messages' section in conversation settings permissions view.",
        )

        announcementOnlySection.add(.init(
            text: OWSLocalizedString(
                "CONVERSATION_SETTINGS_SEND_MESSAGES_SECTION_ALL_MEMBERS",
                comment: "Label for button that sets 'send messages permission' for a group to 'all members'.",
            ),
            actionBlock: { [weak self] in
                self?.tryToSetIsAnnouncementsOnly(false)
            },
            accessoryType: !isAnnouncementsOnly ? .checkmark : .none,
        ))
        announcementOnlySection.add(.init(
            text: OWSLocalizedString(
                "CONVERSATION_SETTINGS_SEND_MESSAGES_SECTION_ONLY_ADMINS",
                comment: "Label for button that sets 'send messages permission' for a group to 'administrators only'.",
            ),
            actionBlock: { [weak self] in
                self?.tryToSetIsAnnouncementsOnly(true)
            },
            accessoryType: isAnnouncementsOnly ? .checkmark : .none,
        ))

        contents.add(announcementOnlySection)
    }

    private func tryToSetAccessMembers(_ value: GroupV2Access) {
        guard groupViewHelper.canEditPermissions else {
            showAdminOnlyWarningAlert()
            return
        }
        self.newAccessMembers = value
        self.updateTableContents()
        self.updateNavigation()
    }

    private func showClearMemberLabelWarning(continueHandler: @escaping () -> Void) {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "MEMBER_LABEL_CLEAR_WARNING_TITLE",
                comment: "Title for action sheet when attempting to change the group attributes access to 'administrator'",
            ),
            message: OWSLocalizedString(
                "MEMBER_LABEL_CLEAR_WARNING_BODY",
                comment: "Body for action sheet when attempting to change the group attributes access to 'administrator'",
            ),
        )
        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "MEMBER_LABEL_CLEAR_CHANGE_PERMISSION_CONTINUE",
                comment: "Button label on action sheet when attempting to change the group attributes access to 'administrator' and then continue",
            ),
            style: .default,
            handler: { _ in
                continueHandler()
            },
        ))
        actionSheet.addAction(.cancel)

        if BuildFlags.MemberLabel.send {
            self.presentActionSheet(actionSheet)
        } else {
            continueHandler()
        }
    }

    private func tryToSetAccessAttributes(_ value: GroupV2Access) {
        guard groupViewHelper.canEditPermissions else {
            showAdminOnlyWarningAlert()
            return
        }

        self.newAccessAttributes = value
        self.updateTableContents()
        self.updateNavigation()
    }

    private func tryToSetIsAnnouncementsOnly(_ value: Bool) {
        guard groupViewHelper.canEditPermissions else {
            showAdminOnlyWarningAlert()
            return
        }
        newIsAnnouncementsOnly = value
        updateTableContents()
        updateNavigation()
    }

    private func showAdminOnlyWarningAlert() {
        let message = OWSLocalizedString(
            "GROUP_ADMIN_ONLY_WARNING",
            comment: "Message indicating that a feature can only be used by group admins.",
        )
        presentToast(text: message)
        updateTableContents()
    }

    private func reloadThreadAndUpdateContent() {
        let didUpdate = SSKEnvironment.shared.databaseStorageRef.read { transaction -> Bool in
            guard
                let newThread = TSThread.fetchViaCache(
                    uniqueId: self.thread.uniqueId,
                    transaction: transaction,
                )
            else {
                return false
            }
            let newThreadViewModel = ThreadViewModel(
                thread: newThread,
                forChatList: false,
                transaction: transaction,
            )
            self.threadViewModel = newThreadViewModel
            self.groupViewHelper = GroupViewHelper(threadViewModel: newThreadViewModel, memberLabelCoordinator: nil)
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

    private func didTapSet() {
        guard groupViewHelper.canEditPermissions else {
            owsFailDebug("Missing edit permission.")
            return
        }

        // TODO: We might consolidate this from (up to) 3 separate group changes
        // into a single change.
        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: self,
            updateBlock: { @MainActor [thread] in
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().async {
                        // We're sending a message, so we're accepting any pending message request.
                        ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction(thread)
                        continuation.resume()
                    }
                }

                if self.newAccessMembers != self.oldAccessMembers {
                    try await GroupManager.changeGroupMembershipAccessV2(
                        groupModel: self.groupModelV2,
                        access: self.newAccessMembers,
                    )
                }
                if self.newAccessAttributes != self.oldAccessAttributes {
                    try await GroupManager.changeGroupAttributesAccessV2(
                        groupModel: self.groupModelV2,
                        access: self.newAccessAttributes,
                    )
                }
                if self.newIsAnnouncementsOnly != self.oldIsAnnouncementsOnly {
                    try await GroupManager.setIsAnnouncementsOnly(
                        groupModel: self.groupModelV2,
                        isAnnouncementsOnly: self.newIsAnnouncementsOnly,
                    )
                }
            },
            completion: { [weak self] in
                self?.permissionsDelegate?.groupPermissionSettingsDidUpdate()
                self?.dismiss(animated: true)
            },
        )
    }
}

extension GroupPermissionsSettingsViewController: GroupViewHelperDelegate {
    func groupViewHelperDidUpdateGroup() {
        reloadThreadAndUpdateContent()
    }

    var currentGroupModel: TSGroupModel? {
        thread.groupModelIfGroupThread
    }

    var fromViewController: UIViewController? {
        self
    }
}
