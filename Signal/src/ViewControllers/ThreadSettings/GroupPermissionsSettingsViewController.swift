//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

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

    private enum AnnouncementOnlyCapabilityState: Equatable {
        case enabled
        case disabled(membersWithoutCapability: Set<SignalServiceAddress>)
    }
    private var announcementOnlyCapabilityState: AnnouncementOnlyCapabilityState {
        didSet {
            if oldValue != announcementOnlyCapabilityState,
               isViewLoaded {
                updateTableContents()
                updateNavigation()
            }
        }
    }

    init(threadViewModel: ThreadViewModel, delegate: GroupPermissionsSettingsDelegate) {
        owsAssertDebug(threadViewModel.threadRecord.isGroupV2Thread)
        self.threadViewModel = threadViewModel
        self.groupViewHelper = GroupViewHelper(threadViewModel: threadViewModel)
        self.permissionsDelegate = delegate
        self.announcementOnlyCapabilityState = Self.announcementOnlyCapabilityState(threadViewModel: threadViewModel)

        super.init()

        self.groupViewHelper.delegate = self

        // We only show the "announcement-only" UI if all members of the
        // group support this capability.  If some members don't, fetch their
        // profiles; perhaps they have the capability and we just don't know
        // it yet.
        switch announcementOnlyCapabilityState {
        case .enabled:
            break
        case .disabled(let membersWithoutCapability):
            firstly(on: .global()) { () -> Promise<Void> in
                let promises = membersWithoutCapability.map { address in
                    ProfileFetcherJob.fetchProfilePromise(address: address, ignoreThrottling: true)
                }
                return when(resolved: promises).asVoid()
            }.done { [weak self] in
                self?.updateAnnouncementOnlyCapabilityState()
            }.catch { error in
                owsFailDebug("Error: \(error)")
            }
        }
    }

    private func updateAnnouncementOnlyCapabilityState() {
        self.announcementOnlyCapabilityState = Self.announcementOnlyCapabilityState(threadViewModel: threadViewModel)
    }

    private static func announcementOnlyCapabilityState(threadViewModel: ThreadViewModel) -> AnnouncementOnlyCapabilityState {
        guard let groupThread = threadViewModel.threadRecord as? TSGroupThread else {
            owsFailDebug("Invalid group.")
            return .disabled(membersWithoutCapability: Set())
        }
        let members = groupThread.groupMembership.allMembersOfAnyKind
        return databaseStorage.read { transaction in
            var membersWithoutCapability = Set<SignalServiceAddress>()
            for member in members {
                if !GroupManager.doesUserHaveAnnouncementOnlyGroupsCapability(address: member,
                                                                              transaction: transaction) {
                    membersWithoutCapability.insert(member)
                }
            }
            if membersWithoutCapability.isEmpty {
                return .enabled
            } else {
                return .disabled(membersWithoutCapability: membersWithoutCapability)
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString(
            "CONVERSATION_SETTINGS_PERMISSIONS",
            comment: "Label for 'permissions' action in conversation settings view."
        )

        updateTableContents()
        updateNavigation()
    }

    private var hasUnsavedChanges: Bool {
        guard groupViewHelper.canEditPermissions else {
            return false
        }

        return (oldAccessMembers != newAccessMembers ||
            oldAccessAttributes != newAccessAttributes ||
            oldIsAnnouncementsOnly != newIsAnnouncementsOnly)
    }

    // Don't allow interactive dismiss when there are unsaved changes.
    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set {}
    }

    private func updateNavigation() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didTapCancel),
            accessibilityIdentifier: "cancel_button"
        )

        if hasUnsavedChanges {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: CommonStrings.setButton,
                style: .done,
                target: self,
                action: #selector(didTapSet),
                accessibilityIdentifier: "set_button"
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        let accessMembersSection = OWSTableSection()
        accessMembersSection.headerTitle = NSLocalizedString(
            "CONVERSATION_SETTINGS_EDIT_MEMBERSHIP_ACCESS",
            comment: "Label for 'edit membership access' action in conversation settings view."
        )
        accessMembersSection.footerTitle = NSLocalizedString(
            "CONVERSATION_SETTINGS_EDIT_MEMBERSHIP_ACCESS_FOOTER",
            comment: "Description for the 'edit membership access'."
        )

        accessMembersSection.add(.init(
            text: NSLocalizedString(
                "CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS_ALERT_MEMBERS_BUTTON",
                comment: "Label for button that sets 'group attributes access' to 'members-only'."
            ),
            actionBlock: { [weak self] in
                self?.tryToSetAccessMembers(.member)
            },
            accessoryType: newAccessMembers == .member ? .checkmark : .none
        ))
        accessMembersSection.add(.init(
            text: NSLocalizedString(
                "CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS_ALERT_ADMINISTRATORS_BUTTON",
                comment: "Label for button that sets 'group attributes access' to 'administrators-only'."
            ),
            actionBlock: { [weak self] in
                self?.tryToSetAccessMembers(.administrator)
            },
            accessoryType: newAccessMembers == .administrator ? .checkmark : .none
        ))

        contents.addSection(accessMembersSection)

        let accessAttributesSection = OWSTableSection()
        accessAttributesSection.headerTitle = NSLocalizedString(
            "CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS",
            comment: "Label for 'edit attributes access' action in conversation settings view."
        )
        accessAttributesSection.footerTitle = NSLocalizedString(
            "CONVERSATION_SETTINGS_ATTRIBUTES_ACCESS_SECTION_FOOTER",
            comment: "Footer for the 'attributes access' section in conversation settings view."
        )

        accessAttributesSection.add(.init(
            text: NSLocalizedString(
                "CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS_ALERT_MEMBERS_BUTTON",
                comment: "Label for button that sets 'group attributes access' to 'members-only'."
            ),
            actionBlock: { [weak self] in
                self?.tryToSetAccessAttributes(.member)
            },
            accessoryType: newAccessAttributes == .member ? .checkmark : .none
        ))
        accessAttributesSection.add(.init(
            text: NSLocalizedString(
                "CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS_ALERT_ADMINISTRATORS_BUTTON",
                comment: "Label for button that sets 'group attributes access' to 'administrators-only'."
            ),
            actionBlock: { [weak self] in
                self?.tryToSetAccessAttributes(.administrator)
            },
            accessoryType: newAccessAttributes == .administrator ? .checkmark : .none
        ))

        contents.addSection(accessAttributesSection)

        // Always show the announcements-only UI if that option is
        // already enabled.  If not, only show that UI if all group
        // members support that capability and the remote config flag
        // is enabled.
        let canShowAnnouncementOnly = (RemoteConfig.announcementOnlyGroups &&
                                            announcementOnlyCapabilityState == .enabled)
        if canShowAnnouncementOnly || newIsAnnouncementsOnly {
            let isAnnouncementsOnly = self.newIsAnnouncementsOnly

            let announcementOnlySection = OWSTableSection()
            announcementOnlySection.headerTitle = NSLocalizedString(
                "CONVERSATION_SETTINGS_SEND_MESSAGES_SECTION_HEADER",
                comment: "Label for 'send messages' action in conversation settings permissions view."
            )
            announcementOnlySection.footerTitle = NSLocalizedString(
                "CONVERSATION_SETTINGS_SEND_MESSAGES_SECTION_FOOTER",
                comment: "Footer for the 'send messages' section in conversation settings permissions view."
            )

            announcementOnlySection.add(.init(
                text: NSLocalizedString(
                    "CONVERSATION_SETTINGS_SEND_MESSAGES_SECTION_ALL_MEMBERS",
                    comment: "Label for button that sets 'send messages permission' for a group to 'all members'."
                ),
                actionBlock: { [weak self] in
                    self?.tryToSetIsAnnouncementsOnly(false)
                },
                accessoryType: !isAnnouncementsOnly ? .checkmark : .none
            ))
            announcementOnlySection.add(.init(
                text: NSLocalizedString(
                    "CONVERSATION_SETTINGS_SEND_MESSAGES_SECTION_ONLY_ADMINS",
                    comment: "Label for button that sets 'send messages permission' for a group to 'administrators only'."
                ),
                actionBlock: { [weak self] in
                    self?.tryToSetIsAnnouncementsOnly(true)
                },
                accessoryType: isAnnouncementsOnly ? .checkmark : .none
            ))

            contents.addSection(announcementOnlySection)
        }
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
        let message = NSLocalizedString("GROUP_ADMIN_ONLY_WARNING",
                                        comment: "Message indicating that a feature can only be used by group admins.")
        presentToast(text: message)
        updateTableContents()
    }

    private func reloadThreadAndUpdateContent() {
        let didUpdate = self.databaseStorage.read { transaction -> Bool in
            guard let newThread = TSThread.anyFetch(
                uniqueId: self.thread.uniqueId,
                transaction: transaction
            ) else {
                return false
            }
            let newThreadViewModel = ThreadViewModel(
                thread: newThread,
                forHomeView: false,
                transaction: transaction
            )
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

    @objc
    func didTapCancel() {
        guard hasUnsavedChanges else {
            dismiss(animated: true)
            return
        }

        OWSActionSheets.showPendingChangesActionSheet(discardAction: { [weak self] in
            self?.dismiss(animated: true)
        })
    }

    @objc
    func didTapSet() {
        guard groupViewHelper.canEditPermissions else {
            owsFailDebug("Missing edit permission.")
            return
        }

        // TODO: We might consolidate this from (up to) 3 separate group changes
        // into a single change.
        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: self,
            updatePromiseBlock: {
                firstly { () -> Promise<Void> in
                    GroupManager.messageProcessingPromise(
                        for: self.thread,
                        description: "Update group permissions"
                    )
                }.map(on: .global()) {
                    // We're sending a message, so we're accepting any pending message request.
                    ThreadUtil.addToProfileWhitelistIfEmptyOrPendingRequestWithSneakyTransaction(thread: self.thread)
                }.then { () -> Promise<Void> in
                    if self.newAccessMembers != self.oldAccessMembers {
                        return GroupManager.changeGroupMembershipAccessV2(
                            groupModel: self.groupModelV2,
                            access: self.newAccessMembers
                        ).asVoid()
                    } else {
                        return Promise.value(())
                    }
                }.then { () -> Promise<Void> in
                    if self.newAccessAttributes != self.oldAccessAttributes {
                        return GroupManager.changeGroupAttributesAccessV2(
                            groupModel: self.groupModelV2,
                            access: self.newAccessAttributes
                        ).asVoid()
                    } else {
                        return Promise.value(())
                    }
                }.then { () -> Promise<Void> in
                    if self.newIsAnnouncementsOnly != self.oldIsAnnouncementsOnly {
                        return GroupManager.setIsAnnouncementsOnly(
                            groupModel: self.groupModelV2,
                            isAnnouncementsOnly: self.newIsAnnouncementsOnly
                        ).asVoid()
                    } else {
                        return Promise.value(())
                    }
                }
            },
            completion: { [weak self] _ in
                self?.permissionsDelegate?.groupPermissionSettingsDidUpdate()
                self?.dismiss(animated: true)
            }
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
