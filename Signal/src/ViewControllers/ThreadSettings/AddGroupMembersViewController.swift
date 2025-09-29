//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
public import SignalServiceKit
import SignalUI

protocol AddGroupMembersViewControllerDelegate: AnyObject {
    func addGroupMembersViewDidUpdate()
}

// MARK: -

final public class AddGroupMembersViewController: BaseGroupMemberViewController {

    weak var addGroupMembersViewControllerDelegate: AddGroupMembersViewControllerDelegate?

    private let groupThread: TSGroupThread
    private let oldGroupModel: TSGroupModel

    private var newRecipientSet = OrderedSet<PickedRecipient>()

    public init(groupThread: TSGroupThread) {
        owsAssertDebug(groupThread.isGroupV2Thread, "Can't add members to v1 threads.")

        self.groupThread = groupThread
        self.oldGroupModel = groupThread.groupModel

        super.init()

        groupMemberViewDelegate = self
    }

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("ADD_GROUP_MEMBERS_VIEW_TITLE",
                                  comment: "The title for the 'add group members' view.")
    }

    // MARK: -

    fileprivate func updateNavbar() {
        if hasUnsavedChanges {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: OWSLocalizedString("EDIT_GROUP_UPDATE_BUTTON",
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
    private func updateGroupPressed() {
        showConfirmationAlert()
    }

    private func showConfirmationAlert() {
        let newMemberCount = newRecipientSet.count
        guard newMemberCount > 0 else {
            owsFailDebug("No new members.")
            return
        }

        let groupName = SSKEnvironment.shared.databaseStorageRef.read { tx in SSKEnvironment.shared.contactManagerRef.displayName(for: groupThread, transaction: tx) }
        let alertTitle: String
        let alertMessage: String
        let actionTitle: String
        let messageFormat = OWSLocalizedString("ADD_GROUP_MEMBERS_VIEW_CONFIRM_ALERT_MESSAGE_%d", tableName: "PluralAware",
                                              comment: "Format for the message for the 'add group members' confirmation alert.  Embeds {{ %1$@ number of new members, %2$@ name of the group. }}.")
        alertMessage = String.localizedStringWithFormat(messageFormat, newRecipientSet.count, groupName)
        alertTitle = String.localizedStringWithFormat(OWSLocalizedString("ADD_GROUP_MEMBERS_VIEW_CONFIRM_ALERT_TITLE_%d", tableName: "PluralAware",
                                                      comment: "Title for the 'add group members' confirmation alert."), newRecipientSet.count)
        actionTitle = String.localizedStringWithFormat(OWSLocalizedString("ADD_GROUP_MEMBERS_ACTION_TITLE_%d", tableName: "PluralAware",
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

        let newServiceIds = newRecipientSet.orderedMembers
            .compactMap { recipient -> ServiceId? in
                if let serviceId = recipient.address?.serviceId,
                   !oldGroupModel.groupMembership.isFullMember(serviceId) {
                    return serviceId
                }

                owsFailDebug("Missing UUID, or recipient is already in group!")
                return nil
            }

        guard !newServiceIds.isEmpty else {
            let error = OWSAssertionError("No valid recipients")
            GroupViewUtils.showUpdateErrorUI(error: error)
            return
        }

        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: self,
            updateBlock: {
                try await GroupManager.addOrInvite(
                    serviceIds: newServiceIds,
                    toExistingGroup: self.oldGroupModel
                )
            },
            completion: dismissAndUpdateDelegate
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

    func groupMemberViewRemoveRecipient(_ recipient: PickedRecipient) {
        newRecipientSet.remove(recipient)
        updateNavbar()
    }

    func groupMemberViewAddRecipient(_ recipient: PickedRecipient) {
        newRecipientSet.append(recipient)
        updateNavbar()
    }

    func groupMemberViewShouldShowMemberCount() -> Bool {
        true
    }

    func groupMemberViewGroupMemberCountForDisplay() -> Int {
        let currentFullMembers = oldGroupModel.groupMembership.fullMembers
        let currentInvitedMembers = oldGroupModel.groupMembership.invitedMembers
        return currentFullMembers.count + currentInvitedMembers.count + newRecipientSet.count
    }

    func groupMemberViewIsGroupFull_HardLimit() -> Bool {
        groupMemberViewGroupMemberCountForDisplay() >= RemoteConfig.current.maxGroupSizeHardLimit
    }

    func groupMemberViewIsGroupFull_RecommendedLimit() -> Bool {
        groupMemberViewGroupMemberCountForDisplay() >= RemoteConfig.current.maxGroupSizeRecommended
    }

    func groupMemberViewIsPreExistingMember(_ recipient: PickedRecipient,
                                            transaction: DBReadTransaction) -> Bool {
        guard let serviceId = recipient.address?.serviceId else {
            owsFailDebug("Invalid recipient.")
            return false
        }
        let groupMembership = oldGroupModel.groupMembership
        switch groupMembership.canTryToAddToGroup(serviceId: serviceId) {
        case .alreadyInGroup:
            return true
        case .addableWithProfileKeyCredential:
            let canAddMember = GroupMembership.canTryToAddWithProfileKeyCredential(serviceId: serviceId, tx: transaction)
            return !canAddMember
        case .addableOrInvitable:
            return false
        }
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
