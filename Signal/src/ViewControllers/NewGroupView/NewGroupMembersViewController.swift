//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

// TODO: Rename to NewGroupViewController; remove old view.
public class NewGroupMembersViewController: BaseGroupMemberViewController {

    private var newGroupState = NewGroupState()

    public required override init() {
        super.init()

        groupMemberViewDelegate = self
    }

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        updateBarButtons()
    }

    private func updateBarButtons() {
        let hasMembers = !newGroupState.recipientSet.isEmpty
        let buttonTitle = (hasMembers
                            ? CommonStrings.nextButton
                            : CommonStrings.skipButton)
        let rightBarButtonItem = UIBarButtonItem(title: buttonTitle,
                                                 style: .plain,
                                                 target: self,
                                                 action: #selector(nextButtonPressed),
                                                 accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "next"))
        rightBarButtonItem.imageInsets = UIEdgeInsets(top: 0, left: -1, bottom: 0, right: 10)
        rightBarButtonItem.accessibilityLabel
            = OWSLocalizedString("FINISH_GROUP_CREATION_LABEL", comment: "Accessibility label for finishing new group")
        navigationItem.rightBarButtonItem = rightBarButtonItem
        if hasMembers {
            let format = OWSLocalizedString("NEW_GROUP_MEMBERS_VIEW_TITLE_%d", tableName: "PluralAware", comment: "The title for the 'select members for new group' view if already some members are selected. Embeds {{number}} of members.")
            title = String.localizedStringWithFormat(format, newGroupState.recipientSet.count)
        } else {
            title = OWSLocalizedString("NEW_GROUP_SELECT_MEMBERS_VIEW_TITLE", comment: "The title for the 'select members for new group' view.")
        }
    }

    // MARK: - Actions

    @objc
    private func nextButtonPressed() {
        AssertIsOnMainThread()

        let confirmViewController = NewGroupConfirmViewController(newGroupState: newGroupState)
        navigationController?.pushViewController(confirmViewController, animated: true)
    }
}

// MARK: -

extension NewGroupMembersViewController: GroupMemberViewDelegate {

    var groupMemberViewRecipientSet: OrderedSet<PickedRecipient> {
        newGroupState.recipientSet
    }

    var groupMemberViewHasUnsavedChanges: Bool {
        newGroupState.hasUnsavedChanges
    }

    func groupMemberViewRemoveRecipient(_ recipient: PickedRecipient) {
        newGroupState.recipientSet.remove(recipient)
        updateBarButtons()
    }

    func groupMemberViewAddRecipient(_ recipient: PickedRecipient) {
        newGroupState.recipientSet.append(recipient)
        updateBarButtons()
    }

    func groupMemberViewCanAddRecipient(_ recipient: PickedRecipient) -> Bool {
        guard let address = recipient.address else {
            owsFailDebug("Invalid recipient.")
            return false
        }
        return GroupManager.doesUserSupportGroupsV2(address: address)
    }

    func groupMemberViewShouldShowMemberCount() -> Bool {
        false
    }

    func groupMemberViewGroupMemberCountForDisplay() -> Int {
        groupMemberViewGroupMemberCount(withSelf: false)
    }

    func groupMemberViewGroupMemberCount(withSelf: Bool) -> Int {
        // We sometimes add one for the local user.
        newGroupState.recipientSet.count + (withSelf ? 1 : 0)
    }

    func groupMemberViewIsGroupFull_HardLimit() -> Bool {
        groupMemberViewGroupMemberCount(withSelf: true) >= GroupManager.groupsV2MaxGroupSizeHardLimit
    }

    func groupMemberViewIsGroupFull_RecommendedLimit() -> Bool {
        groupMemberViewGroupMemberCount(withSelf: true) >= GroupManager.groupsV2MaxGroupSizeRecommended
    }

    func groupMemberViewIsPreExistingMember(_ recipient: PickedRecipient,
                                            transaction: SDSAnyReadTransaction) -> Bool {
        false
    }

    func groupMemberViewDismiss() {
        dismiss(animated: true)
    }

    var isNewGroup: Bool {
        true
    }

    var groupThreadForGroupMemberView: TSGroupThread? {
        nil
    }
}
