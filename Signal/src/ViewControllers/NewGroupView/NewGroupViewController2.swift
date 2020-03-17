//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// TODO: Rename to NewGroupViewController; remove old view.
@objc
public class NewGroupViewController2: OWSViewController {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private var messageSender: MessageSender {
        return SSKEnvironment.shared.messageSender
    }

    private var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    // MARK: -

    private var groupSeed = NewGroupSeed()

    private let recipientPicker = RecipientPickerViewController()

    private var recipientSet = Set<PickedRecipient>()

    private var hasUnsavedChanges: Bool {
        return !recipientSet.isEmpty
    }

    private let searchBar = NewGroupSearchBar()

    private var searchBarHeightConstraint: NSLayoutConstraint?

    public required init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable, message:"use other constructor instead.")
    @objc
    public required init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    private func generateNewSeed() {
        groupSeed = NewGroupSeed()
    }

    // MARK: - View Lifecycle

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        title = MessageStrings.newGroupDefaultTitle

        view.backgroundColor = Theme.backgroundColor

        let rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("NEW_GROUP_CREATE_BUTTON",
                                                                          comment: "The title for the 'create group' button."),
                                                 style: .plain,
                                                 target: self,
                                                 action: #selector(createNewGroup),
                                                 accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "create"))
        rightBarButtonItem.imageInsets = UIEdgeInsets(top: 0, left: -1, bottom: 0, right: 10)
        rightBarButtonItem.accessibilityLabel
            = NSLocalizedString("FINISH_GROUP_CREATION_LABEL", comment: "Accessibility label for finishing new group")
        navigationItem.rightBarButtonItem = rightBarButtonItem

        // First section.

        searchBar.delegate = self
        let firstSection = searchBar
        view.addSubview(firstSection)
        firstSection.autoPinWidthToSuperview()
        firstSection.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        searchBarHeightConstraint = firstSection.autoSetDimension(.height, toSize: 0)

        recipientPicker.allowsSelectingUnregisteredPhoneNumbers = false
        recipientPicker.shouldShowGroups = false
        recipientPicker.allowsSelectingUnregisteredPhoneNumbers = false
        recipientPicker.shouldShowSearchBar = false
        recipientPicker.delegate = self
        addChild(recipientPicker)
        view.addSubview(recipientPicker.view)

        recipientPicker.view.autoPinEdge(toSuperviewSafeArea: .leading)
        recipientPicker.view.autoPinEdge(toSuperviewSafeArea: .trailing)
        recipientPicker.view.autoPinEdge(.top, to: .bottom, of: firstSection)
        recipientPicker.view.autoPinEdge(toSuperviewEdge: .bottom)
    }

    @objc
    public override func viewWillLayoutSubviews() {
        updateSearchBarHeightConstraint()

        super.viewWillLayoutSubviews()
    }

    private func updateSearchBarHeightConstraint() {
        guard let searchBarHeightConstraint = searchBarHeightConstraint else {
            owsFailDebug("Missing searchBarHeightConstraint.")
            return
        }
        let searchBarHeight = searchBar.contentHeight(forWidth: view.width)
        searchBarHeightConstraint.constant = searchBarHeight
    }

    public func removeRecipient(_ recipient: PickedRecipient) {
        recipientSet.remove(recipient)
        recipientPicker.pickedRecipients = Array(recipientSet)
        updateSearchBar()
    }

    public func addRecipient(_ recipient: PickedRecipient) {
        recipientSet.insert(recipient)
        recipientPicker.pickedRecipients = Array(recipientSet)
        updateSearchBar()
    }

    private func updateSearchBar() {
        searchBar.acceptAutocorrectSuggestion()

        let members = databaseStorage.uiRead { transaction in
            Array(self.recipientSet).compactMap { (recipient: PickedRecipient) -> NewGroupMember? in
                guard let address = recipient.address else {
                    owsFailDebug("Invalid recipient.")
                    return nil
                }
                let displayName = self.contactsManager.displayName(for: address, transaction: transaction)
                return NewGroupMember(recipient: recipient, address: address, displayName: displayName)
            }
        }
        searchBar.members = members
        updateSearchBarHeightConstraint()
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
            dismiss(animated: true)
            return
        }

        OWSActionSheets.showPendingChangesActionSheet { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    private var hasAppeared = false

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !hasAppeared {
            _ = searchBar.becomeFirstResponder()
            hasAppeared = true
        }
    }

    // MARK: - Actions

    @objc
    func createNewGroup() {
        AssertIsOnMainThread()

        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("missing local address")
            return
        }

        let memberSet = Set([localAddress] + Array(recipientSet.compactMap { $0.address }))

        let groupName: String? = nil
        let avatarImage: UIImage? = nil
        createGroupThread(name: groupName,
                          avatarImage: avatarImage,
                          members: Array(memberSet),
                          newGroupSeed: groupSeed)
    }

    // MARK: - Event Handling

    private func backButtonPressed() {

        guard let navigationController = navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }

        if !hasUnsavedChanges {
            // If user made no changes, return to 'compose' view.
            navigationController.popViewController(animated: true)
            return
        }

        OWSActionSheets.showPendingChangesActionSheet { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    // MARK: -

    private func createGroupThread(name: String?,
                                   avatarImage: UIImage?,
                                   members: [SignalServiceAddress],
                                   newGroupSeed: NewGroupSeed) {

        // GroupsV2 TODO: Should we allow cancel here?
        ModalActivityIndicatorViewController.present(fromViewController: self,
                                                     canCancel: false) { modalActivityIndicator in
                                                        firstly {
                                                            GroupManager.localCreateNewGroup(members: members,
                                                                                             groupId: nil,
                                                                                             name: name,
                                                                                             avatarImage: avatarImage,
                                                                                             newGroupSeed: newGroupSeed,
                                                                                             shouldSendMessage: true)
                                                        }.done { groupThread in
                                                            SignalApp.shared().presentConversation(for: groupThread,
                                                                                                   action: .compose,
                                                                                                   animated: false)
                                                            self.presentingViewController?.dismiss(animated: true)
                                                        }.catch { error in
                                                            owsFailDebug("Could not create group: \(error)")

                                                            modalActivityIndicator.dismiss {
                                                                // Partial success could create the group on the service.
                                                                // This would cause retries to fail with 409.  Therefore
                                                                // we must rotate the seed after every failure.
                                                                self.generateNewSeed()

                                                                NewGroupViewController.showCreateErrorUI(error: error)
                                                            }
                                                        }.retainUntilComplete()
        }
    }

    public class func showCreateErrorUI(error: Error) {
        AssertIsOnMainThread()

        if error.isNetworkFailureOrTimeout {
            OWSActionSheets.showActionSheet(title: NSLocalizedString("NEW_GROUP_CREATION_FAILED_DUE_TO_NETWORK",
                                                                     comment: "Error indicating that a new group could not be created due to network connectivity problems."))
            return
        }

        OWSActionSheets.showActionSheet(title: NSLocalizedString("NEW_GROUP_CREATION_FAILED",
                                                                 comment: "Error indicating that a new group could not be created."))
    }
}

// MARK: -

extension NewGroupViewController2: RecipientPickerDelegate {

    func recipientPicker(_ recipientPickerViewController: RecipientPickerViewController,
                         canSelectRecipient recipient: PickedRecipient) -> Bool {
        return true
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

        let isCurrentMember = recipientSet.contains(recipient)
        let isBlocked = self.recipientPicker.contactsViewHelper.isSignalServiceAddressBlocked(address)

        let imageView = UIImageView()
        if isCurrentMember {
            imageView.setTemplateImageName("check-circle-solid-24", tintColor: .ows_signalBlue)
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
}

// MARK: -

extension NewGroupViewController2: OWSNavigationView {

    public func shouldCancelNavigationBack() -> Bool {
        let hasUnsavedChanges = self.hasUnsavedChanges
        if hasUnsavedChanges {
            backButtonPressed()
        }
        return hasUnsavedChanges
    }
}

// MARK: -

extension NewGroupViewController2: NewGroupSearchBarDelegate {
    public func searchBarTextDidChange() {
        recipientPicker.customSearchQuery = searchBar.searchText
        updateSearchBarHeightConstraint()
    }
}
