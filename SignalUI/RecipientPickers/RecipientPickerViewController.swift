//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MessageUI
public import SignalServiceKit
import SwiftUI

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

    public weak var delegate: RecipientPickerDelegate? {
        didSet {
            recipientContextMenuHelper.delegate = delegate
        }
    }

    // MARK: Configuration

    public var allowsAddByAddress = true
    public var shouldHideLocalRecipient = true
    public var selectionMode = SelectionMode.default
    public var groupsToShow = GroupsToShow.groupsThatUserIsMemberOfWhenSearching
    public var shouldShowInvites = false
    public var shouldShowAlphabetSlider = true
    public var shouldShowNewGroup = false
    public var findByPhoneNumberButtonTitle: String?

    // MARK: Signal Connections

    private var signalConnections = [ComparableDisplayName]()
    private var signalConnectionAddresses = Set<SignalServiceAddress>()

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

        updateSignalConnections()
        SUIEnvironment.shared.contactsViewHelperRef.addObserver(self)

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
        SSKEnvironment.shared.contactManagerImplRef.requestSystemContactsOnce()

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
    private var lastSearchTask: Task<Void, Never>?

    private var _searchResults = Atomic<RecipientSearchResultSet?>(wrappedValue: nil)

    private var searchResults: RecipientSearchResultSet? {
        get { _searchResults.wrappedValue }
        set {
            _searchResults.wrappedValue = newValue
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

        lastSearchTask?.cancel()
        lastSearchTask = Task {
            do throws(CancellationError) {
                let searchResults = try await performSearch(
                    searchText: searchText,
                    shouldHideLocalRecipient: self.shouldHideLocalRecipient,
                )
                if Task.isCancelled {
                    throw CancellationError()
                }
                self.searchResults = searchResults
            } catch {
                // Discard obsolete search results.
                return
            }
        }
    }

    private nonisolated func performSearch(
        searchText: String,
        shouldHideLocalRecipient: Bool,
    ) async throws(CancellationError) -> RecipientSearchResultSet {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        return try databaseStorage.read { tx throws(CancellationError) in
            return try FullTextSearcher.shared.searchForRecipients(
                searchText: searchText,
                includeLocalUser: !shouldHideLocalRecipient,
                includeStories: false,
                tx: tx
            )
        }
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
        searchBar.placeholder = OWSLocalizedString(
            "SEARCH_BY_NAME_OR_USERNAME_OR_NUMBER_PLACEHOLDER_TEXT",
            comment: "Placeholder text indicating the user can search for contacts by name, username, or phone number."
        )
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
            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
            blockingManager: SSKEnvironment.shared.blockingManagerRef,
            recipientHidingManager: DependenciesBridge.shared.recipientHidingManager,
            accountManager: DependenciesBridge.shared.tsAccountManager,
            contactsManager: SSKEnvironment.shared.contactManagerRef,
            fromViewController: self,
            delegate: self.delegate
        )
    }()

    // MARK: - Fetching Signal Connections

    private func updateSignalConnections() {
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager

            // All Signal Connections that we believe are registered. In theory, this
            // should include your system contacts, the people you chat with, and Note to Self.
            let whitelistedAddresses = Set(SSKEnvironment.shared.profileManagerRef.allWhitelistedRegisteredAddresses(tx: tx))
            let blockedAddresses = SSKEnvironment.shared.blockingManagerRef.blockedAddresses(transaction: tx)
            let hiddenAddresses = DependenciesBridge.shared.recipientHidingManager.hiddenAddresses(tx: tx)

            var resolvedAddresses = Set(whitelistedAddresses).subtracting(blockedAddresses).subtracting(hiddenAddresses)

            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
                Logger.error("No local identifiers")
                return
            }

            if !shouldHideLocalRecipient {
                resolvedAddresses.insert(localIdentifiers.aciAddress)
            } else {
                resolvedAddresses.remove(localIdentifiers.aciAddress)
            }

            signalConnections = SSKEnvironment.shared.contactManagerImplRef.sortedComparableNames(for: resolvedAddresses, tx: tx).filter { $0.displayName.hasKnownValue }
            signalConnectionAddresses = Set(signalConnections.lazy.map { $0.address })
        }
    }

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
                withText: OWSLocalizedString(
                    "NEW_GROUP_BUTTON",
                    comment: "Label for the 'create new group' button."
                ),
                actionBlock: { [weak self] in
                    self?.newGroupButtonPressed()
                }
            ))
        }

        if allowsAddByAddress && !isSearching {
            // Find by username
            staticSection.add(OWSTableItem.disclosureItem(
                icon: .profileUsername,
                withText: OWSLocalizedString(
                    "NEW_CONVERSATION_FIND_BY_USERNAME",
                    comment: "A label for the cell that lets you add a new member by their username"
                ),
                actionBlock: { [weak self] in
                    guard let self else { return }
                    let viewController = FindByUsernameViewController()
                    viewController.findByUsernameDelegate = self
                    self.navigationController?.pushViewController(viewController, animated: true)
                }
            ))

            // Find by phone number
            staticSection.add(OWSTableItem.disclosureItem(
                icon: .phoneNumber,
                withText: OWSLocalizedString(
                    "NEW_CONVERSATION_FIND_BY_PHONE_NUMBER",
                    comment: "A label the cell that lets you add a new member to a group."
                ),
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

        if staticSection.itemCount > 0 {
            tableContents.add(staticSection)
        }

        // Render any non-contact picked recipients
        if !pickedRecipients.isEmpty && !isSearching {
            let sectionRecipients = pickedRecipients.filter { recipient in
                guard let recipientAddress = recipient.address else { return false }
                if signalConnectionAddresses.contains(recipientAddress) {
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

        // Invite Contacts
        if shouldShowInvites && !isSearching && SSKEnvironment.shared.contactManagerImplRef.sharingAuthorization != .denied {
            let bottomSection = OWSTableSection(title: OWSLocalizedString(
                "INVITE_FRIENDS_CONTACT_TABLE_HEADER",
                comment: "Header label above a section for more options for adding contacts"
            ))
            bottomSection.add(OWSTableItem.disclosureItem(
                icon: .settingsInvite,
                withText: OWSLocalizedString(
                    "INVITE_FRIENDS_CONTACT_TABLE_BUTTON",
                    comment: "Label for the cell that presents the 'invite contacts' workflow."
                ),
                actionBlock: { [weak self] in
                    self?.presentInviteFlow()
                }
            ))
            tableContents.add(bottomSection)
        }

        tableViewController.contents = tableContents
    }

    // MARK: -

    @objc
    private func pullToRefreshPerformed(_ refreshControl: UIRefreshControl) {
        AssertIsOnMainThread()
        Logger.info("Beginning refreshing")

        Task { @MainActor in
            if DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice {
                try? await SSKEnvironment.shared.contactManagerImplRef.userRequestedSystemContactsRefresh().awaitable()
            } else {
                try? await SSKEnvironment.shared.syncManagerRef.sendAllSyncRequestMessages(timeout: 20).awaitable()
            }
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
        updateSignalConnections()
        updateTableContents()
        showContactAppropriateViews()
    }
}

extension RecipientPickerViewController {

    public func groupSection(for searchResults: RecipientSearchResultSet) -> OWSTableSection? {
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
        didPrepareToSelectRecipient(recipient)
    }

    private func didPrepareToSelectRecipient(_ recipient: PickedRecipient) {
        AssertIsOnMainThread()

        guard let delegate = delegate else { return }

        delegate.recipientPicker(self, didSelectRecipient: recipient)
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

        if allowsAddByAddress {
            addButton(
                title: OWSLocalizedString(
                    "NO_CONTACTS_SEARCH_BY_USERNAME",
                    comment: "Label for a button that lets users search for contacts by username"
                ),
                selector: #selector(hideBackgroundView),
                accessibilityIdentifierName: "searchByPhoneNumberButton",
                icon: .composeFindByUsernameLarge,
                innerIconSize: 40
            )

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
        switch SSKEnvironment.shared.contactManagerImplRef.syncingAuthorization {
        case .denied, .restricted:
            // Return false so `contactAccessReminderSection` is invoked.
            return false
        case .limited:
            // Return false so `contactAccessReminderSection` is invoked.
            return false
        case .notAllowed where shouldShowContactAccessNotAllowedReminderItemWithSneakyTransaction():
            // Return false so `contactAccessReminderSection` is invoked.
            return false
        case .authorized where !SSKEnvironment.shared.contactManagerImplRef.hasLoadedSystemContacts:
            // Return false so `noContactsTableSection` can show a spinner.
            return false
        case .authorized, .notAllowed:
            if !signalConnections.isEmpty {
                // Return false if we have any contacts; we want to show them!
                return false
            }
            if SSKEnvironment.shared.preferencesRef.hasDeclinedNoContactsView {
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
        switch SSKEnvironment.shared.contactManagerImplRef.syncingAuthorization {
        case .denied, .restricted:
            return OWSTableSection()
        case .limited:
            return OWSTableSection()
        case .authorized where !SSKEnvironment.shared.contactManagerImplRef.hasLoadedSystemContacts:
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
        switch SSKEnvironment.shared.contactManagerImplRef.syncingAuthorization {
        case .denied:
            tableItem = contactAccessDeniedReminderItem()
        case .limited:
            if #available(iOS 18, *) {
                tableItem = contactAccessLimitedReminderItem()
            } else {
                return nil
            }
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
            ContactAccessDeniedReminderTableViewCell {
                CurrentAppContext().openSystemSettings()
            }
        })
    }

    @available(iOS 18, *)
    private func contactAccessLimitedReminderItem() -> OWSTableItem {
        return OWSTableItem(customCellBlock: {
            let cell = ContactAccessLimitedReminderTableViewCell()
            cell.contentConfiguration = UIHostingConfiguration {
                ContactAccessLimitedReminderView {
                    Task {
                        // Fetch all contacts the app has access to.
                        try? await SSKEnvironment.shared.contactManagerImplRef.userRequestedSystemContactsRefresh().asVoid().awaitable()
                    }
                }
            }
            return cell
        })
    }

    private static let keyValueStore = KeyValueStore(collection: "RecipientPicker.contactAccess")
    private static let showNotAllowedReminderKey = "shouldShowNotAllowedReminder"

    private func shouldShowContactAccessNotAllowedReminderItemWithSneakyTransaction() -> Bool {
        SSKEnvironment.shared.databaseStorageRef.read {
            Self.keyValueStore.getBool(Self.showNotAllowedReminderKey, defaultValue: true, transaction: $0)
        }
    }

    private func hideShowContactAccessNotAllowedReminderItem() {
        SSKEnvironment.shared.databaseStorageRef.write {
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
        SSKEnvironment.shared.preferencesRef.setHasDeclinedNoContactsView(true)
        showContactAppropriateViews()
    }

    @objc
    private func presentInviteFlow() {
        let inviteFlow = InviteFlow(presentingViewController: self)
        inviteFlow.present(isAnimated: true, completion: nil)
    }
}

// MARK: - Contacts, Connections, & Groups

extension RecipientPickerViewController {
    private func contactsSection() -> [OWSTableSection] {
        guard !signalConnections.isEmpty else {
            return [ noContactsTableSection() ]
        }

        // All contacts in one section
        guard shouldShowAlphabetSlider else {
            return [OWSTableSection(
                title: OWSLocalizedString(
                    "COMPOSE_MESSAGE_CONTACT_SECTION_TITLE",
                    comment: "Table section header for contact listing when composing a new message"
                ),
                items: signalConnections.map { item(forRecipient: PickedRecipient.for(address: $0.address)) }
            )]
        }

        var collatedSignalConnections = collation.sectionTitles.map { _ in return [ComparableDisplayName]() }
        for signalConnection in signalConnections {
            let section = collation.section(
                for: CollatableComparableDisplayName(signalConnection),
                collationStringSelector: #selector(CollatableComparableDisplayName.collationString)
            )
            guard section >= 0 else {
                continue
            }
            collatedSignalConnections[section].append(signalConnection)
        }

        let contactSections = collatedSignalConnections.enumerated().map { index, signalConnections in
            // Don't show empty sections.
            // To accomplish this we add a section with a blank title rather than omitting the section altogether,
            // in order for section indexes to match up correctly
            if signalConnections.isEmpty {
                return OWSTableSection()
            }

            return OWSTableSection(
                title: collation.sectionTitles[index].uppercased(),
                items: signalConnections.map { item(forRecipient: PickedRecipient.for(address: $0.address)) }
            )
        }

        return contactSections
    }

    private func contactsSections(for searchResults: RecipientSearchResultSet) -> [OWSTableSection] {
        AssertIsOnMainThread()

        var sections = [OWSTableSection]()

        // Contacts, with blocked contacts and hidden recipients removed.
        var matchedAccountPhoneNumbers = Set<String>()
        var contactsSectionItems = [OWSTableItem]()
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            for recipientAddress in searchResults.contactResults.map({ $0.recipientAddress }) {
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
                },
                contextMenuActionProvider: recipientContextMenuHelper.actionProvider(groupThread: groupThread)
            )
        }
    }

    private func addressCell(for address: SignalServiceAddress, recipient: PickedRecipient, tableView: UITableView) -> UITableViewCell? {
        guard let cell = tableView.dequeueReusableCell(ContactTableViewCell.self) else { return nil }
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            let configuration = ContactCellConfiguration(address: address, localUserDisplayMode: .noteToSelf)
            if let delegate {
                cell.selectionStyle = delegate.recipientPicker(self, selectionStyleForRecipient: recipient, transaction: transaction)
                if let accessoryView = delegate.recipientPicker(self, accessoryViewForRecipient: recipient, transaction: transaction) {
                    configuration.accessoryView = accessoryView
                } else {
                    let accessoryMessage = delegate.recipientPicker(self, accessoryMessageForRecipient: recipient, transaction: transaction)
                    configuration.accessoryMessage = accessoryMessage
                }
                if let attributedSubtitle = delegate.recipientPicker(self, attributedSubtitleForRecipient: recipient, transaction: transaction) {
                    configuration.attributedSubtitle = attributedSubtitle
                }

                configuration.allowUserInteraction = delegate.recipientPicker(self, shouldAllowUserInteractionForRecipient: recipient, transaction: transaction)

                let isSystemContact = SSKEnvironment.shared.contactManagerRef.fetchSignalAccount(for: address, transaction: transaction) != nil
                configuration.shouldShowContactIcon = isSystemContact
            }
            cell.configure(configuration: configuration, transaction: transaction)
        }
        return cell
    }

    private func groupCell(for groupThread: TSGroupThread, recipient: PickedRecipient) -> UITableViewCell? {
        let cell = GroupTableViewCell()

        if let delegate {
            SSKEnvironment.shared.databaseStorageRef.read { tx in
                cell.selectionStyle = delegate.recipientPicker(self, selectionStyleForRecipient: recipient, transaction: tx)
                cell.accessoryMessage = delegate.recipientPicker(self, accessoryMessageForRecipient: recipient, transaction: tx)
                cell.customAccessoryView = delegate.recipientPicker(self, accessoryViewForRecipient: recipient, transaction: tx)?.accessoryView
            }
        }

        cell.configure(thread: groupThread)

        return cell
    }
}

// MARK: - Find by Number

struct PhoneNumberFinder {
    let localNumber: String?
    let contactDiscoveryManager: ContactDiscoveryManager
    let phoneNumberUtil: PhoneNumberUtil

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
            phoneNumberUtil.parsePhoneNumbers(
                userSpecifiedText: searchText,
                localPhoneNumber: localNumber ?? ""
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
        let filteredValue = searchText.filteredAsE164

        let potentialE164: String
        if filteredValue.hasPrefix("+") {
            potentialE164 = filteredValue
        } else if
            let localNumber,
            let callingCode = phoneNumberUtil.parseE164(localNumber)?.getCallingCode()
        {
            potentialE164 = "+\(callingCode)\(filteredValue)"
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
        return E164(phoneNumber.e164)?.stringValue
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

    func lookUp(phoneNumber searchResult: SearchResult) async throws -> LookupResult {
        let validE164ToLookUp: String
        switch searchResult {
        case .valid(validE164: let validE164):
            validE164ToLookUp = validE164
        case .maybeValid(maybeValidE164: let maybeValidE164):
            guard
                let phoneNumber = phoneNumberUtil.parsePhoneNumber(userSpecifiedText: maybeValidE164),
                let validE164 = validE164(from: phoneNumber)
            else {
                return .notValid(invalidE164: maybeValidE164)
            }
            validE164ToLookUp = validE164
        }
        let signalRecipients = try await contactDiscoveryManager.lookUp(phoneNumbers: [validE164ToLookUp], mode: .oneOffUserRequest)
        if let signalRecipient = signalRecipients.first {
            return .success(signalRecipient)
        } else {
            return .notFound(validE164: validE164ToLookUp)
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
        for searchResults: RecipientSearchResultSet,
        skipping alreadyMatchedPhoneNumbers: Set<String>
    ) -> OWSTableSection? {
        let phoneNumberFinder = PhoneNumberFinder(
            localNumber: DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber,
            contactDiscoveryManager: SSKEnvironment.shared.contactDiscoveryManagerRef,
            phoneNumberUtil: SSKEnvironment.shared.phoneNumberUtilRef
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
        ModalActivityIndicatorViewController.present(fromViewController: self) { modal in
            do {
                let lookupResult = try await finder.lookUp(phoneNumber: phoneNumberResult)
                modal.dismissIfNotCanceled {
                    self.handlePhoneNumberLookupResult(lookupResult)
                }
            } catch {
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
            Self.presentSMSInvitationSheet(for: validE164, fromViewController: self)

        case (_, .notValid(invalidE164: let invalidE164)):
            // If the number isn't valid, show an error so the user can fix it.
            presentInvalidNumberSheet(for: invalidE164)
        }
    }

    public static func presentSMSInvitationSheet(
        for phoneNumber: String,
        fromViewController viewController: UIViewController,
        dismissalDelegate: (any SheetDismissalDelegate)? = nil
    ) {
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
                PhoneNumber.bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(phoneNumber)
            )
        )
        actionSheet.addAction(OWSActionSheets.cancelAction)
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString(
                "RECIPIENT_PICKER_INVITE_ACTION",
                comment: "Button. Shown after selecting a phone number that isn't a Signal user. Tapping the button will open a view that allows the user to send an SMS message to specified phone number."
            ),
            style: .default,
            handler: { [weak viewController] action in
                guard let viewController else { return }
                guard MFMessageComposeViewController.canSendText() else {
                    OWSActionSheets.showErrorAlert(message: InviteFlow.unsupportedFeatureMessage, fromViewController: viewController)
                    return
                }
                let inviteFlow = InviteFlow(presentingViewController: viewController)
                inviteFlow.sendSMSTo(phoneNumbers: [phoneNumber])
            }
        ))
        actionSheet.dismissalDelegate = dismissalDelegate
        viewController.presentActionSheet(actionSheet)
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
                PhoneNumber.bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber(phoneNumber)
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

extension RecipientPickerViewController: FindByUsernameDelegate {
    func findByUsername(address: SignalServiceAddress) {
        owsAssertDebug(address.isValid)
        tryToSelectRecipient(.for(address: address))
    }

    var shouldShowQRCodeButton: Bool {
        delegate?.shouldShowQRCodeButton ?? false
    }

    func openQRCodeScanner() {
        delegate?.openUsernameQRCodeScanner()
    }
}

// MARK: - Find by Username

extension RecipientPickerViewController {

    private func parsePossibleSearchUsername(for searchText: String) -> String? {
        let username = FindByUsername.preParseUsername(searchText)

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

    private func findByUsernameSection(for searchResults: RecipientSearchResultSet) -> OWSTableSection? {
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
        SSKEnvironment.shared.databaseStorageRef.read { tx in
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

// MARK: - ContactAccessDeniedReminderTableViewCell

private class ContactAccessDeniedReminderTableViewCell: UITableViewCell {
    private let tapAction: () -> Void

    init(openSettingsAction: @escaping () -> Void) {
        self.tapAction = openSettingsAction
        super.init(style: .default, reuseIdentifier: nil)

        let label = UILabel()
        contentView.addSubview(label)
        label.autoPinEdgesToSuperviewMargins()
        label.numberOfLines = 0
        label.attributedText = NSAttributedString.composed(of: [
            OWSLocalizedString(
                "COMPOSE_SCREEN_MISSING_CONTACTS_PERMISSION",
                comment: "Multi-line label explaining why compose-screen contact picker is empty."
            ),
            "\n",
            OWSLocalizedString(
                "COMPOSE_SCREEN_MISSING_CONTACTS_CTA",
                comment: "Button to open settings from an empty compose-screen contact picker."
            ).styled(
                with: .font(.dynamicTypeSubheadline.semibold()),
                .alignment(.trailing)
            )
        ]).styled(
            with: .font(.dynamicTypeSubheadline),
            .color(Theme.primaryTextColor)
        )

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func didTap() {
        tapAction()
    }
}

extension ContactAccessDeniedReminderTableViewCell: CustomBackgroundColorCell {
    func customBackgroundColor(forceDarkMode: Bool) -> UIColor {
        ReminderView.warningBackgroundColor(forceDarkMode: forceDarkMode)
    }

    func customSelectedBackgroundColor(forceDarkMode: Bool) -> UIColor {
        customBackgroundColor(forceDarkMode: forceDarkMode)
    }
}

// MARK: - ContactAccessLimitedReminderTableViewCell

class ContactAccessLimitedReminderTableViewCell: UITableViewCell {}

extension ContactAccessLimitedReminderTableViewCell: CustomBackgroundColorCell {
    func customBackgroundColor(forceDarkMode: Bool) -> UIColor {
        Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_gray05
    }

    func customSelectedBackgroundColor(forceDarkMode: Bool) -> UIColor {
        customBackgroundColor(forceDarkMode: forceDarkMode)
    }
}
