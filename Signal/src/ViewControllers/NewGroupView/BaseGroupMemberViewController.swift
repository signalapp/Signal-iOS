//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SafariServices
import PromiseKit

protocol GroupMemberViewDelegate: class {
    var groupMemberViewRecipientSet: OrderedSet<PickedRecipient> { get }

    var groupMemberViewHasUnsavedChanges: Bool { get }

    func groupMemberViewRemoveRecipient(_ recipient: PickedRecipient)

    func groupMemberViewAddRecipient(_ recipient: PickedRecipient)

    func groupMemberViewCanAddRecipient(_ recipient: PickedRecipient) -> Bool

    func groupMemberViewGroupMemberCount() -> Int

    func groupMemberViewIsGroupFull() -> Bool

    func groupMemberViewIsPreExistingMember(_ recipient: PickedRecipient) -> Bool

    func groupMemberViewIsGroupsV2Required() -> Bool

    func groupMemberViewDismiss()
}

// MARK: -

// A base class used in two scenarios:
//
// * Picking members for a new group.
// * Add new members to an existing group.
@objc
public class BaseGroupMemberViewController: OWSViewController {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private class var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    // MARK: -

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

    private let searchBar = OWSSearchBar()
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

        searchBar.delegate = self
        memberBar.delegate = self

        // Don't use dynamic type in this label.
        memberCountLabel.font = UIFont.ows_dynamicTypeBody2.withSize(12)
        memberCountLabel.textColor = Theme.secondaryTextAndIconColor
        memberCountLabel.textAlignment = CurrentAppContext().isRTL ? .left : .right

        memberCountWrapper.addSubview(memberCountLabel)
        memberCountLabel.autoPinEdgesToSuperviewMargins()
        memberCountWrapper.layoutMargins = UIEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)

        let firstSection = UIStackView(arrangedSubviews: [searchBar, memberBar, memberCountWrapper])
        firstSection.axis = .vertical
        firstSection.alignment = .fill
        view.addSubview(firstSection)
        firstSection.autoPinWidthToSuperview()
        firstSection.autoPin(toTopLayoutGuideOf: self, withInset: 0)

        recipientPicker.allowsSelectingUnregisteredPhoneNumbers = false
        recipientPicker.shouldShowGroups = false
        recipientPicker.allowsSelectingUnregisteredPhoneNumbers = false
        recipientPicker.shouldShowSearchBar = false
        recipientPicker.showUseAsyncSelection = true
        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)

        recipientPicker.view.autoPinEdge(toSuperviewSafeArea: .leading)
        recipientPicker.view.autoPinEdge(toSuperviewSafeArea: .trailing)
        recipientPicker.view.autoPinEdge(.top, to: .bottom, of: firstSection)
        autoPinView(toBottomOfViewControllerOrKeyboard: recipientPicker.view, avoidNotch: false)

        updateMemberCount()
        tryToFillInMissingUuuids()
    }

    private func tryToFillInMissingUuuids() {
        let addresses = recipientPicker.contactsViewHelper.signalAccounts.map { $0.recipientAddress }
        firstly {
            GroupManager.tryToFillInMissingUuuids(for: addresses, isBlocking: false)
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }.retainUntilComplete()
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
        memberCountWrapper.isHidden = false
        let format = NSLocalizedString("GROUP_MEMBER_COUNT_FORMAT",
                                       comment: "Format string for the group member count indicator. Embeds {{ %1$@ the number of members in the group, %2$@ the maximum number of members in the group. }}.")
        let memberCount = groupMemberViewDelegate?.groupMemberViewGroupMemberCount() ?? 0

        memberCountLabel.text = String(format: format,
                                       OWSFormat.formatInt(memberCount),
                                       OWSFormat.formatUInt(GroupManager.maxGroupMemberCount))
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
            showInvalidGroupMemberAlert(recipient: recipient)
            return
        }
        guard !groupMemberViewDelegate.groupMemberViewIsGroupFull() else {
            showGroupFullAlert()
            return
        }

        groupMemberViewDelegate.groupMemberViewAddRecipient(recipient)
        recipientPicker.pickedRecipients = recipientSet.orderedMembers
        updateMemberBar()
        updateMemberCount()

        memberBar.scrollToRecipient(recipient)
    }

    private func updateMemberBar() {
        memberBar.setMembers(databaseStorage.uiRead { transaction in
            self.orderedMembers(transaction: transaction)
        })
    }

    private func orderedMembers(transaction: SDSAnyReadTransaction) -> [NewGroupMember] {
        return Self.orderedMembers(recipientSet: recipientSet, transaction: transaction)
    }

    class func orderedMembers(recipientSet: OrderedSet<PickedRecipient>,
                              transaction: SDSAnyReadTransaction) -> [NewGroupMember] {
        var members = recipientSet.orderedMembers.compactMap { (recipient: PickedRecipient) -> NewGroupMember? in
            guard let address = recipient.address else {
                owsFailDebug("Invalid recipient.")
                return nil
            }
            let displayName = self.contactsManager.displayName(for: address, transaction: transaction)
            let comparableName = self.contactsManager.comparableName(for: address, transaction: transaction)
            let conversationColorName = ConversationColorName(rawValue: self.contactsManager.conversationColorName(for: address,
                                                                                                                   transaction: transaction))
            var shortName = displayName
            if  !Locale.current.isCJKV,
                let nameComponents = self.contactsManager.nameComponents(for: address, transaction: transaction),
                let givenName = nameComponents.givenName?.filterForDisplay,
                !givenName.isEmpty {
                shortName = givenName
            }
            return NewGroupMember(recipient: recipient,
                                  address: address,
                                  displayName: displayName,
                                  shortName: shortName,
                                  comparableName: comparableName,
                                  conversationColorName: conversationColorName)
        }
        members.sort { (left, right) in
            return left.comparableName < right.comparableName
        }
        return members
    }

    private func showInvalidGroupMemberAlert(recipient: PickedRecipient) {
        let actionSheet = ActionSheetController(title: CommonStrings.errorAlertTitle,
                                                message: NSLocalizedString("EDIT_GROUP_ERROR_CANNOT_ADD_MEMBER",
                                                                           comment: "Error message indicating the a user can't be added to a group."))

        actionSheet.addAction(ActionSheetAction(title: CommonStrings.learnMore,
                                                style: .default) { _ in
                                                    self.showCantAddMemberView()
        })
        actionSheet.addAction(ActionSheetAction(title: CommonStrings.okayButton,
                                                style: .default))
        presentActionSheet(actionSheet)
    }

    private func showGroupFullAlert() {
        OWSActionSheets.showErrorAlert(message: NSLocalizedString("EDIT_GROUP_ERROR_CANNOT_ADD_MEMBER_GROUP_FULL",
                                                                  comment: "Message for 'group full' error alert when a user can't be added to a group."))
    }

    private func showCantAddMemberView() {
        guard let url = URL(string: "https://support.signal.org/hc/articles/360007319331") else {
            owsFailDebug("Invalid url.")
            return
        }
        let vc = SFSafariViewController(url: url)
        present(vc, animated: true, completion: nil)
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
                         canSelectRecipient recipient: PickedRecipient) -> Bool {
        guard let groupMemberViewDelegate = groupMemberViewDelegate else {
            owsFailDebug("Missing groupMemberViewDelegate.")
            return false
        }

        return !groupMemberViewDelegate.groupMemberViewIsPreExistingMember(recipient)
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
        let isBlocked = self.recipientPicker.contactsViewHelper.isSignalServiceAddressBlocked(address)

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
            let didShowSNAlert = SafetyNumberConfirmationAlert.presentAlertIfNecessary(address: address,
                                                                                       confirmationText: confirmationText) { didConfirmIdentity in
                                                                                        if didConfirmIdentity {
                                                                                            addRecipientCompletion()
                                                                                        }
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
        guard RemoteConfig.groupsV2CreateGroups ||
            RemoteConfig.groupsV2IncomingMessages else {
                return
        }
        DispatchQueue.global().async {
            if !self.doesRecipientSupportGroupsV2(recipient) {
                self.tryToEnableGroupsV2ForAddress(address,
                                                   isBlocking: false,
                                                   ignoreErrors: true).retainUntilComplete()
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
        guard RemoteConfig.groupsV2CreateGroups ||
            RemoteConfig.groupsV2IncomingMessages else {
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
        showInvalidGroupMemberAlert(recipient: recipient)
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
        let isBlocked = self.recipientPicker.contactsViewHelper.isSignalServiceAddressBlocked(address)

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
        let isBlocked = self.recipientPicker.contactsViewHelper.isSignalServiceAddressBlocked(address)
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

    func recipientPickerTableViewWillBeginDragging(_ recipientPickerViewController: RecipientPickerViewController) {
        _ = searchBar.resignFirstResponder()
    }

    func recipientPickerNewGroupButtonWasPressed() {}
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

// MARK: -

extension BaseGroupMemberViewController: UISearchBarDelegate {
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        recipientPicker.customSearchQuery = searchText
    }

    public func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
    }

    public func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
    }

    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = nil
        searchBar.resignFirstResponder()
    }
}
