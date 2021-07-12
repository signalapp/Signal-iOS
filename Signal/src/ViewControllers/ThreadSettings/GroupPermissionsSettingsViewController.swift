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

    private var currentAccessMembers: GroupV2Access { groupModelV2.access.members }
    private var currentAccessAttributes: GroupV2Access { groupModelV2.access.attributes }
    private var currentIsAnnouncementsOnly: Bool { groupModelV2.isAnnouncementsOnly }

    private lazy var accessMembers = currentAccessMembers
    private lazy var accessAttributes = currentAccessAttributes
    private lazy var isAnnouncementsOnly = currentIsAnnouncementsOnly

    private enum AnnouncementOnlyMode: Equatable {
        case enabled
        case disabled(membersWithoutCapability: Set<SignalServiceAddress>)
    }
    private var announcementOnlyMode: AnnouncementOnlyMode {
        didSet {
            if oldValue != announcementOnlyMode,
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
        self.announcementOnlyMode = Self.announcementOnlyMode(threadViewModel: threadViewModel)

        super.init()

        self.groupViewHelper.delegate = self

        switch announcementOnlyMode {
        case .enabled:
            break
        case .disabled(let membersWithoutCapability):
            firstly(on: .global()) { () -> Promise<Void> in
                let promises = membersWithoutCapability.map { address in
                    ProfileFetcherJob.fetchProfilePromise(address: address, ignoreThrottling: true)
                }
                return when(resolved: promises).asVoid()
            }.done { [weak self] in
                self?.updateAnnouncementOnlyMode()
            }.catch { error in
                owsFailDebug("Error: \(error)")
            }
        }
    }

    private func updateAnnouncementOnlyMode() {
        self.announcementOnlyMode = Self.announcementOnlyMode(threadViewModel: threadViewModel)
    }

    private static func announcementOnlyMode(threadViewModel: ThreadViewModel) -> AnnouncementOnlyMode {
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
        currentAccessMembers != accessMembers ||
            currentAccessAttributes != accessAttributes ||
            currentIsAnnouncementsOnly != isAnnouncementsOnly
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

        guard groupViewHelper.canEditConversationAccess else {
            return owsFailDebug("!canEditConversationAccess")
        }

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
                guard let self = self else { return }
                self.accessMembers = .member
                self.updateTableContents()
                self.updateNavigation()
            },
            accessoryType: accessMembers == .member ? .checkmark : .none
        ))
        accessMembersSection.add(.init(
            text: NSLocalizedString(
                "CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS_ALERT_ADMINISTRATORS_BUTTON",
                comment: "Label for button that sets 'group attributes access' to 'administrators-only'."
            ),
            actionBlock: { [weak self] in
                guard let self = self else { return }
                self.accessMembers = .administrator
                self.updateTableContents()
                self.updateNavigation()
            },
            accessoryType: accessMembers == .administrator ? .checkmark : .none
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
                guard let self = self else { return }
                self.accessAttributes = .member
                self.updateTableContents()
                self.updateNavigation()
            },
            accessoryType: accessAttributes == .member ? .checkmark : .none
        ))
        accessAttributesSection.add(.init(
            text: NSLocalizedString(
                "CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS_ALERT_ADMINISTRATORS_BUTTON",
                comment: "Label for button that sets 'group attributes access' to 'administrators-only'."
            ),
            actionBlock: { [weak self] in
                guard let self = self else { return }
                self.accessAttributes = .administrator
                self.updateTableContents()
                self.updateNavigation()
            },
            accessoryType: accessAttributes == .administrator ? .checkmark : .none
        ))

        contents.addSection(accessAttributesSection)

        let canShowAnnouncementOnlyMode = announcementOnlyMode == .enabled
        if RemoteConfig.announcementOnlyGroups,
           canShowAnnouncementOnlyMode {
            let isAnnouncementsOnly = self.isAnnouncementsOnly

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
                    guard let self = self else { return }
                    self.isAnnouncementsOnly = false
                    self.updateTableContents()
                    self.updateNavigation()
                },
                accessoryType: !isAnnouncementsOnly ? .checkmark : .none
            ))
            announcementOnlySection.add(.init(
                text: NSLocalizedString(
                    "CONVERSATION_SETTINGS_SEND_MESSAGES_SECTION_ONLY_ADMINS",
                    comment: "Label for button that sets 'send messages permission' for a group to 'administrators only'."
                ),
                actionBlock: { [weak self] in
                    guard let self = self else { return }
                    self.isAnnouncementsOnly = true
                    self.updateTableContents()
                    self.updateNavigation()
                },
                accessoryType: isAnnouncementsOnly ? .checkmark : .none
            ))

            contents.addSection(announcementOnlySection)
        }
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
                forConversationList: false,
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
                    if self.accessMembers != self.currentAccessMembers {
                        return GroupManager.changeGroupMembershipAccessV2(
                            groupModel: self.groupModelV2,
                            access: self.accessMembers
                        ).asVoid()
                    } else {
                        return Promise.value(())
                    }
                }.then { () -> Promise<Void> in
                    if self.accessAttributes != self.currentAccessAttributes {
                        return GroupManager.changeGroupAttributesAccessV2(
                            groupModel: self.groupModelV2,
                            access: self.accessAttributes
                        ).asVoid()
                    } else {
                        return Promise.value(())
                    }
                }.then { () -> Promise<Void> in
                    if self.isAnnouncementsOnly != self.currentIsAnnouncementsOnly {
                        return GroupManager.setIsAnnouncementsOnly(
                            groupModel: self.groupModelV2,
                            isAnnouncementsOnly: self.isAnnouncementsOnly
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
