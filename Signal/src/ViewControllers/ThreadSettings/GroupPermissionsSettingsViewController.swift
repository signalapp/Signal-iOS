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

    private lazy var accessMembers = currentAccessMembers
    private lazy var accessAttributes = currentAccessAttributes

    init(threadViewModel: ThreadViewModel, delegate: GroupPermissionsSettingsDelegate) {
        owsAssertDebug(threadViewModel.threadRecord.isGroupV2Thread)
        self.threadViewModel = threadViewModel
        self.groupViewHelper = GroupViewHelper(threadViewModel: threadViewModel)
        self.permissionsDelegate = delegate
        super.init()
        self.groupViewHelper.delegate = self
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
        currentAccessMembers != accessMembers || currentAccessAttributes != accessAttributes
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
                self?.accessMembers = .member
                self?.updateTableContents()
                self?.updateNavigation()
            },
            accessoryType: accessMembers == .member ? .checkmark : .none
        ))
        accessMembersSection.add(.init(
            text: NSLocalizedString(
                "CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS_ALERT_ADMINISTRATORS_BUTTON",
                comment: "Label for button that sets 'group attributes access' to 'administrators-only'."
            ),
            actionBlock: { [weak self] in
                self?.accessMembers = .administrator
                self?.updateTableContents()
                self?.updateNavigation()
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
                self?.accessAttributes = .member
                self?.updateTableContents()
                self?.updateNavigation()
            },
            accessoryType: accessAttributes == .member ? .checkmark : .none
        ))
        accessAttributesSection.add(.init(
            text: NSLocalizedString(
                "CONVERSATION_SETTINGS_EDIT_ATTRIBUTES_ACCESS_ALERT_ADMINISTRATORS_BUTTON",
                comment: "Label for button that sets 'group attributes access' to 'administrators-only'."
            ),
            actionBlock: { [weak self] in
                self?.accessAttributes = .administrator
                self?.updateTableContents()
                self?.updateNavigation()
            },
            accessoryType: accessAttributes == .administrator ? .checkmark : .none
        ))

        contents.addSection(accessAttributesSection)
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
