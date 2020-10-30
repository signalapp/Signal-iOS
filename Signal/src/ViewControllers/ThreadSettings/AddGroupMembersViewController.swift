//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

protocol AddGroupMembersViewControllerDelegate: class {
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

    @objc func updateGroupPressed() {
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
        if newMemberCount > 1 {
            let messageFormat = NSLocalizedString("ADD_GROUP_MEMBERS_VIEW_CONFIRM_ALERT_MESSAGE_N_FORMAT",
                                                  comment: "Format for the message for the 'add group members' confirmation alert.  Embeds {{ %1$@ number of new members, %2$@ name of the group. }}.")
            alertMessage = String(format: messageFormat,
                             OWSFormat.formatInt(newRecipientSet.count),
                             groupName)
            alertTitle = NSLocalizedString("ADD_GROUP_MEMBERS_VIEW_CONFIRM_ALERT_TITLE_N",
                                            comment: "Title for the 'add group members' confirmation alert.")
            actionTitle = NSLocalizedString("ADD_GROUP_MEMBERS_ACTION_TITLE_N",
                                            comment: "Label for the 'add group members' button.")
        } else {
            let messageFormat = NSLocalizedString("ADD_GROUP_MEMBERS_VIEW_CONFIRM_ALERT_MESSAGE_1_FORMAT",
                                        comment: "Format for the message for the 'add group member' confirmation alert.  Embeds {{ the name of the group. }}.")
            alertMessage = String(format: messageFormat, groupName)
            alertTitle = NSLocalizedString("ADD_GROUP_MEMBERS_VIEW_CONFIRM_ALERT_TITLE_1",
                                           comment: "Title for the 'add group member' confirmation alert.")
            actionTitle = NSLocalizedString("ADD_GROUP_MEMBERS_ACTION_TITLE_1",
                                            comment: "Label for the 'add group member' button.")
        }

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

    func buildNewGroupModel() -> TSGroupModel? {
        do {
            return try databaseStorage.read { transaction in
                var builder = self.oldGroupModel.asBuilder
                let oldGroupMembership = self.oldGroupModel.groupMembership
                var groupMembershipBuilder = oldGroupMembership.asBuilder
                let addresses = self.newRecipientSet.orderedMembers.compactMap { $0.address }
                guard !addresses.isEmpty else {
                    owsFailDebug("No valid recipients.")
                    return nil
                }
                for address in addresses {
                    guard !oldGroupMembership.isFullMember(address) else {
                        owsFailDebug("Recipient is already in group.")
                        continue
                    }
                    // GroupManager will separate out members as pending if necessary.
                    groupMembershipBuilder.remove(address)
                    groupMembershipBuilder.addFullMember(address, role: .normal)
                }
                builder.groupMembership = groupMembershipBuilder.build()
                return try builder.build(transaction: transaction)
            }
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

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

        guard let newGroupModel = buildNewGroupModel() else {
                                                        let error = OWSAssertionError("Couldn't build group model.")
                                                        GroupViewUtils.showUpdateErrorUI(error: error)
                                                        return
        }
        GroupViewUtils.updateGroupWithActivityIndicator(fromViewController: self,
                                                        updatePromiseBlock: {
                                                            self.updateGroupThreadPromise(newGroupModel: newGroupModel)
        },
                                                        completion: { _ in
                                                            dismissAndUpdateDelegate()
        })
    }

    func updateGroupThreadPromise(newGroupModel: TSGroupModel) -> Promise<Void> {

        let oldGroupModel = self.oldGroupModel

        guard let localAddress = tsAccountManager.localAddress else {
            return Promise(error: OWSAssertionError("Missing localAddress."))
        }

        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: oldGroupModel,
                                                         description: self.logTag)
        }.then(on: .global()) { _ in
            // dmConfiguration: nil means don't change disappearing messages configuration.
            GroupManager.localUpdateExistingGroup(oldGroupModel: oldGroupModel,
                                                  newGroupModel: newGroupModel,
                                                  dmConfiguration: nil,
                                                  groupUpdateSourceAddress: localAddress)
        }.asVoid()
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
        groupThread.isGroupV2Thread
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
        guard groupThread.isGroupV2Thread else {
            return true
        }
        guard let address = recipient.address else {
            owsFailDebug("Invalid recipient.")
            return false
        }
        return databaseStorage.read { transaction in
            return GroupManager.doesUserSupportGroupsV2(address: address, transaction: transaction)
        }
    }

    func groupMemberViewShouldShowMemberCount() -> Bool {
        groupThread.isGroupV2Thread
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

    func groupMemberViewIsPreExistingMember(_ recipient: PickedRecipient) -> Bool {
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
            let canAddMember = databaseStorage.read { transaction -> Bool in
                guard GroupManager.doesUserSupportGroupsV2(address: address, transaction: transaction) else {
                    return false
                }
                return self.groupsV2.hasProfileKeyCredential(for: address, transaction: transaction)
            }

            return !canAddMember
        }
        return false
    }

    func groupMemberViewIsGroupsV2Required() -> Bool {
        return groupThread.isGroupV2Thread
    }

    func groupMemberViewDismiss() {
        navigationController?.popViewController(animated: true)
    }

    var isNewGroup: Bool {
        false
    }
}
