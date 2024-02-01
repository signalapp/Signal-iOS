//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI

extension GroupViewHelper {

    // This group of member actions follow a similar pattern:
    //
    // * Show a confirmation alert.
    // * Present a modal activity indicator.
    // * Perform the action using a promise.
    // * Reload the group model and update the table content.
    private func showMemberActionConfirmationActionSheet<T: ServiceId>(
        address: SignalServiceAddress,
        titleFormat: String,
        actionTitle: String,
        updateDescription: String,
        updateBlock: @escaping (TSGroupModelV2, T) -> Promise<Void>
    ) {
        guard
            let fromViewController = fromViewController,
            let oldGroupModel = delegate?.currentGroupModel as? TSGroupModelV2,
            oldGroupModel.groupMembership.isMemberOfAnyKind(address),
            let serviceId = address.serviceId as? T
        else {
            GroupViewUtils.showUpdateErrorUI(error: OWSAssertionError("Invalid parameters for update: \(updateDescription)"))
            return
        }

        let actionBlock = {
            GroupViewUtils.updateGroupWithActivityIndicator(
                fromViewController: fromViewController,
                withGroupModel: oldGroupModel,
                updateDescription: updateDescription,
                updateBlock: { updateBlock(oldGroupModel, serviceId) },
                completion: { [weak self] _ in
                    self?.delegate?.groupViewHelperDidUpdateGroup()
                }
            )
        }
        let title = String(format: titleFormat, databaseStorage.read { tx in
            return contactsManager.displayName(for: address, transaction: tx)
        })
        let actionSheet = ActionSheetController(title: title)
        actionSheet.addAction(ActionSheetAction(title: actionTitle, style: .default, handler: { _ in actionBlock() }))
        actionSheet.addAction(OWSActionSheets.cancelAction)
        fromViewController.presentActionSheet(actionSheet)
    }

    // MARK: - Make Group Admin

    func memberActionSheetCanMakeGroupAdmin(address: SignalServiceAddress) -> Bool {
        guard let groupThread = thread as? TSGroupThread,
            groupThread.isGroupV2Thread else {
                return false
        }
        guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress else {
            owsFailDebug("Missing localAddress.")
            return false
        }
        let isLocalUserAdmin = groupThread.groupModel.groupMembership.isFullMemberAndAdministrator(localAddress)
        let groupMembership = groupThread.groupModel.groupMembership
        let canBecomeAdmin = (groupMembership.isFullMember(address) &&
            !groupMembership.isFullMemberAndAdministrator(address))
        return (canEditConversationMembership && isLocalUserAdmin && canBecomeAdmin)
    }

    func memberActionSheetMakeGroupAdminWasSelected(address: SignalServiceAddress) {
        let titleFormat = OWSLocalizedString("CONVERSATION_SETTINGS_MAKE_GROUP_ADMIN_TITLE_FORMAT",
                                            comment: "Format for title for 'make group admin' confirmation alert. Embeds {user to make an admin}.")
        let actionTitle =  OWSLocalizedString("CONVERSATION_SETTINGS_MAKE_GROUP_ADMIN_BUTTON",
                                             comment: "Label for 'make group admin' button in conversation settings view.")
        showMemberActionConfirmationActionSheet(
            address: address,
            titleFormat: titleFormat,
            actionTitle: actionTitle,
            updateDescription: "Make group admin",
            updateBlock: { (oldGroupModel, aci: Aci) in
                GroupManager.changeMemberRoleV2(groupModel: oldGroupModel, aci: aci, role: .administrator).asVoid()
            }
        )
    }

    // MARK: - Revoke Group Admin

    func memberActionSheetCanRevokeGroupAdmin(address: SignalServiceAddress) -> Bool {
        guard let groupThread = thread as? TSGroupThread,
            groupThread.isGroupV2Thread else {
                return false
        }
        guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress else {
            owsFailDebug("Missing localAddress.")
            return false
        }
        let groupMembership = groupThread.groupModel.groupMembership
        let isLocalUserAdmin = groupMembership.isFullMemberAndAdministrator(localAddress)
        let canRevokeAdmin = groupMembership.isFullMemberAndAdministrator(address)
        return (canEditConversationMembership && isLocalUserAdmin && canRevokeAdmin)
    }

    func memberActionSheetRevokeGroupAdminWasSelected(address: SignalServiceAddress) {
        let titleFormat = OWSLocalizedString("CONVERSATION_SETTINGS_REVOKE_GROUP_ADMIN_TITLE_FORMAT",
                                            comment: "Format for title for 'revoke group admin' confirmation alert. Embeds {user to revoke admin status from}.")
        let actionTitle =  OWSLocalizedString("CONVERSATION_SETTINGS_REVOKE_GROUP_ADMIN_BUTTON",
                                             comment: "Label for 'revoke group admin' button in conversation settings view.")
        showMemberActionConfirmationActionSheet(
            address: address,
            titleFormat: titleFormat,
            actionTitle: actionTitle,
            updateDescription: "Revoke group admin",
            updateBlock: { (oldGroupModel, aci: Aci) in
                GroupManager.changeMemberRoleV2(groupModel: oldGroupModel, aci: aci, role: .normal).asVoid()
            }
        )
    }

    // MARK: - Remove From Group

    // This action can be used to remove members _or_ revoke invites.
    func canRemoveFromGroup(address: SignalServiceAddress) -> Bool {
        guard let groupThread = thread as? TSGroupThread,
            groupThread.isGroupV2Thread else {
                return false
        }
        guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress else {
            owsFailDebug("Missing localAddress.")
            return false
        }
        // Only admins can kick out other members.
        let groupMembership = groupThread.groupModel.groupMembership
        let isLocalUserAdmin = groupMembership.isFullMemberAndAdministrator(localAddress)
        let isAddressInGroup = groupMembership.isMemberOfAnyKind(address)
        let isRemovalTargetLocalAdress = address.isLocalAddress
        return canEditConversationMembership && isLocalUserAdmin && isAddressInGroup && !isRemovalTargetLocalAdress
    }

    func presentRemoveFromGroupActionSheet(address: SignalServiceAddress) {
        let titleFormat = OWSLocalizedString("CONVERSATION_SETTINGS_REMOVE_FROM_GROUP_TITLE_FORMAT",
                                            comment: "Format for title for 'remove from group' confirmation alert. Embeds {user to remove from the group}.")
        let actionTitle =  OWSLocalizedString("CONVERSATION_SETTINGS_REMOVE_FROM_GROUP_BUTTON",
                                             comment: "Label for 'remove from group' button in conversation settings view.")
        showMemberActionConfirmationActionSheet(
            address: address,
            titleFormat: titleFormat,
            actionTitle: actionTitle,
            updateDescription: "Remove user from group",
            updateBlock: { (oldGroupModel, serviceId: ServiceId) in
                GroupManager.removeFromGroupOrRevokeInviteV2(groupModel: oldGroupModel, serviceIds: [serviceId]).asVoid()
            }
        )
    }
}
