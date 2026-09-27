//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import SignalUI
import UIKit

protocol GroupMemberSearchViewControllerDelegate: AnyObject {
    func groupMemberSearchViewControllerRequestAddMembers(_ viewController: GroupMemberSearchViewController)
    func groupMemberSearchViewControllerRequestShareGroupLink(_ viewController: GroupMemberSearchViewController)
}

class GroupMemberSearchViewController: OWSViewController {

    private enum FilterMode {
        case all
        case admins
        case contacts
    }

    private enum Section: Hashable {
        case members(collationIndex: Int)
        case searchResults
        case empty
        case actions
    }

    private enum Item: Hashable {
        case member(Aci)
        case empty
        case addMembers
        case shareGroupLink
    }

    private struct Member {
        let aci: Aci
        let comparableName: ComparableDisplayName
    }

    private let db = DependenciesBridge.shared.db
    private let contactManager = SSKEnvironment.shared.contactManagerImplRef
    private let identityManager = DependenciesBridge.shared.identityManager

    private let groupModel: TSGroupModelV2
    private let thread: TSThread
    private let groupViewHelper: GroupViewHelper
    private let spoilerState: SpoilerRenderState
    private let canEditConversationMembership: Bool
    private let isTerminatedGroup: Bool
    private weak var memberSearchDelegate: GroupMemberSearchViewControllerDelegate?

    private var allMembers = [Member]()
    private var adminAcis = Set<Aci>()
    private var systemContactAcis = Set<Aci>()
    private var verificationStateMap = [Aci: VerificationState]()

    private var filterMode: FilterMode = .all {
        didSet {
            updateContents(animated: true)
            updateNavigationItems()
        }
    }

    private let collation = UILocalizedIndexedCollation.current()

    private static let headerReuseIdentifier = "memberSectionHeader"
    private static let emptyCellReuseIdentifier = "emptyCell"

    private static let searchResultsSectionTitle = OWSLocalizedString(
        "GROUP_MEMBER_SEARCH_RESULTS_SECTION_TITLE",
        comment: "Section header shown above the results in the group member search sheet.",
    )

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private lazy var dataSource = OWSTableViewDiffableDataSource<Section, Item>(tableView: tableView) { [weak self] _, indexPath, item in
        guard let self else { return UITableViewCell() }
        let cell: UITableViewCell
        switch item {
        case .member(let aci):
            cell = self.memberCell(for: aci, at: indexPath)
        case .empty:
            cell = self.emptyListCell(at: indexPath)
        case .addMembers:
            cell = self.actionCell(
                icon: .groupInfoAddMembers,
                title: OWSLocalizedString(
                    "CONVERSATION_SETTINGS_ADD_MEMBERS",
                    comment: "Label for 'add members' button in conversation settings view.",
                ),
            )
        case .shareGroupLink:
            cell = self.actionCell(
                icon: .groupInfoGroupLink,
                title: OWSLocalizedString(
                    "GROUP_MEMBER_SEARCH_INVITE_VIA_GROUP_LINK",
                    comment: "Label for the 'invite via group link' button in the group member search sheet.",
                ),
            )
        }

        cell.backgroundColor = UIColor.Signal.secondaryGroupedBackground
        let selectedBackgroundView = UIView()
        selectedBackgroundView.backgroundColor = Theme.tableCell2SelectedBackgroundColor
        cell.selectedBackgroundView = selectedBackgroundView

        return cell
    }

    private let searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.obscuresBackgroundDuringPresentation = false
        controller.hidesNavigationBarDuringPresentation = false
        controller.searchBar.placeholder = OWSLocalizedString(
            "GROUP_MEMBER_SEARCH_SEARCH_BAR_PLACEHOLDER",
            comment: "Placeholder text for the search bar in the group member search sheet.",
        )
        return controller
    }()

    private var searchText: String {
        searchController.searchBar.text?.stripped ?? ""
    }

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    init(
        groupModel: TSGroupModelV2,
        thread: TSThread,
        groupViewHelper: GroupViewHelper,
        spoilerState: SpoilerRenderState,
        canEditConversationMembership: Bool,
        isTerminatedGroup: Bool,
        delegate: GroupMemberSearchViewControllerDelegate,
    ) {
        self.groupModel = groupModel
        self.thread = thread
        self.groupViewHelper = groupViewHelper
        self.spoilerState = spoilerState
        self.canEditConversationMembership = canEditConversationMembership
        self.isTerminatedGroup = isTerminatedGroup
        self.memberSearchDelegate = delegate
        super.init()
    }

    // MARK: - View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.Signal.groupedBackground
        tableView.backgroundColor = UIColor.Signal.groupedBackground
        tableView.sectionIndexColor = UIColor.Signal.label

        tableView.register(ContactTableViewCell.self)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.emptyCellReuseIdentifier)
        tableView.register(UITableViewHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: Self.headerReuseIdentifier)
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.separatorInset = UIEdgeInsets(
            top: 0,
            leading: OWSTableViewController2.cellHInnerMargin
                + CGFloat(AvatarBuilder.smallAvatarSizePoints)
                + ContactCellView.avatarTextHSpacing,
            bottom: 0,
            trailing: 0,
        )

        view.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()

        title = OWSLocalizedString(
            "GROUP_MEMBERS_SECTION_TITLE_MEMBERS",
            comment: "Title for the 'members' section of the 'group members' view.",
        )

        navigationItem.leftBarButtonItem = .closeButton { [weak self] in
            self?.dismiss(animated: true)
        }

        searchController.searchResultsUpdater = self
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        dataSource.sectionIndexTitlesProvider = { [weak self] in
            guard let self, !self.isSearching else { return nil }
            return self.collation.sectionTitles
        }
        dataSource.sectionForSectionIndexTitleProvider = { [weak self] _, index in
            guard let self else { return 0 }
            let targetBucket = self.collation.section(forSectionIndexTitle: index)
            var lastMembersSection = 0
            for (sectionIndex, section) in self.dataSource.snapshot().sectionIdentifiers.enumerated() {
                guard case .members(let bucket) = section else { continue }
                if bucket >= targetBucket { return sectionIndex }
                lastMembersSection = sectionIndex
            }
            return lastMembersSection
        }

        loadMembers()
        updateNavigationItems()
        updateContents(animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        DispatchQueue.main.async {
            self.searchController.isActive = true
            self.searchController.searchBar.becomeFirstResponder()
        }
    }

    override func contentSizeCategoryDidChange() {
        super.contentSizeCategoryDidChange()
        tableView.reloadData()
    }

    // TODO: Eventually update ContactTableViewCell to use dynamic colors and remove this
    override func themeDidChange() {
        super.themeDidChange()
        tableView.reloadData()
    }

    private func loadMembers() {
        let groupMembership = groupModel.groupMembership
        self.adminAcis = Set(groupMembership.fullMemberAdministrators.compactMap(\.aci))

        allMembers = db.read { tx in
            contactManager.sortedComparableNames(
                for: groupMembership.fullMembers,
                tx: tx,
            ).compactMap { comparableName in
                guard let aci = comparableName.address.aci else { return nil }
                verificationStateMap[aci] = identityManager.verificationState(for: comparableName.address, tx: tx)
                if contactManager.fetchSignalAccount(for: comparableName.address, transaction: tx) != nil {
                    systemContactAcis.insert(aci)
                }
                return Member(aci: aci, comparableName: comparableName)
            }
        }
    }

    // MARK: - Navigation items

    private func updateNavigationItems() {
        let isFiltering = filterMode != .all

        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(systemName: "line.3.horizontal.decrease")?
            .withTintColor(
                isFiltering ? .white : .Signal.label,
                renderingMode: .alwaysOriginal,
            )
        configuration.baseBackgroundColor = isFiltering ? .Signal.ultramarine : .clear
        configuration.cornerStyle = .capsule

        let filterButton = UIButton(configuration: configuration)
        filterButton.menu = buildFilterMenu()
        filterButton.showsMenuAsPrimaryAction = true
        filterButton.accessibilityLabel = OWSLocalizedString(
            "GROUP_MEMBER_SEARCH_FILTER_ACCESSIBILITY_LABEL",
            comment: "Accessibility label for the filter button in the group member search sheet.",
        )

        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: filterButton)
    }

    private func buildFilterMenu() -> UIMenu {
        func action(_ mode: FilterMode, title: String, image: UIImage?) -> UIAction {
            UIAction(title: title, image: image, state: filterMode == mode ? .on : .off) { [weak self] _ in
                self?.filterMode = mode
            }
        }

        let allAction = action(
            .all,
            title: OWSLocalizedString(
                "GROUP_MEMBER_SEARCH_FILTER_ALL",
                comment: "Title for the filter option that shows all members in the group member search sheet.",
            ),
            image: UIImage(resource: .group),
        )
        let adminsAction = action(
            .admins,
            title: OWSLocalizedString(
                "GROUP_MEMBER_SEARCH_FILTER_ADMINS",
                comment: "Title for the filter option that shows only admins in the group member search sheet.",
            ),
            image: UIImage(resource: .key),
        )
        let contactsAction = action(
            .contacts,
            title: OWSLocalizedString(
                "GROUP_MEMBER_SEARCH_FILTER_CONTACTS",
                comment: "Title for the filter option that shows only members who are in the user's system contacts, in the group member search sheet.",
            ),
            image: UIImage(resource: .personCircle),
        )

        return UIMenu(
            title: OWSLocalizedString(
                "GROUP_MEMBER_SEARCH_FILTER_MENU_TITLE",
                comment: "Title for the filter menu in the group member search sheet.",
            ),
            children: [
                UIMenu(options: .displayInline, children: [allAction]),
                UIMenu(options: .displayInline, children: [adminsAction, contactsAction]),
            ],
        )
    }

    // MARK: - Contents

    private func updateContents(animated: Bool) {
        dataSource.apply(buildSnapshot(), animatingDifferences: animated) { [weak self] in
            self?.tableView.reloadSectionIndexTitles()
        }
    }

    private func buildSnapshot() -> NSDiffableDataSourceSnapshot<Section, Item> {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        let members = allMembers.filter { member in
            switch filterMode {
            case .all:
                break
            case .admins:
                if !adminAcis.contains(member.aci) { return false }
            case .contacts:
                if !systemContactAcis.contains(member.aci) { return false }
            }
            return searchText.isEmpty || member.comparableName.resolvedValue().localizedCaseInsensitiveContains(searchText)
        }

        if isSearching {
            if members.isEmpty {
                snapshot.appendSections([.empty])
                snapshot.appendItems([.empty], toSection: .empty)
            } else {
                snapshot.appendSections([.searchResults])
                snapshot.appendItems(members.map { .member($0.aci) }, toSection: .searchResults)
            }
        } else {
            // Alphabetical buckets
            var collatedMembers = collation.sectionTitles.map { _ in [Aci]() }
            for member in members {
                let bucket = collation.section(
                    for: CollatableComparableDisplayName(member.comparableName),
                    collationStringSelector: #selector(CollatableComparableDisplayName.collationString),
                )
                // `section(for:)` returns a negative value if the name doesn't collate
                // into any section; skip those defensively (matches RecipientPicker).
                guard bucket >= 0 else { continue }
                collatedMembers[bucket].append(member.aci)
            }
            for (index, acis) in collatedMembers.enumerated() where !acis.isEmpty {
                snapshot.appendSections([.members(collationIndex: index)])
                snapshot.appendItems(acis.map { .member($0) }, toSection: .members(collationIndex: index))
            }
            if members.isEmpty {
                snapshot.appendSections([.empty])
                snapshot.appendItems([.empty], toSection: .empty)
            }
        }

        var actionItems = [Item]()
        if canEditConversationMembership, !isTerminatedGroup {
            actionItems.append(.addMembers)
        }
        if case .enabled = groupModel.inviteLinkConfiguration() {
            actionItems.append(.shareGroupLink)
        }
        if !actionItems.isEmpty {
            snapshot.appendSections([.actions])
            snapshot.appendItems(actionItems, toSection: .actions)
        }

        // Reload search term in empty list cell
        if
            snapshot.itemIdentifiers.contains(.empty),
            dataSource.snapshot().itemIdentifiers.contains(.empty)
        {
            snapshot.reconfigureItems([.empty])
        }

        return snapshot
    }

    // MARK: - Cells

    private func memberCell(for aci: Aci, at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(ContactTableViewCell.self, for: indexPath)
        let address = SignalServiceAddress(aci)
        db.read { tx in
            let configuration = ContactCellView.Configuration.groupMember(
                address: address,
                groupMembership: groupModel.groupMembership,
                verificationState: verificationStateMap[aci] ?? .implicit(isAcknowledged: false),
                memberLabel: memberLabelForRendering(for: aci),
                showAddMemberLabel: false,
                tx: tx,
            )
            cell.configure(configuration: configuration, transaction: tx)
        }
        return cell
    }

    private func emptyListCell(at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: Self.emptyCellReuseIdentifier,
            for: indexPath,
        )
        var configuration = UIListContentConfiguration.cell()
        if isSearching {
            configuration.text = String(
                format: OWSLocalizedString(
                    "GROUP_MEMBER_SEARCH_NO_RESULTS_FORMAT",
                    comment: "Message shown when a group member search returns no results. Embeds {{ the search query }}.",
                ),
                searchText,
            )
        } else {
            configuration.text = OWSLocalizedString(
                "SETTINGS_BLOCK_LIST_NO_SEARCH_RESULTS",
                comment: "A label that indicates the user's search has no matching results.",
            )
        }
        configuration.textProperties.alignment = .natural
        configuration.textProperties.color = UIColor.Signal.secondaryLabel
        configuration.textProperties.font = OWSTableItem.primaryLabelFont
        cell.contentConfiguration = configuration
        cell.isUserInteractionEnabled = false
        cell.selectionStyle = .none
        return cell
    }

    private func actionCell(
        icon: ThemeIcon,
        title: String,
    ) -> UITableViewCell {
        let cell = UITableViewCell()
        cell.preservesSuperviewLayoutMargins = true
        cell.contentView.preservesSuperviewLayoutMargins = true

        let iconView = OWSTableItem.buildIconInCircleView(
            icon: icon,
            iconSize: AvatarBuilder.smallAvatarSizePoints,
            innerIconSize: 20,
            iconTintColor: UIColor.Signal.label,
        )

        let rowLabel = UILabel()
        rowLabel.text = title
        rowLabel.textColor = UIColor.Signal.label
        rowLabel.font = OWSTableItem.primaryLabelFont
        rowLabel.lineBreakMode = .byTruncatingTail

        let contentRow = UIStackView(arrangedSubviews: [iconView, rowLabel])
        contentRow.spacing = ContactCellView.avatarTextHSpacing

        cell.contentView.addSubview(contentRow)
        contentRow.autoPinWidthToSuperviewMargins()
        contentRow.autoPinHeightToSuperview(withMargin: 7)

        return cell
    }

    // MARK: - Member selection

    private func memberLabelForRendering(for aci: Aci) -> MemberLabelForRendering? {
        guard
            let groupThread = thread as? TSGroupThread,
            let memberLabelString = groupModel.groupMembership.memberLabel(for: aci)?.labelForRendering()
        else {
            return nil
        }
        let groupNameColors = GroupNameColors.forThread(groupThread)
        return MemberLabelForRendering(
            label: memberLabelString,
            groupNameColor: groupNameColors.color(for: aci),
        )
    }

    private func didSelectMember(_ aci: Aci) {
        ProfileSheetSheetCoordinator(
            address: SignalServiceAddress(aci),
            groupViewHelper: groupViewHelper,
            spoilerState: spoilerState,
            memberLabel: memberLabelForRendering(for: aci),
        )
        .presentAppropriateSheet(from: self)
    }
}

// MARK: - UITableViewDelegate

extension GroupMemberSearchViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .member(let aci):
            didSelectMember(aci)
        case .addMembers:
            memberSearchDelegate?.groupMemberSearchViewControllerRequestAddMembers(self)
        case .shareGroupLink:
            memberSearchDelegate?.groupMemberSearchViewControllerRequestShareGroupLink(self)
        case .empty:
            break
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Re-evaluate the navbar style as the scroll edge changes so it stays solid
        // (matching the grouped background) at the top and blurs once scrolled.
        guard lifecycle == .appeared else { return }
        owsNavigationController?.updateNavbarAppearance(animated: true)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerTitle: String?
        switch dataSource.sectionIdentifier(for: section) {
        case .members(let collationIndex):
            headerTitle = collation.sectionTitles[collationIndex].uppercased()
        case .searchResults:
            headerTitle = Self.searchResultsSectionTitle
        case .empty where isSearching:
            headerTitle = Self.searchResultsSectionTitle
        case .empty, .actions, nil:
            headerTitle = nil
        }

        guard
            let headerTitle,
            let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: Self.headerReuseIdentifier)
        else {
            return nil
        }
        var configuration = UIListContentConfiguration.groupedHeader()
        configuration.text = headerTitle
        configuration.textProperties.font = .dynamicTypeHeadlineClamped
        configuration.textProperties.color = UIColor.Signal.label
        header.contentConfiguration = configuration
        return header
    }
}

// MARK: - UISearchResultsUpdating

extension GroupMemberSearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        updateContents(animated: false)
    }
}

// MARK: - OWSNavigationChildController

extension GroupMemberSearchViewController: OWSNavigationChildController {

    private var usesSolidNavbarStyle: Bool {
        tableView.contentOffset.y <= -tableView.adjustedContentInset.top
    }

    var preferredNavigationBarStyle: OWSNavigationBarStyle {
        usesSolidNavbarStyle ? .solid : .blur
    }

    var navbarBackgroundColorOverride: UIColor? {
        usesSolidNavbarStyle ? UIColor.Signal.groupedBackground : nil
    }
}

// MARK: - ContactCellView

extension ContactCellView.Configuration {
    static func groupMember(
        address: SignalServiceAddress,
        groupMembership: GroupMembership,
        verificationState: VerificationState,
        memberLabel: MemberLabelForRendering?,
        showAddMemberLabel: Bool,
        tx: DBReadTransaction,
    ) -> ContactCellView.Configuration {
        var configuration = ContactCellView.Configuration(address: address, localUserDisplayMode: .asLocalUser)

        let isGroupAdmin = groupMembership.isFullMemberAndAdministrator(address)
        let isVerified = verificationState == .verified
        let isNoLongerVerified = verificationState == .noLongerVerified
        let isBlocked = SSKEnvironment.shared.blockingManagerRef.isAddressBlocked(address, transaction: tx)
        if isGroupAdmin {
            configuration.accessoryMessage = OWSLocalizedString(
                "GROUP_MEMBER_ADMIN_INDICATOR",
                comment: "Label indicating that a group member is an admin.",
            )
        } else if isNoLongerVerified {
            configuration.accessoryMessage = OWSLocalizedString(
                "CONTACT_CELL_IS_NO_LONGER_VERIFIED",
                comment: "An indicator that a contact is no longer verified.",
            )
        } else if isBlocked {
            configuration.accessoryMessage = MessageStrings.conversationIsBlocked
        }

        if let memberLabel {
            configuration.memberLabel = memberLabel
        }

        if showAddMemberLabel {
            configuration.attributedSubtitle = NSAttributedString(
                string: OWSLocalizedString(
                    "MEMBER_LABEL_ADD_CSVC",
                    comment: "Label that shows up under a local user's row in contacts prompting them to add a member label",
                ),
                attributes: [.font: UIFont.dynamicTypeCaption1Clamped.medium()],
            ) + SignalSymbol.chevronRight.attributedString(
                dynamicTypeBaseSize: 10,
                weight: .bold,
                leadingCharacter: .space,
                attributes: [.foregroundColor: UIColor.Signal.secondaryLabel],
            )
        } else if isVerified {
            configuration.useVerifiedSubtitle()
        } else if
            !address.isLocalAddress,
            let bioForDisplay = SSKEnvironment.shared.profileManagerImplRef.userProfile(for: address, tx: tx)?.bioForDisplay
        {
            configuration.attributedSubtitle = NSAttributedString(string: bioForDisplay)
        } else {
            owsAssertDebug(configuration.attributedSubtitle == nil)
        }

        configuration.shouldShowContactIcon = SSKEnvironment.shared.contactManagerRef.fetchSignalAccount(for: address, transaction: tx) != nil

        return configuration
    }
}
