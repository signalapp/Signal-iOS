//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

extension GroupViewHelper {

    // This group of member actions follow a similar pattern:
    //
    // * Show a confirmation alert.
    // * Present a modal activity indicator.
    // * Perform the action using a promise.
    // * Reload the group model and update the table content.
    private func showMemberActionConfirmationActionSheet(address: SignalServiceAddress,
                                                         titleFormat: String,
                                                         actionTitle: String,
                                                         updatePromiseBlock: @escaping () -> Promise<Void>) {
        guard let fromViewController = fromViewController else {
            owsFailDebug("Missing fromViewController.")
            return
        }
        let actionBlock = {
            GroupViewUtils.updateGroupWithActivityIndicator(fromViewController: fromViewController,
                                                            updatePromiseBlock: updatePromiseBlock,
                                                            completion: { [weak self] _ in
                                                                self?.delegate?.groupViewHelperDidUpdateGroup()
            })
        }
        let title = String(format: titleFormat, contactsManager.displayName(for: address))
        let actionSheet = ActionSheetController(title: title)
        actionSheet.addAction(ActionSheetAction(title: actionTitle,
                                                style: .default,
                                                handler: { _ in
                                                    actionBlock()
        }))
        actionSheet.addAction(OWSActionSheets.cancelAction)
        fromViewController.presentActionSheet(actionSheet)
    }

    // MARK: - Make Group Admin

    func memberActionSheetCanMakeGroupAdmin(address: SignalServiceAddress) -> Bool {
        guard let groupThread = thread as? TSGroupThread,
            groupThread.isGroupV2Thread else {
                return false
        }
        guard let localAddress = tsAccountManager.localAddress else {
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
        let titleFormat = NSLocalizedString("CONVERSATION_SETTINGS_MAKE_GROUP_ADMIN_TITLE_FORMAT",
                                            comment: "Format for title for 'make group admin' confirmation alert. Embeds {user to make an admin}.")
        let actionTitle =  NSLocalizedString("CONVERSATION_SETTINGS_MAKE_GROUP_ADMIN_BUTTON",
                                             comment: "Label for 'make group admin' button in conversation settings view.")
        showMemberActionConfirmationActionSheet(address: address,
                                                titleFormat: titleFormat,
                                                actionTitle: actionTitle) {
                                                    self.makeGroupAdminPromise(address: address)
        }
    }

    private func makeGroupAdminPromise(address: SignalServiceAddress) -> Promise<Void> {
        guard let oldGroupModel = delegate?.currentGroupModel as? TSGroupModelV2 else {
            return Promise(error: OWSAssertionError("Missing group model."))
        }
        guard oldGroupModel.groupMembership.isMemberOfAnyKind(address) else {
            return Promise(error: OWSAssertionError("Not a group member."))
        }
        guard let uuid = address.uuid else {
            return Promise(error: OWSAssertionError("Invalid member address."))
        }
        return firstly {
            return GroupManager.messageProcessingPromise(for: oldGroupModel,
                                                         description: "Make group admin")
        }.then(on: .global()) {
            GroupManager.changeMemberRoleV2(groupModel: oldGroupModel, uuid: uuid, role: .administrator)
        }.asVoid()
    }

    // MARK: - Revoke Group Admin

    func memberActionSheetCanRevokeGroupAdmin(address: SignalServiceAddress) -> Bool {
        guard let groupThread = thread as? TSGroupThread,
            groupThread.isGroupV2Thread else {
                return false
        }
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return false
        }
        let groupMembership = groupThread.groupModel.groupMembership
        let isLocalUserAdmin = groupMembership.isFullMemberAndAdministrator(localAddress)
        let canRevokeAdmin = groupMembership.isFullMemberAndAdministrator(address)
        return (canEditConversationMembership && isLocalUserAdmin && canRevokeAdmin)
    }

    func memberActionSheetRevokeGroupAdminWasSelected(address: SignalServiceAddress) {
        let titleFormat = NSLocalizedString("CONVERSATION_SETTINGS_REVOKE_GROUP_ADMIN_TITLE_FORMAT",
                                            comment: "Format for title for 'revoke group admin' confirmation alert. Embeds {user to revoke admin status from}.")
        let actionTitle =  NSLocalizedString("CONVERSATION_SETTINGS_REVOKE_GROUP_ADMIN_BUTTON",
                                             comment: "Label for 'revoke group admin' button in conversation settings view.")
        showMemberActionConfirmationActionSheet(address: address,
                                                titleFormat: titleFormat,
                                                actionTitle: actionTitle) {
                                                    self.revokeGroupAdminPromise(address: address)
        }
    }

    private func revokeGroupAdminPromise(address: SignalServiceAddress) -> Promise<Void> {
        guard let oldGroupModel = delegate?.currentGroupModel as? TSGroupModelV2 else {
            return Promise(error: OWSAssertionError("Missing group model."))
        }
        guard oldGroupModel.groupMembership.isMemberOfAnyKind(address) else {
            return Promise(error: OWSAssertionError("Not a group member."))
        }
        guard let uuid = address.uuid else {
            return Promise(error: OWSAssertionError("Invalid member address."))
        }
        return firstly {
            return GroupManager.messageProcessingPromise(for: oldGroupModel,
                                                         description: "Revoke group admin")
        }.then(on: .global()) {
            GroupManager.changeMemberRoleV2(groupModel: oldGroupModel, uuid: uuid, role: .normal)
        }.asVoid()
    }

    // MARK: - Remove From Group

    // This action can be used to remove members _or_ revoke invites.
    func memberActionSheetCanRemoveFromGroup(address: SignalServiceAddress) -> Bool {
        guard let groupThread = thread as? TSGroupThread,
            groupThread.isGroupV2Thread else {
                return false
        }
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing localAddress.")
            return false
        }
        // Only admins can kick out other members.
        let groupMembership = groupThread.groupModel.groupMembership
        let isLocalUserAdmin = groupMembership.isFullMemberAndAdministrator(localAddress)
        let isAddressInGroup = groupMembership.isMemberOfAnyKind(address)
        return canEditConversationMembership && isLocalUserAdmin && isAddressInGroup
    }

    func memberActionSheetRemoveFromGroupWasSelected(address: SignalServiceAddress) {
        let titleFormat = NSLocalizedString("CONVERSATION_SETTINGS_REMOVE_FROM_GROUP_TITLE_FORMAT",
                                            comment: "Format for title for 'remove from group' confirmation alert. Embeds {user to remove from the group}.")
        let actionTitle =  NSLocalizedString("CONVERSATION_SETTINGS_REMOVE_FROM_GROUP_BUTTON",
                                             comment: "Label for 'remove from group' button in conversation settings view.")
        showMemberActionConfirmationActionSheet(address: address,
                                                titleFormat: titleFormat,
                                                actionTitle: actionTitle) {
                                                    self.removeFromGroupPromise(address: address)
        }
    }

    private func removeFromGroupPromise(address: SignalServiceAddress) -> Promise<Void> {
        guard let oldGroupModel = delegate?.currentGroupModel as? TSGroupModelV2 else {
            return Promise(error: OWSAssertionError("Missing group model."))
        }
        guard oldGroupModel.groupMembership.isMemberOfAnyKind(address) else {
            return Promise(error: OWSAssertionError("Not a group member."))
        }
        guard let uuid = address.uuid else {
            return Promise(error: OWSAssertionError("Invalid member address."))
        }
        return firstly {
            return GroupManager.messageProcessingPromise(for: oldGroupModel,
                                                         description: "Remove user from group")
        }.then(on: .global()) {
            GroupManager.removeFromGroupOrRevokeInviteV2(groupModel: oldGroupModel, uuids: [uuid])
        }.asVoid()
    }
}
