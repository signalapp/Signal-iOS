//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

protocol GroupMemberViewDelegate: class {
    var groupMemberViewRecipientSet: OrderedSet<PickedRecipient> { get }

    var groupMemberViewHasUnsavedChanges: Bool { get }

    var shouldTryToEnableGroupsV2ForMembers: Bool { get }

    func groupMemberViewRemoveRecipient(_ recipient: PickedRecipient)

    func groupMemberViewAddRecipient(_ recipient: PickedRecipient)

    func groupMemberViewCanAddRecipient(_ recipient: PickedRecipient) -> Bool

    func groupMemberViewShouldShowMemberCount() -> Bool

    func groupMemberViewGroupMemberCountForDisplay() -> Int

    func groupMemberViewIsGroupFull_HardLimit() -> Bool

    func groupMemberViewIsGroupFull_RecommendedLimit() -> Bool

    func groupMemberViewIsPreExistingMember(_ recipient: PickedRecipient) -> Bool

    func groupMemberViewIsGroupsV2Required() -> Bool

    func groupMemberViewDismiss()

    var isNewGroup: Bool { get }
}

// MARK: -

// A base class used in two scenarios:
//
// * Picking members for a new group.
// * Add new members to an existing group.
@objc
public class BaseGroupMemberViewController: OWSViewController {

    // This delegate is the subclass.
    weak var groupMemberViewDelegate: GroupMemberViewDelegate?

    private var recipientSet: OrderedSet<PickedRecipient> {
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing groupMemberViewDelegate.")
            return OrderedSet<PickedRecipient>()
        }
        return groupMemberViewDelegate.groupMemberViewRecipientSet
    }

    var hasUnsavedChanges: Bool {
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing groupMemberViewDelegate.")
            return false
        }
        return groupMemberViewDelegate.groupMemberViewHasUnsavedChanges
    }

    private let recipientPicker = RecipientPickerViewController()

    private let memberBar = NewGroupMembersBar()
    private let memberCountLabel = UILabel()
    private let memberCountWrapper = UIView()

    public override init() {
        super.init()
    }

    // MARK: - View Lifecycle

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Theme.backgroundColor

        // First section.

        memberBar.delegate = self

        // Don't use dynamic type in this label.
        memberCountLabel.font = UIFont.ows_dynamicTypeBody2.withSize(12)
        memberCountLabel.textColor = Theme.secondaryTextAndIconColor
        memberCountLabel.textAlignment = CurrentAppContext().isRTL ? .left : .right

        memberCountWrapper.addSubview(memberCountLabel)
        memberCountLabel.autoPinEdgesToSuperviewMargins()
        memberCountWrapper.layoutMargins = UIEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)

        recipientPicker.allowsSelectingUnregisteredPhoneNumbers = false
        recipientPicker.shouldShowGroups = false
        recipientPicker.allowsSelectingUnregisteredPhoneNumbers = false
        recipientPicker.showUseAsyncSelection = true
        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)

        recipientPicker.view.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        recipientPicker.view.autoPinEdge(toSuperviewSafeArea: .leading)
        recipientPicker.view.autoPinEdge(toSuperviewSafeArea: .trailing)
        autoPinView(toBottomOfViewControllerOrKeyboard: recipientPicker.view, avoidNotch: false)

        updateMemberCount()
        tryToFillInMissingUuids()
    }

    private func tryToFillInMissingUuids() {
        let addresses = contactsViewHelper.allSignalAccounts.map { $0.recipientAddress }
        firstly {
            GroupManager.tryToFillInMissingUuids(for: addresses, isBlocking: false)
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

    @objc
    public override func viewWillLayoutSubviews() {
        updateMemberBarHeightConstraint()

        super.viewWillLayoutSubviews()
    }

    private func updateMemberBarHeightConstraint() {
        memberBar.updateHeightConstraint()
    }

    private func updateMemberCount() {
        guard !recipientSet.isEmpty else {
            memberCountWrapper.isHidden = true
            return
        }
        guard let groupMemberViewDelegate = groupMemberViewDelegate,
            groupMemberViewDelegate.groupMemberViewShouldShowMemberCount() else {
            memberCountWrapper.isHidden = true
            return
        }

        memberCountWrapper.isHidden = false
        let format = NSLocalizedString("GROUP_MEMBER_COUNT_WITHOUT_LIMIT_FORMAT",
                                       comment: "Format string for the group member count indicator. Embeds {{ the number of members in the group }}.")
        let memberCount = groupMemberViewDelegate.groupMemberViewGroupMemberCountForDisplay()

        memberCountLabel.text = String(format: format,
                                       OWSFormat.formatInt(memberCount))
        if memberCount >= GroupManager.groupsV2MaxGroupSizeRecommended {
            memberCountLabel.textColor = .ows_accentRed
        } else {
            memberCountLabel.textColor = Theme.primaryTextColor
        }
    }

    public func removeRecipient(_ recipient: PickedRecipient) {
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing groupMemberViewDelegate.")
            return
        }
        groupMemberViewDelegate.groupMemberViewRemoveRecipient(recipient)
        recipientPicker.pickedRecipients = recipientSet.orderedMembers
        updateMemberBar()
        updateMemberCount()
    }

    public func addRecipient(_ recipient: PickedRecipient) {
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing groupMemberViewDelegate.")
            return
        }
        guard !recipientSet.contains(recipient) else {
            owsFailDebug("Recipient already added.")
            return
        }
        guard groupMemberViewDelegate.groupMemberViewCanAddRecipient(recipient) else {
            GroupViewUtils.showInvalidGroupMemberAlert(fromViewController: self)
            return
        }
        guard !groupMemberViewDelegate.groupMemberViewIsGroupFull_HardLimit() else {
            showGroupFullAlert_HardLimit()
            return
        }
        if groupMemberViewDelegate.groupMemberViewIsGroupFull_RecommendedLimit() {
            showGroupFullAlert_SoftLimit(recipient: recipient, groupMemberViewDelegate: groupMemberViewDelegate)
            return
        } else {
            addRecipientStep2(recipient, groupMemberViewDelegate: groupMemberViewDelegate)
        }
    }

    private func addRecipientStep2(_ recipient: PickedRecipient,
                                   groupMemberViewDelegate: GroupMemberViewDelegate) {

        groupMemberViewDelegate.groupMemberViewAddRecipient(recipient)
        recipientPicker.pickedRecipients = recipientSet.orderedMembers
        recipientPicker.clearSearchText()
        updateMemberBar()
        updateMemberCount()

        memberBar.scrollToRecipient(recipient)
    }

    private func updateMemberBar() {
        memberBar.setMembers(databaseStorage.uiRead { transaction in
            self.orderedMembers(shouldSort: false, transaction: transaction)
        })
    }

    private func orderedMembers(shouldSort: Bool, transaction: SDSAnyReadTransaction) -> [NewGroupMember] {
        return Self.orderedMembers(recipientSet: recipientSet, shouldSort: shouldSort, transaction: transaction)
    }

    class func orderedMembers(recipientSet: OrderedSet<PickedRecipient>,
                              shouldSort: Bool,
                              transaction: SDSAnyReadTransaction) -> [NewGroupMember] {
        var members = recipientSet.orderedMembers.compactMap { (recipient: PickedRecipient) -> NewGroupMember? in
            guard let address = recipient.address else {
                owsFailDebug("Invalid recipient.")
                return nil
            }
            let displayName = self.contactsManager.displayName(for: address, transaction: transaction)
            let shortDisplayName = self.contactsManager.shortDisplayName(for: address, transaction: transaction)
            let comparableName = self.contactsManager.comparableName(for: address, transaction: transaction)
            let conversationColorName = self.contactsManager.conversationColorName(for: address, transaction: transaction)
            return NewGroupMember(recipient: recipient,
                                  address: address,
                                  displayName: displayName,
                                  shortName: shortDisplayName,
                                  comparableName: comparableName,
                                  conversationColorName: conversationColorName)
        }
        if shouldSort {
            members.sort { (left, right) in
                return left.comparableName < right.comparableName
            }
        }
        return members
    }

    private func showGroupFullAlert_HardLimit() {
        let format = NSLocalizedString("EDIT_GROUP_ERROR_CANNOT_ADD_MEMBER_GROUP_FULL_FORMAT",
                                       comment: "Format for the 'group full' error alert when a user can't be added to a group because the group is full. Embeds {{ the maximum number of members in a group }}.")
        let message = String(format: format, OWSFormat.formatUInt(GroupManager.groupsV2MaxGroupSizeHardLimit))
        OWSActionSheets.showErrorAlert(message: message)
    }

    private func showGroupFullAlert_SoftLimit(recipient: PickedRecipient,
                                              groupMemberViewDelegate: GroupMemberViewDelegate) {
        let title = NSLocalizedString("GROUPS_TOO_MANY_MEMBERS_ALERT_TITLE",
                                      comment: "Title for alert warning the user that they've reached the recommended limit on how many members can be in a group.")
        let messageFormat = NSLocalizedString("GROUPS_TOO_MANY_MEMBERS_ALERT_MESSAGE_FORMAT",
                                              comment: "Format for the alert warning the user that they've reached the recommended limit on how many members can be in a group when creating a new group. Embeds {{ the maximum number of recommended members in a group }}.")
        var message = String(format: messageFormat, OWSFormat.formatUInt(GroupManager.groupsV2MaxGroupSizeRecommended))

        if groupMemberViewDelegate.isNewGroup {
            let actionSheet = ActionSheetController(title: title, message: message)

            actionSheet.addAction(ActionSheetAction(title: CommonStrings.okayButton) { [weak self] _ in
                guard let self = self else { return }
                self.addRecipientStep2(recipient, groupMemberViewDelegate: groupMemberViewDelegate)
            })
            presentActionSheet(actionSheet)
        } else {
            message += ("\n\n"
                            + NSLocalizedString("GROUPS_TOO_MANY_MEMBERS_CONFIRM",
                                                comment: "Message asking the user to confirm that they want to add a member to the group."))
            let actionSheet = ActionSheetController(title: title, message: message)

            actionSheet.addAction(ActionSheetAction(title: CommonStrings.addButton) { [weak self] _ in
                guard let self = self else { return }
                self.addRecipientStep2(recipient, groupMemberViewDelegate: groupMemberViewDelegate)
            })
            actionSheet.addAction(OWSActionSheets.cancelAction)
            presentActionSheet(actionSheet)
        }
    }

    // MARK: -

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        guard let navigationController = navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }
        if navigationController.viewControllers.count == 1 {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .stop,
                                                               target: self,
                                                               action: #selector(dismissPressed))
        }
    }

    @objc
    func dismissPressed() {
        if !self.hasUnsavedChanges {
            // If user made no changes, dismiss.
            self.groupMemberViewDelegate?.groupMemberViewDismiss()
            return
        }

        OWSActionSheets.showPendingChangesActionSheet { [weak self] in
            self?.groupMemberViewDelegate?.groupMemberViewDismiss()
        }
    }

    // MARK: - Event Handling

    private func backButtonPressed() {

        guard let navigationController = navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }

        if !hasUnsavedChanges {
            // If user made no changes, return to previous view.
            navigationController.popViewController(animated: true)
            return
        }

        OWSActionSheets.showPendingChangesActionSheet { [weak self] in
            self?.groupMemberViewDelegate?.groupMemberViewDismiss()
        }
    }
}

// MARK: -

extension BaseGroupMemberViewController: RecipientPickerDelegate {

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         canSelectRecipient recipient: PickedRecipient) -> RecipientPickerRecipientState {
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing groupMemberViewDelegate.")
            return .unknownError
        }
        guard !groupMemberViewDelegate.groupMemberViewIsPreExistingMember(recipient) else {
            return .duplicateGroupMember
        }
        return .canBeSelected
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         didSelectRecipient recipient: PickedRecipient) {
        guard let address = recipient.address else {
            owsFailDebug("Missing address.")
            return
        }
        guard address.isValid else {
            owsFailDebug("Invalid address.")
            return
        }
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing groupMemberViewDelegate.")
            return
        }
        guard !groupMemberViewDelegate.groupMemberViewIsPreExistingMember(recipient) else {
            owsFailDebug("Can't re-add pre-existing member.")
            return
        }
        guard let navigationController = navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }

        let isCurrentMember = recipientSet.contains(recipient)
        let isBlocked = self.contactsViewHelper.isSignalServiceAddressBlocked(address)

        let addRecipientCompletion = { [weak self] in
            guard let self = self else {
                return
            }
            self.addRecipient(recipient)
            navigationController.popToViewController(self, animated: true)
        }

        if isCurrentMember {
            removeRecipient(recipient)
        } else if isBlocked {
            BlockListUIUtils.showUnblockAddressActionSheet(address,
                                                           from: self) { isStillBlocked in
                                                            if !isStillBlocked {
                                                                addRecipientCompletion()
                                                            }
            }
        } else {
            let confirmationText = NSLocalizedString("SAFETY_NUMBER_CHANGED_CONFIRM_ADD_TO_GROUP_ACTION",
                                                     comment: "button title to confirm adding a recipient to a group when their safety number has recently changed")
            let didShowSNAlert = SafetyNumberConfirmationSheet.presentIfNecessary(
                address: address,
                confirmationText: confirmationText
            ) { didConfirmIdentity in
                guard didConfirmIdentity else { return }
                addRecipientCompletion()
            }

            if didShowSNAlert {
                return
            }

            addRecipientCompletion()
        }
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         willRenderRecipient recipient: PickedRecipient) {
        guard let address = recipient.address else {
            owsFailDebug("Invalid recipient.")
            return
        }
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing delegate.")
            return
        }
        guard groupMemberViewDelegate.shouldTryToEnableGroupsV2ForMembers else {
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

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         prepareToSelectRecipient recipient: PickedRecipient) -> AnyPromise {
        guard let address = recipient.address else {
            owsFailDebug("Invalid recipient.")
            return AnyPromise(Promise.value(()))
        }
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing delegate.")
            return AnyPromise(Promise.value(()))
        }
        guard groupMemberViewDelegate.shouldTryToEnableGroupsV2ForMembers else {
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

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         showInvalidRecipientAlert recipient: PickedRecipient) {
        AssertIsOnMainThread()
        GroupViewUtils.showInvalidGroupMemberAlert(fromViewController: self)
    }

    private func doesRecipientSupportGroupsV2(_ recipient: PickedRecipient) -> Bool {
        guard let address = recipient.address else {
            owsFailDebug("Invalid recipient.")
            return false
        }
        return doesRecipientSupportGroupsV2(address)
    }

    private func doesRecipientSupportGroupsV2(_ address: SignalServiceAddress) -> Bool {
        return databaseStorage.read { transaction in
            return GroupManager.doesUserSupportGroupsV2(address: address, transaction: transaction)
        }
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

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         accessoryMessageForRecipient recipient: PickedRecipient) -> String? {
        guard let address = recipient.address else {
            owsFailDebug("Missing address.")
            return nil
        }
        guard address.isValid else {
            owsFailDebug("Invalid address.")
            return nil
        }

        let isCurrentMember = recipientSet.contains(recipient)
        let isBlocked = self.contactsViewHelper.isSignalServiceAddressBlocked(address)

        if isCurrentMember {
            return nil
        } else if isBlocked {
            return MessageStrings.conversationIsBlocked
        } else {
            return nil
        }
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         accessoryViewForRecipient recipient: PickedRecipient) -> UIView? {
        guard let address = recipient.address else {
            owsFailDebug("Missing address.")
            return nil
        }
        guard address.isValid else {
            owsFailDebug("Invalid address.")
            return nil
        }
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing groupMemberViewDelegate.")
            return nil
        }

        let isCurrentMember = recipientSet.contains(recipient)
        let isBlocked = self.contactsViewHelper.isSignalServiceAddressBlocked(address)
        let isPreExistingMember = groupMemberViewDelegate.groupMemberViewIsPreExistingMember(recipient)

        let imageView = UIImageView()
        if isPreExistingMember {
            imageView.setTemplateImageName("check-circle-solid-24", tintColor: Theme.washColor)
        } else if isCurrentMember {
            imageView.setTemplateImageName("check-circle-solid-24", tintColor: Theme.accentBlueColor)
        } else if isBlocked {
            // Use accessoryMessageForRecipient: to show blocked indicator.
            return nil
        } else {
            imageView.setTemplateImageName("empty-circle-outline-24", tintColor: .ows_gray25)
        }
        return imageView
    }

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         attributedSubtitleForRecipient recipient: PickedRecipient) -> NSAttributedString? {
        guard let address = recipient.address else {
            owsFailDebug("Recipient missing address.")
            return nil
        }
        var items = [String]()
        if address.uuid == nil {
            // This is internal-only; we don't need to localize.
            items.append("No UUID")
        }
        databaseStorage.read { transaction in
            if !GroupManager.doesUserHaveGroupsV2Capability(address: address,
                                                            transaction: transaction) {
                // This is internal-only; we don't need to localize.
                items.append("No capability")
            }
        }

        guard !items.isEmpty else {
            return nil
        }
        if GroupManager.areMigrationsBlocking {
            let warning = NSLocalizedString("NEW_GROUP_CREATION_MEMBER_DOES_NOT_SUPPORT_NEW_GROUPS",
                                            comment: "Indicates that a group member does not support New Groups.")
            return warning.attributedString()
       }
        guard DebugFlags.groupsV2memberStatusIndicators else {
            return nil
        }
        return NSAttributedString(string: items.joined(separator: ", "),
                                  attributes: [
                                    .font: UIFont.ows_dynamicTypeSubheadline.ows_semibold,
                                    .foregroundColor: Theme.secondaryTextAndIconColor
        ])
    }

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController) {}

    func recipientPickerNewGroupButtonWasPressed() {}

    func recipientPickerCustomHeaderViews() -> [UIView] {
        return [memberBar, memberCountWrapper]
    }
}

// MARK: -

extension BaseGroupMemberViewController: OWSNavigationView {

    public func shouldCancelNavigationBack() -> Bool {
        let hasUnsavedChanges = self.hasUnsavedChanges
        if hasUnsavedChanges {
            backButtonPressed()
        }
        return hasUnsavedChanges
    }
}

// MARK: -

extension BaseGroupMemberViewController: NewGroupMembersBarDelegate {
}
