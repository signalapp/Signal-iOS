//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

protocol GroupMemberViewDelegate: AnyObject {
    var groupMemberViewRecipientSet: OrderedSet<PickedRecipient> { get }

    var groupMemberViewHasUnsavedChanges: Bool { get }

    func groupMemberViewRemoveRecipient(_ recipient: PickedRecipient)

    func groupMemberViewAddRecipient(_ recipient: PickedRecipient)

    func groupMemberViewCanAddRecipient(_ recipient: PickedRecipient) -> Bool

    func groupMemberViewShouldShowMemberCount() -> Bool

    func groupMemberViewGroupMemberCountForDisplay() -> Int

    func groupMemberViewIsGroupFull_HardLimit() -> Bool

    func groupMemberViewIsGroupFull_RecommendedLimit() -> Bool

    func groupMemberViewIsPreExistingMember(_ recipient: PickedRecipient,
                                            transaction: SDSAnyReadTransaction) -> Bool

    func groupMemberViewIsGroupsV2Required() -> Bool

    func groupMemberViewDismiss()

    var isNewGroup: Bool { get }

    var groupThreadForGroupMemberView: TSGroupThread? { get }
}

// MARK: -

// A base class used in two scenarios:
//
// * Picking members for a new group.
// * Add new members to an existing group.
@objc
public class BaseGroupMemberViewController: BaseMemberViewController {

    // This delegate is the subclass.
    weak var groupMemberViewDelegate: GroupMemberViewDelegate?

    public override init() {
        super.init()

        memberViewDelegate = self
    }

    private func showGroupFullAlert_HardLimit() {
        let format = NSLocalizedString("EDIT_GROUP_ERROR_CANNOT_ADD_MEMBER_GROUP_FULL_%d", tableName: "PluralAware",
                                       comment: "Format for the 'group full' error alert when a user can't be added to a group because the group is full. Embeds {{ the maximum number of members in a group }}.")
        let message = String.localizedStringWithFormat(format, GroupManager.groupsV2MaxGroupSizeHardLimit)
        OWSActionSheets.showErrorAlert(message: message)
    }

    private var ignoreSoftLimit = false
    private func showGroupFullAlert_SoftLimit(recipient: PickedRecipient,
                                              groupMemberViewDelegate: GroupMemberViewDelegate) {
        let title = NSLocalizedString("GROUPS_TOO_MANY_MEMBERS_ALERT_TITLE",
                                      comment: "Title for alert warning the user that they've reached the recommended limit on how many members can be in a group.")
        let messageFormat = NSLocalizedString("GROUPS_TOO_MANY_MEMBERS_ALERT_MESSAGE_%d", tableName: "PluralAware",
                                              comment: "Format for the alert warning the user that they've reached the recommended limit on how many members can be in a group when creating a new group. Embeds {{ the maximum number of recommended members in a group }}.")
        var message = String.localizedStringWithFormat(messageFormat, GroupManager.groupsV2MaxGroupSizeRecommended)

        if groupMemberViewDelegate.isNewGroup {
            let actionSheet = ActionSheetController(title: title, message: message)

            actionSheet.addAction(ActionSheetAction(title: CommonStrings.okayButton) { [weak self] _ in
                guard let self = self else { return }
                self.ignoreSoftLimit = true
                self.addRecipient(recipient)
                self.ignoreSoftLimit = false
            })
            presentActionSheet(actionSheet)
        } else {
            message += ("\n\n"
                            + NSLocalizedString("GROUPS_TOO_MANY_MEMBERS_CONFIRM",
                                                comment: "Message asking the user to confirm that they want to add a member to the group."))
            let actionSheet = ActionSheetController(title: title, message: message)

            actionSheet.addAction(ActionSheetAction(title: CommonStrings.addButton) { [weak self] _ in
                guard let self = self else { return }
                self.ignoreSoftLimit = true
                self.addRecipient(recipient)
                self.ignoreSoftLimit = false
            })
            actionSheet.addAction(OWSActionSheets.cancelAction)
            presentActionSheet(actionSheet)
        }
    }
}

extension BaseGroupMemberViewController: MemberViewDelegate {
    public var memberViewRecipientSet: OrderedSet<PickedRecipient> {
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing groupMemberViewDelegate.")
            return OrderedSet()
        }
        return groupMemberViewDelegate.groupMemberViewRecipientSet
    }

    public var memberViewHasUnsavedChanges: Bool {
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing groupMemberViewDelegate.")
            return false
        }
        return groupMemberViewDelegate.groupMemberViewHasUnsavedChanges
    }

    public func memberViewRemoveRecipient(_ recipient: PickedRecipient) {
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing groupMemberViewDelegate.")
            return
        }
        groupMemberViewDelegate.groupMemberViewRemoveRecipient(recipient)
    }

    public func memberViewAddRecipient(_ recipient: PickedRecipient) {
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing groupMemberViewDelegate.")
            return
        }
        groupMemberViewDelegate.groupMemberViewAddRecipient(recipient)
    }

    public func memberViewCanAddRecipient(_ recipient: PickedRecipient) -> Bool {
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing groupMemberViewDelegate.")
            return false
        }
        guard groupMemberViewDelegate.groupMemberViewCanAddRecipient(recipient) else {
            GroupViewUtils.showInvalidGroupMemberAlert(fromViewController: self)
            return false
        }
        guard !groupMemberViewDelegate.groupMemberViewIsGroupFull_HardLimit() else {
            showGroupFullAlert_HardLimit()
            return false
        }
        guard ignoreSoftLimit || !groupMemberViewDelegate.groupMemberViewIsGroupFull_RecommendedLimit() else {
            showGroupFullAlert_SoftLimit(recipient: recipient, groupMemberViewDelegate: groupMemberViewDelegate)
            return false
        }
        return true
    }

    public func memberViewWillRenderRecipient(_ recipient: PickedRecipient) {
        guard let address = recipient.address else {
            owsFailDebug("Invalid recipient.")
            return
        }
        DispatchQueue.global().async {
            if !self.doesRecipientSupportGroupsV2(recipient) {
                _ = self.tryToEnableGroupsV2ForAddress(address,
                                                       isBlocking: false,
                                                       ignoreErrors: true)
            }
        }
    }

    public func memberViewPrepareToSelectRecipient(_ recipient: PickedRecipient) -> AnyPromise {
        guard let address = recipient.address else {
            owsFailDebug("Invalid recipient.")
            return AnyPromise(Promise.value(()))
        }
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing delegate.")
            return AnyPromise(Promise.value(()))
        }
        guard !doesRecipientSupportGroupsV2(recipient) else {
            // Recipient already supports groups v2.
            return AnyPromise(Promise.value(()))
        }
        let ignoreErrors = !groupMemberViewDelegate.groupMemberViewIsGroupsV2Required()
        return AnyPromise(tryToEnableGroupsV2ForAddress(address,
                                                        isBlocking: true,
                                                        ignoreErrors: ignoreErrors))
    }

    private func doesRecipientSupportGroupsV2(_ recipient: PickedRecipient) -> Bool {
        guard let address = recipient.address else {
            owsFailDebug("Invalid recipient.")
            return false
        }
        return doesRecipientSupportGroupsV2(address)
    }

    private func doesRecipientSupportGroupsV2(_ address: SignalServiceAddress) -> Bool {
        return GroupManager.doesUserSupportGroupsV2(address: address)
    }

    func tryToEnableGroupsV2ForAddress(_ address: SignalServiceAddress,
                                       isBlocking: Bool,
                                       ignoreErrors: Bool) -> Promise<Void> {
        return firstly { () -> Promise<Void> in
            return GroupManager.tryToEnableGroupsV2(for: [address],
                                                    isBlocking: isBlocking,
                                                    ignoreErrors: ignoreErrors)
        }.done(on: .global() ) { [weak self] _ in
            // If we succeeded in enable groups v2 for this address,
            // reload the recipient picker to reflect that.
            if self?.doesRecipientSupportGroupsV2(address) ?? false {
                DispatchQueue.main.async {
                    // Reload view content.
                    self?.recipientPicker.reloadContent()
                }
            }
        }
    }

    public func memberViewNoUuidSubtitleForRecipient(_ recipient: PickedRecipient) -> String? {
        return NSLocalizedString("NEW_GROUP_CREATION_MEMBER_DOES_NOT_SUPPORT_NEW_GROUPS",
                                 comment: "Indicates that a group member does not support New Groups.")
    }

    public func memberViewShouldShowMemberCount() -> Bool {
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing groupMemberViewDelegate.")
            return false
        }
        return groupMemberViewDelegate.groupMemberViewShouldShowMemberCount()
    }

    public func memberViewShouldAllowBlockedSelection() -> Bool { false }

    public func memberViewMemberCountForDisplay() -> Int {
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing groupMemberViewDelegate.")
            return 0
        }
        return groupMemberViewDelegate.groupMemberViewGroupMemberCountForDisplay()
    }

    public func memberViewIsPreExistingMember(_ recipient: PickedRecipient, transaction: SDSAnyReadTransaction) -> Bool {
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing groupMemberViewDelegate.")
            return false
        }
        return groupMemberViewDelegate.groupMemberViewIsPreExistingMember(recipient, transaction: transaction)
    }

    public func memberViewCustomIconNameForPickedMember(_ recipient: PickedRecipient) -> String? { nil }

    public func memberViewCustomIconColorForPickedMember(_ recipient: PickedRecipient) -> UIColor? { nil }

    public func memberViewDismiss() {
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing groupMemberViewDelegate.")
            return
        }
        groupMemberViewDelegate.groupMemberViewDismiss()
    }
}
