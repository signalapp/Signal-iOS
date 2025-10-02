//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

// I don't like how I implemented this, but passing a delegate all the way here
// and to every BaseMemberViewController subclass with a method to open the QR
// code scanner would be unreasonable, so instead there's this protocol, which
// BaseMemberViewController is extended to conform to in the main Signal target.
public protocol MemberViewUsernameQRCodeScannerPresenter {
    func presentUsernameQRCodeScannerFromMemberView()
}

public protocol MemberViewDelegate: AnyObject {
    var memberViewRecipientSet: OrderedSet<PickedRecipient> { get }

    var memberViewHasUnsavedChanges: Bool { get }

    func memberViewRemoveRecipient(_ recipient: PickedRecipient)

    func memberViewAddRecipient(_ recipient: PickedRecipient) -> Bool

    func memberViewShouldShowMemberCount() -> Bool

    func memberViewShouldAllowBlockedSelection() -> Bool

    func memberViewMemberCountForDisplay() -> Int

    func memberViewIsPreExistingMember(_ recipient: PickedRecipient,
                                       transaction: DBReadTransaction) -> Bool

    func memberViewCustomIconNameForPickedMember(_ recipient: PickedRecipient) -> String?

    func memberViewCustomIconColorForPickedMember(_ recipient: PickedRecipient) -> UIColor?

    func memberViewDismiss()
}

// MARK: -

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

    open override func viewDidLoad() {
        super.viewDidLoad()

        // First section.

        memberBar.delegate = self

        // Don't use dynamic type in this label.
        memberCountLabel.font = UIFont.regularFont(ofSize: 12)
        memberCountLabel.textColor = Theme.isDarkThemeEnabled ? .ows_gray05 : .ows_gray60
        memberCountLabel.textAlignment = CurrentAppContext().isRTL ? .left : .right

        memberCountWrapper.addSubview(memberCountLabel)
        memberCountLabel.autoPinEdgesToSuperviewMargins()
        memberCountWrapper.layoutMargins = UIEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)

        recipientPicker.groupsToShow = .noGroups
        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)

        recipientPicker.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            recipientPicker.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            recipientPicker.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            recipientPicker.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            recipientPicker.view.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
        ])

        updateMemberCount()
    }

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
        if memberCount >= RemoteConfig.current.maxGroupSizeRecommended {
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

        guard memberViewDelegate.memberViewAddRecipient(recipient) else { return }
        recipientPicker.pickedRecipients = recipientSet.orderedMembers
        recipientPicker.clearSearchText()
        updateMemberBar()
        updateMemberCount()

        memberBar.scrollToRecipient(recipient)
    }

    private func updateMemberBar() {
        memberBar.setMembers(SSKEnvironment.shared.databaseStorageRef.read { tx in
            let members = self.recipientSet.orderedMembers.compactMap { (pickedRecipient) -> (PickedRecipient, SignalServiceAddress)? in
                guard let address = pickedRecipient.address else {
                    return nil
                }
                return (pickedRecipient, address)
            }
            let displayNames = SSKEnvironment.shared.contactManagerRef.displayNames(for: members.map { (_, address) in address }, tx: tx)
            return zip(members, displayNames).map { (member, displayName) in
                return NewMember(
                    recipient: member.0,
                    address: member.1,
                    shortName: displayName.resolvedValue(useShortNameIfAvailable: true)
                )
            }
        })
    }

    public class func sortedMemberAddresses(
        recipientSet: OrderedSet<PickedRecipient>,
        tx: DBReadTransaction
    ) -> [SignalServiceAddress] {
        return SSKEnvironment.shared.contactManagerRef.sortSignalServiceAddresses(
            recipientSet.orderedMembers.compactMap { $0.address },
            transaction: tx
        )
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
            navigationItem.leftBarButtonItem = .doneButton { [weak self] in
                self?.dismissPressed()
            }
        }
    }

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
        selectionStyleForRecipient recipient: PickedRecipient,
        transaction: DBReadTransaction
    ) -> UITableViewCell.SelectionStyle {
        guard let memberViewDelegate = memberViewDelegate else {
            owsFailDebug("Missing memberViewDelegate.")
            return .default
        }
        guard memberViewDelegate.memberViewIsPreExistingMember(recipient, transaction: transaction) else {
            return .default
        }
        return .none
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

        let (isPreExistingMember, isBlocked) = SSKEnvironment.shared.databaseStorageRef.read { tx -> (Bool, Bool) in
            let isPreexisting = memberViewDelegate.memberViewIsPreExistingMember(
                recipient,
                transaction: tx)
            let isBlocked = SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(address, transaction: tx)
            return (isPreexisting, isBlocked)
        }

        guard !isPreExistingMember else {
            let errorMessage = OWSLocalizedString(
                "GROUPS_ERROR_MEMBER_ALREADY_IN_GROUP",
                comment: "Error message indicating that a member can't be added to a group because they are already in the group."
            )
            OWSActionSheets.showErrorAlert(message: errorMessage)
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
            confirmSafetyNumber(for: address, untrustedThreshold: nil, thenAddRecipient: addRecipientCompletion)
        }
    }

    private func confirmSafetyNumber(
        for address: SignalServiceAddress,
        untrustedThreshold: Date?,
        thenAddRecipient addRecipient: @escaping () -> Void
    ) {
        let confirmationText = OWSLocalizedString(
            "SAFETY_NUMBER_CHANGED_CONFIRM_ADD_MEMBER_ACTION",
            comment: "button title to confirm adding a recipient when their safety number has recently changed"
        )
        let newUntrustedThreshold = Date()
        let didShowSNAlert = SafetyNumberConfirmationSheet.presentIfNecessary(
            addresses: [address],
            confirmationText: confirmationText,
            untrustedThreshold: untrustedThreshold
        ) { [weak self] didConfirmIdentity in
            guard didConfirmIdentity else { return }
            self?.confirmSafetyNumber(for: address, untrustedThreshold: newUntrustedThreshold, thenAddRecipient: addRecipient)
        }

        if didShowSNAlert {
            return
        }

        addRecipient()
    }

    public func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        accessoryViewForRecipient recipient: PickedRecipient,
        transaction: DBReadTransaction
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

        let pickedIconName = memberViewDelegate.memberViewCustomIconNameForPickedMember(recipient) ?? Theme.iconName(.checkCircleFill)
        let pickedIconColor = memberViewDelegate.memberViewCustomIconColorForPickedMember(recipient) ?? Theme.accentBlueColor

        let imageView = CVImageView()
        if isPreExistingMember {
            imageView.setTemplateImageName(pickedIconName, tintColor: Theme.washColor)
        } else if isCurrentMember {
            imageView.setTemplateImageName(pickedIconName, tintColor: pickedIconColor)
        } else {
            imageView.setTemplateImageName(Theme.iconName(.circle), tintColor: .ows_gray25)
        }
        return ContactCellAccessoryView(accessoryView: imageView, size: .square(24))
    }

    public func recipientPicker(
        _ recipientPickerViewController: RecipientPickerViewController,
        attributedSubtitleForRecipient recipient: PickedRecipient,
        transaction: DBReadTransaction
    ) -> NSAttributedString? {
        guard let address = recipient.address else {
            owsFailDebug("Recipient missing address.")
            return nil
        }
        guard !address.isLocalAddress else {
            return nil
        }
        guard let bioForDisplay = SSKEnvironment.shared.profileManagerRef.userProfile(for: address, tx: transaction)?.bioForDisplay else {
            return nil
        }
        return NSAttributedString(string: bioForDisplay)
    }

    public func recipientPickerCustomHeaderViews() -> [UIView] {
        return [memberBar, memberCountWrapper]
    }

    public var shouldShowQRCodeButton: Bool {
        // The QR code scanner is in the main app target, which itself adds
        // MemberViewUsernameQRCodeScannerPresenter conformance to
        // BaseMemberViewController, but opening this view from the share
        // extension does not show the QR code scanner button.
        self is MemberViewUsernameQRCodeScannerPresenter
    }

    public func openUsernameQRCodeScanner() {
        guard let presenter = self as? MemberViewUsernameQRCodeScannerPresenter else { return }
        presenter.presentUsernameQRCodeScannerFromMemberView()
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
