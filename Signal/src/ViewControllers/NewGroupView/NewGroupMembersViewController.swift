//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

// TODO: Rename to NewGroupViewController; remove old view.
@objc
public class NewGroupMembersViewController: BaseGroupMemberViewController {

    private var newGroupState = NewGroupState()

    public required override init() {
        super.init()

        groupMemberViewDelegate = self
    }

    // MARK: - View Lifecycle

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("NEW_GROUP_SELECT_MEMBERS_VIEW_TITLE",
                                  comment: "The title for the 'select members for new group' view.")

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
            = NSLocalizedString("FINISH_GROUP_CREATION_LABEL", comment: "Accessibility label for finishing new group")
        navigationItem.rightBarButtonItem = rightBarButtonItem
    }

    // MARK: - Actions

    @objc
    func nextButtonPressed() {
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

    var shouldTryToEnableGroupsV2ForMembers: Bool {
        true
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
        // GroupsV2 TODO: Currently we can add any user to any new group,
        // since we'll failover to using a v1 group if any members don't
        // support v2 groups.  Eventually, we'll want to reject certain
        // users.
        true
    }

    func groupMemberViewShouldShowMemberCount() -> Bool {
        true
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

    func groupMemberViewIsPreExistingMember(_ recipient: PickedRecipient) -> Bool {
        false
    }

    func groupMemberViewIsGroupsV2Required() -> Bool {
        // No, we can fail over to creating v1 groups.
        false
    }

    func groupMemberViewDismiss() {
        dismiss(animated: true)
    }

    var isNewGroup: Bool {
        true
    }
}
