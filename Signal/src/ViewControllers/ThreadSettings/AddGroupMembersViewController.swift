//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

protocol AddGroupMembersViewControllerDelegate: AnyObject {
    func addGroupMembersViewDidUpdate()
}

// MARK: -

@objc
public class AddGroupMembersViewController: BaseGroupMemberViewController {

    weak var addGroupMembersViewControllerDelegate: AddGroupMembersViewControllerDelegate?

    private let groupThread: TSGroupThread
    private let oldGroupModel: TSGroupModel

    private var newRecipientSet = OrderedSet<PickedRecipient>()

    public required init(groupThread: TSGroupThread) {
        owsAssertDebug(groupThread.isGroupV2Thread, "Can't add members to v1 threads.")

        self.groupThread = groupThread
        self.oldGroupModel = groupThread.groupModel

        super.init()

        groupMemberViewDelegate = self
    }

    // MARK: - View Lifecycle

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("ADD_GROUP_MEMBERS_VIEW_TITLE",
                                  comment: "The title for the 'add group members' view.")
    }

    // MARK: -

    fileprivate func updateNavbar() {
        if hasUnsavedChanges {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("EDIT_GROUP_UPDATE_BUTTON",
                                                                                         comment: "The title for the 'update group' button."),
                                                                style: .plain,
                                                                target: self,
                                                                action: #selector(updateGroupPressed),
                                                                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "update"))
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    @objc
    func updateGroupPressed() {
        showConfirmationAlert()
    }

    private func showConfirmationAlert() {
        let newMemberCount = newRecipientSet.count
        guard newMemberCount > 0 else {
            owsFailDebug("No new members.")
            return
        }

        let groupName = contactsManager.displayNameWithSneakyTransaction(thread: groupThread)
        let alertTitle: String
        let alertMessage: String
        let actionTitle: String
        let messageFormat = NSLocalizedString("ADD_GROUP_MEMBERS_VIEW_CONFIRM_ALERT_MESSAGE_%d", tableName: "PluralAware",
                                              comment: "Format for the message for the 'add group members' confirmation alert.  Embeds {{ %1$@ number of new members, %2$@ name of the group. }}.")
        alertMessage = String.localizedStringWithFormat(messageFormat, newRecipientSet.count, groupName)
        alertTitle = String.localizedStringWithFormat(NSLocalizedString("ADD_GROUP_MEMBERS_VIEW_CONFIRM_ALERT_TITLE_%d", tableName: "PluralAware",
                                                      comment: "Title for the 'add group members' confirmation alert."), newRecipientSet.count)
        actionTitle = String.localizedStringWithFormat(NSLocalizedString("ADD_GROUP_MEMBERS_ACTION_TITLE_%d", tableName: "PluralAware",
                                        comment: "Label for the 'add group members' button."), newRecipientSet.count)

        let actionSheet = ActionSheetController(title: alertTitle, message: alertMessage)
        actionSheet.addAction(ActionSheetAction(title: actionTitle,
                                                style: .default,
                                                handler: { [weak self] _ in
                                                    self?.updateGroupThreadAndDismiss()
        }))
        actionSheet.addAction(OWSActionSheets.cancelAction)
        self.presentActionSheet(actionSheet)
    }
}

// MARK: -

private extension AddGroupMembersViewController {

    func updateGroupThreadAndDismiss() {

        let dismissAndUpdateDelegate = { [weak self] in
            guard let self = self else {
                return
            }
            self.addGroupMembersViewControllerDelegate?.addGroupMembersViewDidUpdate()
            self.navigationController?.popViewController(animated: true)
        }

        guard hasUnsavedChanges else {
            owsFailDebug("!hasUnsavedChanges.")
            return dismissAndUpdateDelegate()
        }

        let newUuids = newRecipientSet.orderedMembers
            .compactMap { recipient -> UUID? in
                if let uuid = recipient.address?.uuid,
                   !oldGroupModel.groupMembership.isFullMember(uuid) {
                    return uuid
                }

                owsFailDebug("Missing UUID, or recipient is already in group!")
                return nil
            }

        guard !newUuids.isEmpty else {
            let error = OWSAssertionError("No valid recipients")
            GroupViewUtils.showUpdateErrorUI(error: error)
            return
        }

        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: self,
            withGroupModel: self.oldGroupModel,
            updateDescription: self.logTag,
            updateBlock: {
                GroupManager.addOrInvite(
                    aciOrPniUuids: newUuids,
                    toExistingGroup: self.oldGroupModel
                )
            },
            completion: { _ in dismissAndUpdateDelegate() }
        )
    }
}

// MARK: -

extension AddGroupMembersViewController: GroupMemberViewDelegate {

    var groupMemberViewRecipientSet: OrderedSet<PickedRecipient> {
        newRecipientSet
    }

    var groupMemberViewHasUnsavedChanges: Bool {
        !newRecipientSet.isEmpty
    }

    var shouldTryToEnableGroupsV2ForMembers: Bool {
        true
    }

    func groupMemberViewRemoveRecipient(_ recipient: PickedRecipient) {
        newRecipientSet.remove(recipient)
        updateNavbar()
    }

    func groupMemberViewAddRecipient(_ recipient: PickedRecipient) {
        newRecipientSet.append(recipient)
        updateNavbar()
    }

    func groupMemberViewCanAddRecipient(_ recipient: PickedRecipient) -> Bool {
        guard let address = recipient.address else {
            owsFailDebug("Invalid recipient.")
            return false
        }
        return GroupManager.doesUserSupportGroupsV2(address: address)
    }

    func groupMemberViewShouldShowMemberCount() -> Bool {
        true
    }

    func groupMemberViewGroupMemberCountForDisplay() -> Int {
        (oldGroupModel.groupMembership.allMembersOfAnyKind.count +
                newRecipientSet.count)
    }

    func groupMemberViewIsGroupFull_HardLimit() -> Bool {
        groupMemberViewGroupMemberCountForDisplay() >= GroupManager.groupsV2MaxGroupSizeHardLimit
    }

    func groupMemberViewIsGroupFull_RecommendedLimit() -> Bool {
        groupMemberViewGroupMemberCountForDisplay() >= GroupManager.groupsV2MaxGroupSizeRecommended
    }

    func groupMemberViewIsPreExistingMember(_ recipient: PickedRecipient,
                                            transaction: SDSAnyReadTransaction) -> Bool {
        guard let address = recipient.address else {
            owsFailDebug("Invalid recipient.")
            return false
        }
        let groupMembership = oldGroupModel.groupMembership
        if groupMembership.isFullMember(address) {
            return true
        }
        if groupMembership.isInvitedMember(address) ||
            groupMembership.isRequestingMember(address) {
            // We can "add" pending or requesting members if they support gv2
            // and we know their profile key credential.
            let canAddMember: Bool = {
                guard GroupManager.doesUserSupportGroupsV2(address: address) else {
                    return false
                }
                return self.groupsV2.hasProfileKeyCredential(for: address, transaction: transaction)
            }()

            return !canAddMember
        }
        return false
    }

    func groupMemberViewIsGroupsV2Required() -> Bool {
        true
    }

    func groupMemberViewDismiss() {
        navigationController?.popViewController(animated: true)
    }

    var isNewGroup: Bool {
        false
    }

    var groupThreadForGroupMemberView: TSGroupThread? {
        groupThread
    }
}
