//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol MemberViewDelegate: AnyObject {
    var memberViewRecipientSet: OrderedSet<PickedRecipient> { get }

    var memberViewHasUnsavedChanges: Bool { get }

    func memberViewRemoveRecipient(_ recipient: PickedRecipient)

    func memberViewAddRecipient(_ recipient: PickedRecipient)

    func memberViewCanAddRecipient(_ recipient: PickedRecipient) -> Bool

    func memberViewPrepareToSelectRecipient(_ recipient: PickedRecipient) -> AnyPromise

    func memberViewShouldShowMemberCount() -> Bool

    func memberViewShouldAllowBlockedSelection() -> Bool

    func memberViewMemberCountForDisplay() -> Int

    func memberViewIsPreExistingMember(_ recipient: PickedRecipient,
                                       transaction: SDSAnyReadTransaction) -> Bool

    func memberViewCustomIconNameForPickedMember(_ recipient: PickedRecipient) -> String?

    func memberViewCustomIconColorForPickedMember(_ recipient: PickedRecipient) -> UIColor?

    func memberViewDismiss()
}

// MARK: -

@objc
open class BaseMemberViewController: RecipientPickerContainerViewController {

    // This delegate is the subclass.
    public weak var memberViewDelegate: MemberViewDelegate?

    private var recipientSet: OrderedSet<PickedRecipient> {
        guard let memberViewDelegate = memberViewDelegate else {
            owsFailDebug("Missing memberViewDelegate.")
            return OrderedSet<PickedRecipient>()
        }
        return memberViewDelegate.memberViewRecipientSet
    }

    open var hasUnsavedChanges: Bool {
        guard let memberViewDelegate = memberViewDelegate else {
            owsFailDebug("Missing memberViewDelegate.")
            return false
        }
        return memberViewDelegate.memberViewHasUnsavedChanges
    }

    private let memberBar = NewMembersBar()
    private let memberCountLabel = UILabel()
    private let memberCountWrapper = UIView()

    public override init() {
        super.init()
    }

    // MARK: - View Lifecycle

    @objc
    open override func viewDidLoad() {
        super.viewDidLoad()

        // First section.

        memberBar.delegate = self

        // Don't use dynamic type in this label.
        memberCountLabel.font = UIFont.ows_dynamicTypeBody2.withSize(12)
        memberCountLabel.textColor = Theme.isDarkThemeEnabled ? .ows_gray05 : .ows_gray60
        memberCountLabel.textAlignment = CurrentAppContext().isRTL ? .left : .right

        memberCountWrapper.addSubview(memberCountLabel)
        memberCountLabel.autoPinEdgesToSuperviewMargins()
        memberCountWrapper.layoutMargins = UIEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)

        recipientPicker.groupsToShow = .showNoGroups
        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)

        recipientPicker.view.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        recipientPicker.view.autoPinEdge(toSuperviewSafeArea: .leading)
        recipientPicker.view.autoPinEdge(toSuperviewSafeArea: .trailing)
        recipientPicker.view.autoPinEdge(.bottom, to: .bottom, of: keyboardLayoutGuideView)

        updateMemberCount()
    }

    @objc
    open override func viewWillLayoutSubviews() {
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
        guard let memberViewDelegate = memberViewDelegate,
              memberViewDelegate.memberViewShouldShowMemberCount() else {
            memberCountWrapper.isHidden = true
            return
        }

        memberCountWrapper.isHidden = false
        let format = OWSLocalizedString("GROUP_MEMBER_COUNT_WITHOUT_LIMIT_%d", tableName: "PluralAware",
                                        comment: "Format string for the group member count indicator. Embeds {{ the number of members in the group }}.")
        let memberCount = memberViewDelegate.memberViewMemberCountForDisplay()

        memberCountLabel.text = String.localizedStringWithFormat(format, memberCount)
        if memberCount >= GroupManager.groupsV2MaxGroupSizeRecommended {
            memberCountLabel.textColor = .ows_accentRed
        } else {
            memberCountLabel.textColor = Theme.primaryTextColor
        }
    }

    public func removeRecipient(_ recipient: PickedRecipient) {
        guard let memberViewDelegate = memberViewDelegate else {
            owsFailDebug("Missing memberViewDelegate.")
            return
        }
        memberViewDelegate.memberViewRemoveRecipient(recipient)
        recipientPicker.pickedRecipients = recipientSet.orderedMembers
        updateMemberBar()
        updateMemberCount()
    }

    public func addRecipient(_ recipient: PickedRecipient) {
        guard !recipientSet.contains(recipient) else {
            owsFailDebug("Recipient already added.")
            return
        }

        guard let memberViewDelegate = memberViewDelegate else {
            owsFailDebug("Missing memberViewDelegate.")
            return
        }

        guard memberViewDelegate.memberViewCanAddRecipient(recipient) else { return }

        memberViewDelegate.memberViewAddRecipient(recipient)
        recipientPicker.pickedRecipients = recipientSet.orderedMembers
        recipientPicker.clearSearchText()
        updateMemberBar()
        updateMemberCount()

        memberBar.scrollToRecipient(recipient)
    }

    private func updateMemberBar() {
        memberBar.setMembers(databaseStorage.read { transaction in
            self.orderedMembers(shouldSort: false, transaction: transaction)
        })
    }

    private func orderedMembers(shouldSort: Bool, transaction: SDSAnyReadTransaction) -> [NewMember] {
        return Self.orderedMembers(recipientSet: recipientSet, shouldSort: shouldSort, transaction: transaction)
    }

    public class func orderedMembers(recipientSet: OrderedSet<PickedRecipient>,
                                     shouldSort: Bool,
                                     transaction: SDSAnyReadTransaction) -> [NewMember] {
        var members = recipientSet.orderedMembers.compactMap { (recipient: PickedRecipient) -> NewMember? in
            guard let address = recipient.address else {
                owsFailDebug("Invalid recipient.")
                return nil
            }
            let displayName = self.contactsManager.displayName(for: address, transaction: transaction)
            let shortDisplayName = self.contactsManager.shortDisplayName(for: address, transaction: transaction)
            let comparableName = self.contactsManager.comparableName(for: address, transaction: transaction)
            return NewMember(recipient: recipient,
                             address: address,
                             displayName: displayName,
                             shortName: shortDisplayName,
                             comparableName: comparableName)
        }
        if shouldSort {
            members.sort { (left, right) in
                return left.comparableName < right.comparableName
            }
        }
        return members
    }

    // MARK: -

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        recipientPicker.pickedRecipients = recipientSet.orderedMembers

        updateMemberBar()
        updateMemberCount()

        guard let navigationController = navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }
        if navigationController.viewControllers.count == 1 {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                               target: self,
                                                               action: #selector(dismissPressed))
        }
    }

    @objc
    open func dismissPressed() {
        if !self.hasUnsavedChanges {
            // If user made no changes, dismiss.
            self.memberViewDelegate?.memberViewDismiss()
            return
        }

        OWSActionSheets.showPendingChangesActionSheet { [weak self] in
            self?.memberViewDelegate?.memberViewDismiss()
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
            self?.memberViewDelegate?.memberViewDismiss()
        }
    }
}

// MARK: -

extension BaseMemberViewController: RecipientPickerDelegate {

    public func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        getRecipientState recipient: PickedRecipient
    ) -> RecipientPickerRecipientState {
        guard let memberViewDelegate = memberViewDelegate else {
            owsFailDebug("Missing memberViewDelegate.")
            return .unknownError
        }
        return Self.databaseStorage.read { transaction -> RecipientPickerRecipientState in
            if memberViewDelegate.memberViewIsPreExistingMember(
                recipient,
                transaction: transaction
            ) {
                return .duplicateGroupMember
            }
            return .canBeSelected
        }
    }

    public func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        didSelectRecipient recipient: PickedRecipient
    ) {
        guard let address = recipient.address else {
            owsFailDebug("Missing address.")
            return
        }
        guard address.isValid else {
            owsFailDebug("Invalid address.")
            return
        }
        guard let memberViewDelegate = memberViewDelegate else {
            owsFailDebug("Missing memberViewDelegate.")
            return
        }

        let (isPreExistingMember, isBlocked) = databaseStorage.read { readTx -> (Bool, Bool) in
            let isPreexisting = memberViewDelegate.memberViewIsPreExistingMember(
                recipient,
                transaction: readTx)
            let isBlocked = blockingManager.isAddressBlocked(address, transaction: readTx)

            return (isPreexisting, isBlocked)
        }

        guard !isPreExistingMember else {
            owsFailDebug("Can't re-add pre-existing member.")
            return
        }
        guard let navigationController = navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }

        let isCurrentMember = recipientSet.contains(recipient)
        let addRecipientCompletion = { [weak self] in
            guard let self = self else {
                return
            }
            self.addRecipient(recipient)
            navigationController.popToViewController(self, animated: true)
        }

        if isCurrentMember {
            removeRecipient(recipient)
        } else if isBlocked && !memberViewDelegate.memberViewShouldAllowBlockedSelection() {
            BlockListUIUtils.showUnblockAddressActionSheet(address,
                                                           from: self) { isStillBlocked in
                if !isStillBlocked {
                    addRecipientCompletion()
                }
            }
        } else {
            let confirmationText = OWSLocalizedString("SAFETY_NUMBER_CHANGED_CONFIRM_ADD_MEMBER_ACTION",
                                                      comment: "button title to confirm adding a recipient when their safety number has recently changed")
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

    public func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        prepareToSelectRecipient recipient: PickedRecipient
    ) -> AnyPromise {

        guard let memberViewDelegate = memberViewDelegate else {
            owsFailDebug("Missing delegate.")
            return AnyPromise(Promise.value(()))
        }

        return memberViewDelegate.memberViewPrepareToSelectRecipient(recipient)
    }

    public func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryMessageForRecipient recipient: PickedRecipient,
        transaction: SDSAnyReadTransaction
    ) -> String? { nil }

    public func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryViewForRecipient recipient: PickedRecipient,
        transaction: SDSAnyReadTransaction
    ) -> ContactCellAccessoryView? {
        guard let address = recipient.address else {
            owsFailDebug("Missing address.")
            return nil
        }
        guard address.isValid else {
            owsFailDebug("Invalid address.")
            return nil
        }
        guard let memberViewDelegate = memberViewDelegate else {
            owsFailDebug("Missing memberViewDelegate.")
            return nil
        }

        let isCurrentMember = recipientSet.contains(recipient)
        let isPreExistingMember = memberViewDelegate.memberViewIsPreExistingMember(recipient,
                                                                                   transaction: transaction)

        let pickedIconName = memberViewDelegate.memberViewCustomIconNameForPickedMember(recipient) ?? "check-circle-solid-new-24"
        let pickedIconColor = memberViewDelegate.memberViewCustomIconColorForPickedMember(recipient) ?? Theme.accentBlueColor

        let imageView = CVImageView()
        if isPreExistingMember {
            imageView.setTemplateImageName(pickedIconName, tintColor: Theme.washColor)
        } else if isCurrentMember {
            imageView.setTemplateImageName(pickedIconName, tintColor: pickedIconColor)
        } else {
            imageView.setTemplateImageName("empty-circle-outline-24", tintColor: .ows_gray25)
        }
        return ContactCellAccessoryView(accessoryView: imageView, size: .square(24))
    }

    public func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        attributedSubtitleForRecipient recipient: PickedRecipient,
        transaction: SDSAnyReadTransaction
    ) -> NSAttributedString? {
        guard let address = recipient.address else {
            owsFailDebug("Recipient missing address.")
            return nil
        }
        guard !address.isLocalAddress else {
            return nil
        }
        guard let bioForDisplay = Self.profileManagerImpl.profileBioForDisplay(for: address,
                                                                               transaction: transaction) else {
            return nil
        }
        return NSAttributedString(string: bioForDisplay)
    }

    public func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController) {}

    public func recipientPickerNewGroupButtonWasPressed() {}

    public func recipientPickerCustomHeaderViews() -> [UIView] {
        return [memberBar, memberCountWrapper]
    }
}

// MARK: -

extension BaseMemberViewController {

    public var shouldCancelNavigationBack: Bool {
        let hasUnsavedChanges = self.hasUnsavedChanges
        if hasUnsavedChanges {
            backButtonPressed()
        }
        return hasUnsavedChanges
    }
}

// MARK: -

extension BaseMemberViewController: NewMembersBarDelegate {
}
