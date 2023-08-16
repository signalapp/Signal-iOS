//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MessageUI
import SignalMessaging
import SignalServiceKit

public class RecipientPickerViewController: OWSViewController, OWSNavigationChildController {

    public enum SelectionMode {
        case `default`

        // The .blocklist selection mode changes the behavior in a few ways:
        //
        // - If numbers aren't registered, allow them to be chosen. You may want to
        //   block someone even if they aren't registered.
        //
        // - If numbers aren't registered, don't offer to invite them to Signal. If
        //   you want to block someone, you probably don't want to invite them.
        case blocklist
    }

    public enum GroupsToShow {
        case noGroups
        case groupsThatUserIsMemberOfWhenSearching
        case allGroupsWhenSearching
    }

    public weak var delegate: RecipientPickerDelegate?

    // MARK: Configuration

    public var allowsAddByPhoneNumber = true
    public var shouldHideLocalRecipient = true
    public var selectionMode = SelectionMode.default
    public var groupsToShow = GroupsToShow.groupsThatUserIsMemberOfWhenSearching
    public var shouldShowInvites = false
    public var shouldShowAlphabetSlider = true
    public var shouldShowNewGroup = false
    public var shouldUseAsyncSelection = false
    public var findByPhoneNumberButtonTitle: String?

    // MARK: Picker

    public var pickedRecipients: [PickedRecipient] = [] {
        didSet {
            updateTableContents()
        }
    }

    // MARK: UIViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("MESSAGE_COMPOSEVIEW_TITLE", comment: "")

        contactsViewHelper.addObserver(self)

        // Stack View
        signalContactsStackView.isHidden = isNoContactsModeActive
        view.addSubview(signalContactsStackView)
        signalContactsStackView.autoPinEdgesToSuperviewEdges()

        // Search Bar
        signalContactsStackView.addArrangedSubview(searchBar)

        // Custom Header Views
        if let customHeaderViews = delegate?.recipientPickerCustomHeaderViews() {
            customHeaderViews.forEach { signalContactsStackView.addArrangedSubview($0) }
        }

        // Table View
        addChild(tableViewController)
        signalContactsStackView.addArrangedSubview(tableViewController.view)

        // "No Signal Contacts"
        noSignalContactsView.isHidden = !isNoContactsModeActive
        view.addSubview(noSignalContactsView)
        noSignalContactsView.autoPinWidthToSuperview()
        noSignalContactsView.autoPinEdge(toSuperviewEdge: .top)
        noSignalContactsView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)

        // Pull to Refresh
        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = .gray
        refreshControl.accessibilityIdentifier = "RecipientPickerViewController.pullToRefreshView"
        refreshControl.addTarget(self, action: #selector(pullToRefreshPerformed), for: .valueChanged)
        tableView.refreshControl = refreshControl

        updateTableContents()

        applyTheme()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // Make sure we have requested contact access at this point if, e.g.
        // the user has no messages in their inbox and they choose to compose
        // a message.
        contactsManagerImpl.requestSystemContactsOnce()

        showContactAppropriateViews()
    }

    public override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateSearchBarMargins()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateSearchBarMargins()
    }

    public override func themeDidChange() {
        super.themeDidChange()
        applyTheme()
    }

    public var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }

    public var navbarBackgroundColorOverride: UIColor? { tableViewController.tableBackgroundColor }

    // MARK: Search

    private static let minimumSearchLength = 1

    private var searchText: String { searchBar.text?.stripped ?? "" }

    private var lastSearchText: String?

    private var _searchResults = Atomic<ComposeScreenSearchResultSet?>(wrappedValue: nil)

    private var searchResults: ComposeScreenSearchResultSet? {
        get { _searchResults.wrappedValue }
        set {
            if let newValue {
                if searchText != newValue.searchText {
                    Logger.verbose("user has changed text since search started. Skipping stale results.")
                    return
                }
            } else {
                if searchText.count >= Self.minimumSearchLength {
                    Logger.verbose("user has entered text since clearing results. Skipping stale results.")
                    return
                }
            }
            guard _searchResults.wrappedValue != newValue else { return }

            _searchResults.wrappedValue = newValue
            Logger.verbose("showing search results for term: \(String(describing: newValue?.searchText))")
            updateTableContents()
        }
    }

    private func searchTextDidChange() {
        let searchText = self.searchText

        guard searchText.count >= Self.minimumSearchLength else {
            searchResults = nil
            lastSearchText = nil
            return
        }

        guard lastSearchText != searchText else { return }

        lastSearchText = searchText

        var searchResults: ComposeScreenSearchResultSet?
        databaseStorage.asyncRead(
            block: { transaction in
                searchResults = self.fullTextSearcher.searchForComposeScreen(
                    searchText: searchText,
                    omitLocalUser: self.shouldHideLocalRecipient,
                    transaction: transaction
                )
            },
            completion: { [weak self] in
                guard let self else { return }
                guard self.lastSearchText == searchText else {
                    // Discard obsolete search results.
                    return
                }
                self.searchResults = searchResults
                BenchManager.completeEvent(eventId: "Compose Search - \(searchResults?.searchText ?? "")")
            }
        )
    }

    private func updateSearchBarMargins() {
        // This should ideally compute the insets for self.tableView, but that
        // view's size hasn't been updated when the viewDidLayoutSubviews method is
        // called. As a quick fix, use self.view's size, which matches the eventual
        // width of self.tableView. (A more complete fix would likely add a
        // callback when self.tableView’s size is available.)
        searchBar.layoutMargins = OWSTableViewController2.cellOuterInsets(in: view)
    }

    internal func clearSearchText() {
        searchBar.text = ""
        searchTextDidChange()
    }

    // MARK: UI

    private var inviteFlow: InviteFlow?

    private var isNoContactsModeActive = false {
        didSet {
            guard oldValue != isNoContactsModeActive else { return }

            signalContactsStackView.isHidden = isNoContactsModeActive
            noSignalContactsView.isHidden = !isNoContactsModeActive

            updateTableContents()
        }
    }

    private let collation = UILocalizedIndexedCollation.current()

    private lazy var signalContactsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .fill
        return stackView
    }()

    private lazy var searchBar: OWSSearchBar = {
        let searchBar = OWSSearchBar()
        searchBar.delegate = self
        if FeatureFlags.usernames {
            searchBar.placeholder = OWSLocalizedString(
                "SEARCH_BY_NAME_OR_USERNAME_OR_NUMBER_PLACEHOLDER_TEXT",
                comment: "Placeholder text indicating the user can search for contacts by name, username, or phone number."
            )
        } else {
            searchBar.placeholder = OWSLocalizedString(
                "SEARCH_BYNAMEORNUMBER_PLACEHOLDER_TEXT",
                comment: "Placeholder text indicating the user can search for contacts by name or phone number."
            )
        }
        searchBar.accessibilityIdentifier = "RecipientPickerViewController.searchBar"
        searchBar.textField?.accessibilityIdentifier = "RecipientPickerViewController.contact_search"
        searchBar.sizeToFit()
        searchBar.setCompressionResistanceVerticalHigh()
        searchBar.setContentHuggingVerticalHigh()
        return searchBar
    }()

    private lazy var tableViewController: OWSTableViewController2 = {
        let viewController = OWSTableViewController2()
        viewController.delegate = self
        viewController.defaultSeparatorInsetLeading = OWSTableViewController2.cellHInnerMargin
            + CGFloat(AvatarBuilder.smallAvatarSizePoints) + ContactCellView.avatarTextHSpacing
        viewController.tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)
        viewController.tableView.register(NonContactTableViewCell.self, forCellReuseIdentifier: NonContactTableViewCell.reuseIdentifier)
        viewController.view.setCompressionResistanceVerticalHigh()
        viewController.view.setContentHuggingVerticalHigh()
        return viewController
    }()

    private lazy var noSignalContactsView = createNoSignalContactsView()

    private var tableView: UITableView { tableViewController.tableView }

    private func applyTheme() {
        tableViewController.applyTheme(to: self)
        searchBar.searchFieldBackgroundColorOverride = Theme.searchFieldElevatedBackgroundColor
        tableViewController.tableView.sectionIndexColor = Theme.primaryTextColor
        if let owsNavigationController = navigationController as? OWSNavigationController {
            owsNavigationController.updateNavbarAppearance()
        }
    }

    public func applyTheme(to viewController: UIViewController) {
        tableViewController.applyTheme(to: viewController)
    }

    // MARK: Context Menu

    /// This must be retained for as long as we want to be able
    /// to display recipient context menus in this view controller.
    private lazy var recipientContextMenuHelper = {
        return RecipientContextMenuHelper(
            databaseStorage: databaseStorage,
            blockingManager: blockingManager,
            recipientHidingManager: DependenciesBridge.shared.recipientHidingManager,
            accountManager: tsAccountManager,
            contactsManager: contactsManager,
            fromViewController: self
        )
    }()

    // MARK: Table Contents

    public func reloadContent() {
        updateTableContents()
    }

    private func updateTableContents() {
        AssertIsOnMainThread()

        guard !isNoContactsModeActive else {
            tableViewController.contents = OWSTableContents()
            return
        }

        let tableContents = OWSTableContents()

        // App is killed and restarted when the user changes their contact
        // permissions, so no need to "observe" anything to re-render this.
        if let reminderSection = contactAccessReminderSection() {
            tableContents.add(reminderSection)
        }

        let staticSection = OWSTableSection()
        staticSection.separatorInsetLeading = OWSTableViewController2.cellHInnerMargin + 24 + OWSTableItem.iconSpacing

        let isSearching = searchResults != nil

        if shouldShowNewGroup && !isSearching {
            staticSection.add(OWSTableItem.disclosureItem(
                icon: .genericGroup,
                name: OWSLocalizedString(
                    "NEW_GROUP_BUTTON",
                    comment: "Label for the 'create new group' button."
                ),
                accessibilityIdentifier: "RecipientPickerViewController.new_group",
                actionBlock: { [weak self] in
                    self?.newGroupButtonPressed()
                }
            ))
        }

        // Find Non-Contacts by Phone Number
        if allowsAddByPhoneNumber && !isSearching {
            staticSection.add(OWSTableItem.disclosureItem(
                icon: .phoneNumber,
                name: OWSLocalizedString(
                    "NEW_CONVERSATION_FIND_BY_PHONE_NUMBER",
                    comment: "A label the cell that lets you add a new member to a group."
                ),
                accessibilityIdentifier: "RecipientPickerViewController.find_by_phone",
                actionBlock: { [weak self] in
                    guard let self else { return }
                    let viewController = FindByPhoneNumberViewController(
                        delegate: self,
                        buttonText: self.findByPhoneNumberButtonTitle,
                        requiresRegisteredNumber: self.selectionMode != .blocklist
                    )
                    self.navigationController?.pushViewController(viewController, animated: true)
                }
            ))
        }

        // Invite Contacts
        if shouldShowInvites && !isSearching && contactsManagerImpl.sharingAuthorization != .denied {
            staticSection.add(OWSTableItem.disclosureItem(
                icon: .settingsInvite,
                name: OWSLocalizedString(
                    "INVITE_FRIENDS_CONTACT_TABLE_BUTTON",
                    comment: "Label for the cell that presents the 'invite contacts' workflow."
                ),
                accessibilityIdentifier: "RecipientPickerViewController.invite_contacts",
                actionBlock: { [weak self] in
                    self?.presentInviteFlow()
                }
            ))
        }

        if staticSection.itemCount > 0 {
            tableContents.add(staticSection)
        }

        // Render any non-contact picked recipients
        if !pickedRecipients.isEmpty && !isSearching {
            let sectionRecipients = pickedRecipients.filter { recipient in
                guard let recipientAddress = recipient.address else { return false }

                if shouldHideLocalRecipient && recipientAddress == contactsViewHelper.localAddress() {
                    return false
                }
                if contactsViewHelper.fetchSignalAccount(for: recipientAddress) != nil {
                    return false
                }
                return true
            }
            if !sectionRecipients.isEmpty {
                tableContents.add(OWSTableSection(
                    title: OWSLocalizedString(
                        "NEW_GROUP_NON_CONTACTS_SECTION_TITLE",
                        comment: "a title for the selected section of the 'recipient picker' view."
                    ),
                    items: sectionRecipients.map { item(forRecipient: $0) }
                ))
            }
        }

        if let searchResults {
            tableContents.add(sections: contactsSections(for: searchResults))
        } else {
            // Count the non-collated sections, before we add our collated sections.
            // Later we'll need to offset which sections our collation indexes reference
            // by this amount. e.g. otherwise the "B" index will reference names starting with "A"
            // And the "A" index will reference the static non-collated section(s).
            let beforeContactsSectionCount = tableContents.sections.count
            tableContents.add(sections: contactsSection())

            if shouldShowAlphabetSlider {
                tableContents.sectionForSectionIndexTitleBlock = { [weak tableContents, weak self] title, index in
                    guard let self, let tableContents else { return 0 }

                    // Offset the collation section to account for the noncollated sections.
                    let sectionIndex = self.collation.section(forSectionIndexTitle: index) + beforeContactsSectionCount
                    guard sectionIndex >= 0 else {
                        // Sentinel in case we change our section ordering in a surprising way.
                        owsFailDebug("Unexpected negative section index")
                        return 0
                    }
                    guard sectionIndex < tableContents.sections.count else {
                        // Sentinel in case we change our section ordering in a surprising way.
                        owsFailDebug("Unexpectedly large index")
                        return 0
                    }
                    return sectionIndex
                }
                tableContents.sectionIndexTitlesForTableViewBlock = { [weak self] in
                    guard let self else { return [] }
                    return self.collation.sectionTitles
                }
            }
        }

        tableViewController.contents = tableContents
    }

    // MARK: -

    @objc
    private func pullToRefreshPerformed(_ refreshControl: UIRefreshControl) {
        AssertIsOnMainThread()
        Logger.info("Beginning refreshing")

        let refreshPromise: AnyPromise
        if tsAccountManager.isRegisteredPrimaryDevice {
            refreshPromise = contactsManagerImpl.userRequestedSystemContactsRefresh()
        } else {
            refreshPromise = syncManager.sendAllSyncRequestMessages(timeout: 20)
        }
        _ = refreshPromise.ensure {
            Logger.info("ending refreshing")
            refreshControl.endRefreshing()
        }
    }
}

extension RecipientPickerViewController: OWSTableViewControllerDelegate {

    public func tableViewWillBeginDragging(_ tableView: UITableView) {
        searchBar.resignFirstResponder()
        delegate?.recipientPickerTableViewWillBeginDragging(self)
    }
}

extension RecipientPickerViewController: UISearchBarDelegate {

    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        BenchManager.startEvent(title: "Compose Search", eventId: "Compose Search - \(searchText)")
        searchTextDidChange()
    }

    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchTextDidChange()
    }

    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchTextDidChange()
    }

    public func searchBarResultsListButtonClicked(_ searchBar: UISearchBar) {
        searchTextDidChange()
    }

    public func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        searchTextDidChange()
    }
}

extension RecipientPickerViewController: ContactsViewHelperObserver {

    public func contactsViewHelperDidUpdateContacts() {
        updateTableContents()
        showContactAppropriateViews()
    }
}

extension RecipientPickerViewController {

    public func groupSection(for searchResults: ComposeScreenSearchResultSet) -> OWSTableSection? {
        let groupThreads: [TSGroupThread]
        switch groupsToShow {
        case .noGroups:
            return nil
        case .groupsThatUserIsMemberOfWhenSearching:
            groupThreads = searchResults.groupThreads.filter { thread in
                thread.isLocalUserFullMember
            }
        case .allGroupsWhenSearching:
            groupThreads = searchResults.groupThreads
        }

        guard !groupThreads.isEmpty else { return nil }

        return OWSTableSection(
            title: OWSLocalizedString(
                "COMPOSE_MESSAGE_GROUP_SECTION_TITLE",
                comment: "Table section header for group listing when composing a new message"
            ),
            items: groupThreads.map {
                self.item(forRecipient: PickedRecipient.for(groupThread: $0))
            }
        )
    }
}

// MARK: - Selecting Recipients

private extension RecipientPickerViewController {

    private func tryToSelectRecipient(_ recipient: PickedRecipient) {
        if let address = recipient.address, address.isLocalAddress, shouldHideLocalRecipient {
            owsFailDebug("Trying to select recipient that shouldn't be visible")
            return
        }
        if shouldUseAsyncSelection {
            prepareToSelectRecipient(recipient)
        } else {
            didPrepareToSelectRecipient(recipient)
        }
    }

    private func prepareToSelectRecipient(_ recipient: PickedRecipient) {
        guard let delegate = delegate else { return }
        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { modal in
            firstly {
                delegate.recipientPicker(self, prepareToSelectRecipient: recipient)
            }.done(on: DispatchQueue.main) { [weak self] _ in
                modal.dismiss {
                    self?.didPrepareToSelectRecipient(recipient)
                }
            }.catch(on: DispatchQueue.main) { error in
                owsFailDebugUnlessNetworkFailure(error)
                modal.dismiss {
                    OWSActionSheets.showErrorAlert(message: error.userErrorDescription)
                }
            }
        }
    }

    private func didPrepareToSelectRecipient(_ recipient: PickedRecipient) {
        AssertIsOnMainThread()

        guard let delegate = delegate else { return }

        let recipientPickerRecipientState = delegate.recipientPicker(self, getRecipientState: recipient)
        guard recipientPickerRecipientState == .canBeSelected else {
            showErrorAlert(recipientPickerRecipientState: recipientPickerRecipientState)
            return
        }

        delegate.recipientPicker(self, didSelectRecipient: recipient)
    }

    private func showErrorAlert(recipientPickerRecipientState: RecipientPickerRecipientState) {
        let errorMessage: String
        switch recipientPickerRecipientState {
        case .duplicateGroupMember:
            errorMessage = OWSLocalizedString(
                "GROUPS_ERROR_MEMBER_ALREADY_IN_GROUP",
                comment: "Error message indicating that a member can't be added to a group because they are already in the group."
            )
        case .userAlreadyInBlocklist:
            errorMessage = OWSLocalizedString(
                "BLOCK_LIST_ERROR_USER_ALREADY_IN_BLOCKLIST",
                comment: "Error message indicating that a user can't be blocked because they are already blocked."
            )
        case .conversationAlreadyInBlocklist:
            errorMessage = OWSLocalizedString(
                "BLOCK_LIST_ERROR_CONVERSATION_ALREADY_IN_BLOCKLIST",
                comment: "Error message indicating that a conversation can't be blocked because they are already blocked."
            )
        case .canBeSelected, .unknownError:
            owsFailDebug("Unexpected value.")
            errorMessage = OWSLocalizedString(
                "RECIPIENT_PICKER_ERROR_USER_CANNOT_BE_SELECTED",
                comment: "Error message indicating that a user can't be selected."
            )
        }
        OWSActionSheets.showErrorAlert(message: errorMessage)
    }
}

// MARK: - No Contacts

extension RecipientPickerViewController {

    private func createNoSignalContactsView() -> UIView {
        let heroImageView = UIImageView(image: .init(named: "uiEmptyContact"))
        heroImageView.layer.minificationFilter = .trilinear
        heroImageView.layer.magnificationFilter = .trilinear
        let heroSize = CGFloat.scaleFromIPhone5To7Plus(100, 150)
        heroImageView.autoSetDimensions(to: CGSize(square: heroSize))

        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString(
            "EMPTY_CONTACTS_LABEL_LINE1",
            comment: "Full width label displayed when attempting to compose message"
        )
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.font = .semiboldFont(ofSize: .scaleFromIPhone5To7Plus(17, 20))
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.numberOfLines = 0

        let subtitleLabel = UILabel()
        subtitleLabel.text = OWSLocalizedString(
            "EMPTY_CONTACTS_LABEL_LINE2",
            comment: "Full width label displayed when attempting to compose message"
        )
        subtitleLabel.textColor = Theme.secondaryTextAndIconColor
        subtitleLabel.font = .regularFont(ofSize: .scaleFromIPhone5To7Plus(12, 14))
        subtitleLabel.textAlignment = .center
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.numberOfLines = 0

        let headerStack = UIStackView(arrangedSubviews: [
            heroImageView,
            titleLabel,
            subtitleLabel
        ])
        headerStack.setCustomSpacing(30, after: heroImageView)
        headerStack.setCustomSpacing(15, after: titleLabel)
        headerStack.axis = .vertical
        headerStack.alignment = .center

        let buttonStack = UIStackView()
        buttonStack.axis = .vertical
        buttonStack.alignment = .fill
        buttonStack.spacing = 16

        func addButton(
            title: String,
            selector: Selector,
            accessibilityIdentifierName: String,
            icon: ThemeIcon,
            innerIconSize: CGFloat
        ) {
            let button = UIButton(type: .custom)
            button.addTarget(self, action: selector, for: .touchUpInside)
            button.accessibilityIdentifier = UIView.accessibilityIdentifier(
                in: self,
                name: accessibilityIdentifierName
            )
            buttonStack.addArrangedSubview(button)

            let iconView = OWSTableItem.buildIconInCircleView(
                icon: icon,
                iconSize: AvatarBuilder.standardAvatarSizePoints,
                innerIconSize: innerIconSize,
                iconTintColor: Theme.accentBlueColor
            )
            iconView.backgroundColor = tableViewController.cellBackgroundColor

            let label = UILabel()
            label.text = title
            label.font = .regularFont(ofSize: 17)
            label.textColor = Theme.primaryTextColor
            label.lineBreakMode = .byTruncatingTail

            let hStack = UIStackView(arrangedSubviews: [iconView, label])
            hStack.axis = .horizontal
            hStack.alignment = .center
            hStack.spacing = 12
            hStack.isUserInteractionEnabled = false
            button.addSubview(hStack)
            hStack.autoPinEdgesToSuperviewEdges()
        }

        if shouldShowNewGroup {
            addButton(
                title: OWSLocalizedString(
                    "NEW_GROUP_BUTTON",
                    comment: "Label for the 'create new group' button."
                ),
                selector: #selector(newGroupButtonPressed),
                accessibilityIdentifierName: "newGroupButton",
                icon: .composeNewGroupLarge,
                innerIconSize: 35
            )
        }

        if allowsAddByPhoneNumber {
            addButton(
                title: OWSLocalizedString(
                    "NO_CONTACTS_SEARCH_BY_PHONE_NUMBER",
                    comment: "Label for a button that lets users search for contacts by phone number"
                ),
                selector: #selector(hideBackgroundView),
                accessibilityIdentifierName: "searchByPhoneNumberButton",
                icon: .composeFindByPhoneNumberLarge,
                innerIconSize: 42
            )
        }

        if shouldShowInvites {
            addButton(
                title: OWSLocalizedString(
                    "INVITE_FRIENDS_CONTACT_TABLE_BUTTON",
                    comment: "Label for the cell that presents the 'invite contacts' workflow."
                ),
                selector: #selector(presentInviteFlow),
                accessibilityIdentifierName: "inviteContactsButton",
                icon: .composeInviteLarge,
                innerIconSize: 38
            )
        }

        let stackView = UIStackView(arrangedSubviews: [headerStack, buttonStack])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 50
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = .init(margin: 20)

        let result = UIView()
        result.backgroundColor = tableViewController.tableBackgroundColor
        result.addSubview(stackView)
        stackView.autoPinWidthToSuperview()
        stackView.autoVCenterInSuperview()
        return result
    }

    private func filteredSignalAccounts() -> [SignalAccount] {
        Array(lazyFilteredSignalAccounts())
    }

    /// Fetches the Signal Connections for the recipient picker.
    ///
    /// Excludes the local address (if `shouldHideLocalRecipient` is true) as
    /// well as any addresses that have been blocked.
    private func lazyFilteredSignalAccounts() -> LazyFilterSequence<[SignalAccount]> {
        let allSignalAccounts = contactsViewHelper.signalAccounts(includingLocalUser: !shouldHideLocalRecipient)
        guard allSignalAccounts.isEmpty.negated else {
            return allSignalAccounts.lazy.filter { _ in true }
        }
        let (blockedAddresses, hiddenAddresses) = databaseStorage.read { tx in
            return (
                blockingManager.blockedAddresses(transaction: tx),
                DependenciesBridge.shared.recipientHidingManager.hiddenAddresses(tx: tx.asV2Read)
            )
        }
        return allSignalAccounts.lazy.filter {
            !blockedAddresses.contains($0.recipientAddress) && !hiddenAddresses.contains($0.recipientAddress)

        }
    }

    /// Checks if we should show the dedicated "no contacts" view.
    ///
    /// If you don't have any contacts, there's a special UX we'll show to the
    /// user that looks a bit nicer than a (mostly) empty table view; that UX
    /// doesn't look anything like a normal table view. If you dismiss that
    /// view, we'll switch to a normal table view with a row that says "You have
    /// no contacts on Signal." This method controls whether or not we show this
    /// special UX to the user.
    ///
    /// However, it also works closely in tandem with `noContactsTableSection`
    /// and `contactAccessReminderSection`. If this method returns true, those
    /// sections can't possibly be shown. If they should be visible, this method
    /// must return false. The former is shown in place of the list of contacts,
    /// and it's either a loading spinner or the "You have no contacts on
    /// Signal." row. The latter is shown at the very top of the recipient
    /// picker and may contain a banner if the user has disabled access to their
    /// contacts. So, if the user doesn't have any contacts but has also
    /// prevented Signal from accessing their contacts, we don't show the
    /// special UX and instead allow the banner to be visible.
    private func shouldNoContactsModeBeActive() -> Bool {
        switch contactsManagerImpl.editingAuthorization {
        case .denied, .restricted:
            // Return false so `contactAccessReminderSection` is invoked.
            return false
        case .notAllowed where shouldShowContactAccessNotAllowedReminderItemWithSneakyTransaction():
            // Return false so `contactAccessReminderSection` is invoked.
            return false
        case .authorized where !contactsViewHelper.hasUpdatedContactsAtLeastOnce:
            // Return false so `noContactsTableSection` can show a spinner.
            return false
        case .authorized, .notAllowed:
            if !lazyFilteredSignalAccounts().isEmpty {
                // Return false if we have any contacts; we want to show them!
                return false
            }
            if preferences.hasDeclinedNoContactsView {
                // Return false if the user has explicitly told us to hide the UX.
                return false
            }
            return true
        }
    }

    private func showContactAppropriateViews() {
        isNoContactsModeActive = shouldNoContactsModeBeActive()
    }

    /// Returns a section when there's no contacts to show.
    ///
    /// Works closely with `shouldNoContactsModeBeActive` and therefore might
    /// not be invoked even if the user has no contacts.
    private func noContactsTableSection() -> OWSTableSection {
        switch contactsManagerImpl.editingAuthorization {
        case .denied, .restricted:
            return OWSTableSection()
        case .authorized where !contactsViewHelper.hasUpdatedContactsAtLeastOnce:
            return OWSTableSection(items: [loadingContactsTableItem()])
        case .authorized, .notAllowed:
            return OWSTableSection(items: [noContactsTableItem()])
        }
    }

    /// Returns a section with a banner at the top of the picker.
    ///
    /// Works closely with `shouldNoContactsModeBeActive`.
    private func contactAccessReminderSection() -> OWSTableSection? {
        let tableItem: OWSTableItem
        switch contactsManagerImpl.editingAuthorization {
        case .denied:
            tableItem = contactAccessDeniedReminderItem()
        case .restricted:
            // TODO: We don't show a reminder when the user isn't allowed to give
            // contacts permission. Should we?
            return nil
        case .authorized:
            return nil
        case .notAllowed:
            guard shouldShowContactAccessNotAllowedReminderItemWithSneakyTransaction() else {
                return nil
            }
            tableItem = contactAccessNotAllowedReminderItem()
        }
        return OWSTableSection(items: [tableItem])
    }

    private func noContactsTableItem() -> OWSTableItem {
        return OWSTableItem.softCenterLabel(
            withText: OWSLocalizedString(
                "SETTINGS_BLOCK_LIST_NO_CONTACTS",
                comment: "A label that indicates the user has no Signal contacts that they haven't blocked."
            )
        )
    }

    private func loadingContactsTableItem() -> OWSTableItem {
        let cell = OWSTableItem.newCell()

        let activityIndicatorView = UIActivityIndicatorView(style: .medium)
        cell.contentView.addSubview(activityIndicatorView)
        activityIndicatorView.startAnimating()
        activityIndicatorView.autoCenterInSuperview()
        activityIndicatorView.setCompressionResistanceHigh()
        activityIndicatorView.setContentHuggingHigh()

        cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "loading")

        let tableItem = OWSTableItem(customCellBlock: { cell })
        tableItem.customRowHeight = 40
        return tableItem
    }

    private func contactAccessDeniedReminderItem() -> OWSTableItem {
        return OWSTableItem(customCellBlock: {
            let reminderView = ReminderView(
                style: .warning,
                text: OWSLocalizedString(
                    "COMPOSE_SCREEN_MISSING_CONTACTS_PERMISSION",
                    comment: "Multi-line label explaining why compose-screen contact picker is empty."
                ),
                tapAction: { CurrentAppContext().openSystemSettings() }
            )

            let cell = OWSTableItem.newCell()
            cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "missing_contacts")
            cell.contentView.addSubview(reminderView)
            reminderView.autoPinEdgesToSuperviewEdges()

            return cell
        })
    }

    private static let keyValueStore = SDSKeyValueStore(collection: "RecipientPicker.contactAccess")
    private static let showNotAllowedReminderKey = "shouldShowNotAllowedReminder"

    private func shouldShowContactAccessNotAllowedReminderItemWithSneakyTransaction() -> Bool {
        databaseStorage.read {
            Self.keyValueStore.getBool(Self.showNotAllowedReminderKey, defaultValue: true, transaction: $0)
        }
    }

    private func hideShowContactAccessNotAllowedReminderItem() {
        databaseStorage.write {
            Self.keyValueStore.setBool(false, key: Self.showNotAllowedReminderKey, transaction: $0)
        }
        reloadContent()
    }

    private func contactAccessNotAllowedReminderItem() -> OWSTableItem {
        return OWSTableItem(customCellBlock: {
            ContactReminderTableViewCell(
                learnMoreAction: { [weak self] in
                    guard let self else { return }
                    ContactsViewHelper.presentContactAccessNotAllowedLearnMore(from: self)
                },
                dismissAction: { [weak self] in
                    self?.hideShowContactAccessNotAllowedReminderItem()
                }
            )
        })
    }

    @objc
    private func newGroupButtonPressed() {
        delegate?.recipientPickerNewGroupButtonWasPressed()
    }

    @objc
    private func hideBackgroundView() {
        self.preferences.setHasDeclinedNoContactsView(true)
        showContactAppropriateViews()
    }

    @objc
    private func presentInviteFlow() {
        let inviteFlow = InviteFlow(presentingViewController: self)
        self.inviteFlow = inviteFlow
        inviteFlow.present(isAnimated: true, completion: nil)
    }
}

// MARK: - Contacts, Connections, & Groups

extension RecipientPickerViewController {

    private func contactsSection() -> [OWSTableSection] {
        let signalAccountsToShow = filteredSignalAccounts()

        guard !signalAccountsToShow.isEmpty else {
            return [ noContactsTableSection() ]
        }

        // All contacts in one section
        guard shouldShowAlphabetSlider else {
            return [OWSTableSection(
                title: OWSLocalizedString(
                    "COMPOSE_MESSAGE_CONTACT_SECTION_TITLE",
                    comment: "Table section header for contact listing when composing a new message"
                ),
                items: signalAccountsToShow.map { item(forRecipient: PickedRecipient.for(address: $0.recipientAddress)) }
            )]
        }

        var collatedSignalAccounts: [[SignalAccount]] = collation.sectionTitles.map { _ in [SignalAccount]() }
        for signalAccount in signalAccountsToShow {
            let section = collation.section(for: signalAccount, collationStringSelector: #selector(SignalAccount.stringForCollation))
            guard section >= 0 else {
                owsFailDebug("Unexpected collation for name:\(signalAccount.stringForCollation())")
                continue
            }
            collatedSignalAccounts[section].append(signalAccount)
        }

        let contactSections = collatedSignalAccounts.enumerated().map { index, signalAccounts in
            // Don't show empty sections.
            // To accomplish this we add a section with a blank title rather than omitting the section altogether,
            // in order for section indexes to match up correctly
            guard !signalAccounts.isEmpty else { return OWSTableSection() }

            return OWSTableSection(
                title: collation.sectionTitles[index].uppercased(),
                items: signalAccounts.map { item(forRecipient: PickedRecipient.for(address: $0.recipientAddress)) }
            )
        }

        return contactSections
    }

    private func contactsSections(for searchResults: ComposeScreenSearchResultSet) -> [OWSTableSection] {
        AssertIsOnMainThread()

        var sections = [OWSTableSection]()

        // Contacts, with blocked contacts and hidden recipients removed.
        var matchedAccountPhoneNumbers = Set<String>()
        var contactsSectionItems = [OWSTableItem]()
        databaseStorage.read { tx in
            let blockedAddresses = self.blockingManager.blockedAddresses(transaction: tx)
            let hiddenAddresses = DependenciesBridge.shared.recipientHidingManager.hiddenAddresses(tx: tx.asV2Read)
            let addressesToSkip = blockedAddresses.union(hiddenAddresses)
            for recipientAddress in searchResults.signalAccounts.map({ $0.recipientAddress }) {
                guard !addressesToSkip.contains(recipientAddress) else { continue }

                if let phoneNumber = recipientAddress.phoneNumber {
                    matchedAccountPhoneNumbers.insert(phoneNumber)
                }

                contactsSectionItems.append(item(forRecipient: PickedRecipient.for(address: recipientAddress)))
            }
        }

        if !contactsSectionItems.isEmpty {
            sections.append(OWSTableSection(
                title: OWSLocalizedString(
                    "COMPOSE_MESSAGE_CONTACT_SECTION_TITLE",
                    comment: "Table section header for contact listing when composing a new message"
                ),
                items: contactsSectionItems
            ))
        }

        if let groupSection = groupSection(for: searchResults) {
            sections.append(groupSection)
        }

        if let findByNumberSection = findByNumberSection(for: searchResults, skipping: matchedAccountPhoneNumbers) {
            sections.append(findByNumberSection)
        }

        if let usernameSection = findByUsernameSection(for: searchResults) {
            sections.append(usernameSection)
        }

        guard !sections.isEmpty else {
            // No Search Results
             return [
                OWSTableSection(items: [
                    OWSTableItem.softCenterLabel(withText: OWSLocalizedString(
                        "SETTINGS_BLOCK_LIST_NO_SEARCH_RESULTS",
                        comment: "A label that indicates the user's search has no matching results."
                    ))
                ])
            ]
        }

        return sections
    }

    private func item(forRecipient recipient: PickedRecipient) -> OWSTableItem {
        switch recipient.identifier {
        case .address(let address):
            return OWSTableItem(
                dequeueCellBlock: { [weak self] tableView in
                    self?.addressCell(for: address, recipient: recipient, tableView: tableView) ?? UITableViewCell()
                },
                actionBlock: { [weak self] in
                    self?.tryToSelectRecipient(recipient)
                },
                contextMenuActionProvider: recipientContextMenuHelper.actionProvider(address: address)
            )
        case .group(let groupThread):
            return OWSTableItem(
                customCellBlock: { [weak self] in
                    self?.groupCell(for: groupThread, recipient: recipient) ?? UITableViewCell()
                },
                actionBlock: { [weak self] in
                    self?.tryToSelectRecipient(recipient)
                }
            )
        }
    }

    private func addressCell(for address: SignalServiceAddress, recipient: PickedRecipient, tableView: UITableView) -> UITableViewCell? {
        guard let cell = tableView.dequeueReusableCell(ContactTableViewCell.self) else { return nil }
        if let delegate, delegate.recipientPicker(self, getRecipientState: recipient) != .canBeSelected {
            cell.selectionStyle = .none
        }
        databaseStorage.read { transaction in
            let configuration = ContactCellConfiguration(address: address, localUserDisplayMode: .noteToSelf)
            if let delegate {
                if let accessoryView = delegate.recipientPicker(self, accessoryViewForRecipient: recipient, transaction: transaction) {
                    configuration.accessoryView = accessoryView
                } else {
                    let accessoryMessage = delegate.recipientPicker(self, accessoryMessageForRecipient: recipient, transaction: transaction)
                    configuration.accessoryMessage = accessoryMessage
                }
                if let attributedSubtitle = delegate.recipientPicker(self, attributedSubtitleForRecipient: recipient, transaction: transaction) {
                    configuration.attributedSubtitle = attributedSubtitle
                }
            }
            cell.configure(configuration: configuration, transaction: transaction)
        }
        return cell
    }

    private func groupCell(for groupThread: TSGroupThread, recipient: PickedRecipient) -> UITableViewCell? {
        let cell = GroupTableViewCell()

        if let delegate {
            if delegate.recipientPicker(self, getRecipientState: recipient) != .canBeSelected {
                cell.selectionStyle = .none
            }

            cell.accessoryMessage = databaseStorage.read {
                delegate.recipientPicker(self, accessoryMessageForRecipient: recipient, transaction: $0)
            }
        }

        cell.configure(thread: groupThread)

        return cell
    }
}

// MARK: - Find by Number

struct PhoneNumberFinder {
    var localNumber: String?
    var contactDiscoveryManager: ContactDiscoveryManager

    /// A list of all [+1, +20, ..., +N] known calling codes.
    static let validCallingCodes: [String] = {
        Set(PhoneNumberUtil.countryCodes(forSearchTerm: nil).lazy.compactMap {
            PhoneNumberUtil.callingCode(fromCountryCode: $0)
        }).sorted()
    }()

    /// Extracts the calling code (e.g., "+1") from an e164.
    ///
    /// Calling codes are defined such that only one prefix match should be
    /// possible. For example, "+1" is a valid prefix, but "+12" and "+123"
    /// aren't; if a number starts with "+1", the calling code is "+1".
    /// Similarly, "+351" and "+352" are valid prefixes, but "+35" isn't.
    ///
    /// - Returns:
    ///     The calling code (starting with "+") if the provided e164 starts
    ///     with a valid calling code.
    private static func callingCode(for e164: String) -> String? {
        owsAssertDebug(e164.hasPrefix("+"))
        return validCallingCodes.first { e164.hasPrefix($0) }
    }

    enum SearchResult {
        /// This e164 has already been validated by libPhoneNumber.
        case valid(validE164: String)

        /// This e164 consists of arbitrary user-provided text that needs to be
        /// validated before fetching it from CDS.
        case maybeValid(maybeValidE164: String)

        var maybeValidE164: String {
            switch self {
            case .valid(validE164: let validE164):
                return validE164
            case .maybeValid(maybeValidE164: let maybeValidE164):
                return maybeValidE164
            }
        }
    }

    /// For a given search term, extract potential phone number matches.
    ///
    /// We consider phone number matches that libPhoneNumber thinks may be
    /// valid, based on a fuzzy matching algorithm and the user's current phone
    /// number. It's possible to receive multiple matches.
    ///
    /// For example, if your current number has the +1 calling code and you
    /// enter "521 555 0100", you'll see three results:
    ///   - +1 521-555-0100
    ///   - +52 15 5501 00
    ///   - +52 55 5010 0
    ///
    /// We also consider arbitrary sequences of digits entered by the user. We
    /// wait to validate these until the user taps them. This improves the UX
    /// and helps make the feature more discoverable.
    ///
    /// - Parameter searchText:
    ///     Arbitrary text provided by the user. It could be "cat", the empty
    ///     string, or something that looks roughly like a phone number. If this
    ///     parameter contains fewer than 3 characters, an empty array is
    ///     returned.
    ///
    /// - Returns: Zero, one, or many matches.
    func parseResults(for searchText: String) -> [SearchResult] {
        guard searchText.count >= 3 else {
            return []
        }

        // Check for valid libPhoneNumber results.
        let uniqueResults = OrderedSet(
            PhoneNumber.tryParsePhoneNumbers(
                fromUserSpecifiedText: searchText,
                clientPhoneNumber: localNumber ?? ""
            ).lazy.compactMap { self.validE164(from: $0) }
        )
        if !uniqueResults.isEmpty {
            return uniqueResults.orderedMembers.map { .valid(validE164: $0) }
        }

        // Otherwise, show a potentially-invalid number that we'll validate if the
        // user tries to select it.
        if let maybeValidE164 = parseFakeSearchPhoneNumber(for: searchText) {
            return [.maybeValid(maybeValidE164: maybeValidE164)]
        }

        return []
    }

    private func parseFakeSearchPhoneNumber(for searchText: String) -> String? {
        let filteredValue = (searchText as NSString).filterAsE164()

        let potentialE164: String
        if filteredValue.hasPrefix("+") {
            potentialE164 = filteredValue
        } else if let localNumber, let callingCode = Self.callingCode(for: localNumber) {
            potentialE164 = callingCode + filteredValue
        } else {
            owsFailDebug("No localNumber")
            return nil
        }

        // Stop showing results after 20 characters. A 3-digit country code (4
        // characters, including "+") and a 15-digit phone number would be 19
        // characters. Allow for one extra accidental character, even though a
        // 20-digit number should always fail to parse.
        guard (3...20).contains(potentialE164.count) else {
            return nil
        }

        // Allow only symbols, digits, and whitespace. The `filterE164()` call
        // above will keep only "+" and ASCII digits, but the user may try to
        // format the number themselves, or they may paste a number formatted
        // elsewhere. If the user types a letter, this result will disappear.

        var allowedCharacters = CharacterSet(charactersIn: "+0123456789")
        allowedCharacters.formUnion(.whitespaces)
        allowedCharacters.formUnion(.punctuationCharacters)  // allow "(", ")", "-", etc.
        guard searchText.rangeOfCharacter(from: allowedCharacters.inverted) == nil else {
            return nil
        }

        return potentialE164
    }

    private func validE164(from phoneNumber: PhoneNumber) -> String? {
        let e164 = phoneNumber.toE164()
        guard let callingCode = Self.callingCode(for: e164) else {
            return nil
        }
        guard (1...15).contains(e164.count - callingCode.count) else {
            return nil
        }
        return e164
    }

    enum LookupResult {
        /// The phone number was found on CDS.
        case success(SignalRecipient)

        /// The phone number is valid but doesn't exist on CDS. Perhaps phone number
        /// discovery is disabled, or perhaps the account isn't registered.
        case notFound(validE164: String)

        /// The phone number isn't valid, so we didn't even send a request to CDS to check.
        case notValid(invalidE164: String)
    }

    func lookUp(phoneNumber searchResult: SearchResult) -> Promise<LookupResult> {
        let validE164ToLookUp: String
        switch searchResult {
        case .valid(validE164: let validE164):
            validE164ToLookUp = validE164
        case .maybeValid(maybeValidE164: let maybeValidE164):
            guard
                let phoneNumber = PhoneNumber.tryParsePhoneNumber(fromUserSpecifiedText: maybeValidE164),
                let validE164 = validE164(from: phoneNumber)
            else {
                return .value(.notValid(invalidE164: maybeValidE164))
            }
            validE164ToLookUp = validE164
        }
        return firstly {
            contactDiscoveryManager.lookUp(phoneNumbers: [validE164ToLookUp], mode: .oneOffUserRequest)
        }.map { signalRecipients in
            if let signalRecipient = signalRecipients.first {
                return .success(signalRecipient)
            } else {
                return .notFound(validE164: validE164ToLookUp)
            }
        }
    }
}

extension RecipientPickerViewController {

    private func findByNumberCell(for phoneNumber: String, tableView: UITableView) -> UITableViewCell? {
        guard let cell = tableView.dequeueReusableCell(NonContactTableViewCell.self) else { return nil }
        cell.configureWithPhoneNumber(phoneNumber)
        return cell
    }

    public func findByNumberSection(
        for searchResults: ComposeScreenSearchResultSet,
        skipping alreadyMatchedPhoneNumbers: Set<String>
    ) -> OWSTableSection? {
        let phoneNumberFinder = PhoneNumberFinder(
            localNumber: TSAccountManager.localNumber,
            contactDiscoveryManager: contactDiscoveryManager
        )
        var phoneNumberResults = phoneNumberFinder.parseResults(for: searchResults.searchText)
        // Don't show phone numbers that are visible in other sections.
        phoneNumberResults.removeAll { alreadyMatchedPhoneNumbers.contains($0.maybeValidE164) }
        // Don't show the user's own number if they can't select it.
        if shouldHideLocalRecipient, let localNumber = phoneNumberFinder.localNumber {
            phoneNumberResults.removeAll { localNumber == $0.maybeValidE164 }
        }
        guard !phoneNumberResults.isEmpty else {
            return nil
        }

        return OWSTableSection(
            title: OWSLocalizedString(
                "COMPOSE_MESSAGE_PHONE_NUMBER_SEARCH_SECTION_TITLE",
                comment: "Table section header for phone number search when composing a new message"
            ),
            items: phoneNumberResults.map { phoneNumberResult in
                return OWSTableItem(
                    dequeueCellBlock: { [weak self] tableView in
                        let e164 = phoneNumberResult.maybeValidE164
                        return self?.findByNumberCell(for: e164, tableView: tableView) ?? UITableViewCell()
                    },
                    actionBlock: { [weak self] in
                        self?.findByNumber(phoneNumberResult, using: phoneNumberFinder)
                    }
                )
            }
        )
    }

    /// Performs a lookup for an unknown number entered by the user.
    ///
    /// - If the number is found, the recipient will be selected. (The
    ///   definition of "selected" depends on whether you're on the Compose
    ///   screen, Add Group Members screen, etc.)
    ///
    /// - If the number isn't found, the behavior depends on `selectionMode`. If
    ///   you're trying to block someone, we'll allow the number to be blocked.
    ///   Otherwise, you'll be told that the number isn't registered.
    ///
    /// - If the number isn't valid, you'll be told that it's not valid.
    ///
    /// - Parameter phoneNumberResult: The search result the user tapped.
    private func findByNumber(_ phoneNumberResult: PhoneNumberFinder.SearchResult, using finder: PhoneNumberFinder) {
        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: true) { modal in
            firstly {
                finder.lookUp(phoneNumber: phoneNumberResult)
            }.done(on: DispatchQueue.main) { [weak self] lookupResult in
                modal.dismissIfNotCanceled {
                    guard let self = self else { return }
                    self.handlePhoneNumberLookupResult(lookupResult)
                }
            }.catch(on: DispatchQueue.main) { error in
                modal.dismissIfNotCanceled {
                    OWSActionSheets.showErrorAlert(message: error.userErrorDescription)
                }
            }
        }
    }

    private func handlePhoneNumberLookupResult(_ lookupResult: PhoneNumberFinder.LookupResult) {
        switch (selectionMode, lookupResult) {
        case (_, .success(let signalRecipient)):
            // If the lookup was successful, select the recipient.
            tryToSelectRecipient(.for(address: signalRecipient.address))

        case (.blocklist, .notFound(validE164: let validE164)):
            // If we're trying to block an unregistered user, allow it.
            tryToSelectRecipient(.for(address: SignalServiceAddress(phoneNumber: validE164)))

        case (.`default`, .notFound(validE164: let validE164)):
            // Otherwise, if we're trying to contact someone, offer to invite them.
            presentSMSInvitationSheet(for: validE164)

        case (_, .notValid(invalidE164: let invalidE164)):
            // If the number isn't valid, show an error so the user can fix it.
            presentInvalidNumberSheet(for: invalidE164)
        }
    }

    private func presentSMSInvitationSheet(for phoneNumber: String) {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "RECIPIENT_PICKER_INVITE_TITLE",
                comment: "Alert title. Shown after selecting a phone number that isn't a Signal user."
            ),
            message: String(
                format: OWSLocalizedString(
                    "RECIPIENT_PICKER_INVITE_MESSAGE",
                    comment: "Alert text. Shown after selecting a phone number that isn't a Signal user."
                ),
                PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: phoneNumber)
            )
        )
        actionSheet.addAction(OWSActionSheets.cancelAction)
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "RECIPIENT_PICKER_INVITE_ACTION",
                comment: "Button. Shown after selecting a phone number that isn't a Signal user. Tapping the button will open a view that allows the user to send an SMS message to specified phone number."
            ),
            style: .default,
            handler: { [weak self] action in
                guard let self = self else { return }
                guard MFMessageComposeViewController.canSendText() else {
                    OWSActionSheets.showErrorAlert(message: InviteFlow.unsupportedFeatureMessage)
                    return
                }
                let inviteFlow = InviteFlow(presentingViewController: self)
                inviteFlow.sendSMSTo(phoneNumbers: [phoneNumber])
                // We need to keep InviteFlow around until it's completed. We tie its
                // lifetime to this view controller -- while not perfect, this avoids
                // leaking the object.
                self.inviteFlow = inviteFlow
            }
        ))
        presentActionSheet(actionSheet)
    }

    private func presentInvalidNumberSheet(for phoneNumber: String) {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "RECIPIENT_PICKER_INVALID_NUMBER_TITLE",
                comment: "Alert title. Shown after selecting a phone number that isn't valid."
            ),
            message: String(
                format: OWSLocalizedString(
                    "RECIPIENT_PICKER_INVALID_NUMBER_MESSAGE",
                    comment: "Alert text. Shown after selecting a phone number that isn't valid."
                ),
                PhoneNumber.bestEffortFormatPartialUserSpecifiedText(toLookLikeAPhoneNumber: phoneNumber)
            )
        )
        actionSheet.addAction(OWSActionSheets.okayAction)
        presentActionSheet(actionSheet)
    }
}

// MARK: - FindByPhoneNumberDelegate
// ^^ This refers to the *separate* "Find by Phone Number" row that you can tap.

extension RecipientPickerViewController: FindByPhoneNumberDelegate {

    public func findByPhoneNumber(
        _ findByPhoneNumber: FindByPhoneNumberViewController,
        didSelectAddress address: SignalServiceAddress
    ) {
        owsAssertDebug(address.isValid)

        tryToSelectRecipient(.for(address: address))
    }
}

// MARK: - Find by Username

extension RecipientPickerViewController {

    private func parsePossibleSearchUsername(for searchText: String) -> String? {
        let username = searchText

        guard let firstCharacter = username.first else {
            // Don't show username results -- the user hasn't searched for anything
            return nil
        }
        guard firstCharacter != "+" else {
            // Don't show username results -- assume this is a phone number
            return nil
        }
        guard !("0"..."9").contains(firstCharacter) else {
            // Don't show username results -- assume this is a phone number
            return nil
        }

        return username
    }

    private func findByUsernameCell(for username: String, tableView: UITableView) -> UITableViewCell? {
        guard let cell = tableView.dequeueReusableCell(NonContactTableViewCell.self) else { return nil }
        cell.configureWithUsername(username)
        return cell
    }

    private func findByUsernameSection(for searchResults: ComposeScreenSearchResultSet) -> OWSTableSection? {
        guard FeatureFlags.usernames else {
            return nil
        }
        guard let username = parsePossibleSearchUsername(for: searchResults.searchText) else {
            return nil
        }
        let tableItem = OWSTableItem(
            dequeueCellBlock: { [weak self] tableView in
                self?.findByUsernameCell(for: username, tableView: tableView) ?? UITableViewCell()
            },
            actionBlock: { [weak self] in
                self?.findByUsername(username)
            }
        )
        return OWSTableSection(
            title: OWSLocalizedString(
                "COMPOSE_MESSAGE_USERNAME_SEARCH_SECTION_TITLE",
                comment: "Table section header for username search when composing a new message"
            ),
            items: [tableItem]
        )
    }

    private func findByUsername(_ username: String) {
        databaseStorage.read { tx in
            UsernameQuerier().queryForUsername(
                username: username,
                fromViewController: self,
                tx: tx,
                onSuccess: { [weak self] aci in
                    AssertIsOnMainThread()

                    guard let self else { return }
                    self.tryToSelectRecipient(.for(address: SignalServiceAddress(aci)))
                }
            )
        }
    }
}

fileprivate extension SignalAccount {

    @objc
    func stringForCollation() -> String {
        contactsManagerImpl.comparableNameForSignalAccountWithSneakyTransaction(self)
    }
}
