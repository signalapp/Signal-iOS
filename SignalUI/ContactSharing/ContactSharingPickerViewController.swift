//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
public import SignalServiceKit
import SwiftUI
import UIKit

public class ContactSharingPickerViewController: OWSTableViewController2, UISearchResultsUpdating, UITextViewDelegate {

    public weak var contactSharingDelegate: (any ContactSharingPickerDelegate)?

    private typealias ContactsAccessPrompt = ContactSharingPickerViewModel.ContactsAccessPrompt
    private typealias Row = ContactSharingPickerViewModel.Row

    private enum CachedAvatar {
        case image(UIImage)
        case noImage

        var image: UIImage? {
            switch self {
            case .image(let image): image
            case .noImage: nil
            }
        }
    }

    private let viewModel = ContactSharingPickerViewModel()
    private let collation = UILocalizedIndexedCollation.current()
    private var cancellables = Set<AnyCancellable>()

    private lazy var searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.obscuresBackgroundDuringPresentation = false
        controller.hidesNavigationBarDuringPresentation = false
        controller.searchResultsUpdater = self
        controller.searchBar.placeholder = OWSLocalizedString(
            "SELECT_CONTACT_FOR_SHARING_SEARCH_BAR_PLACEHOLDER",
            comment: "Placeholder text for the search bar on the 'Select Contact' view",
        )
        return controller
    }()

    private enum EmptyState {
        case noContacts
        case noContactsWithAccessDenied
        case noContactsWithAccessRestricted
        case noSearchResults

        var title: String {
            switch self {
            case .noContacts, .noContactsWithAccessDenied, .noContactsWithAccessRestricted:
                OWSLocalizedString(
                    "SELECT_CONTACT_FOR_SHARING_NO_CONTACTS_TITLE",
                    comment: "Title shown on the 'Select Contact' view when the user has no contacts.",
                )
            case .noSearchResults:
                OWSLocalizedString(
                    "SELECT_CONTACT_FOR_SHARING_NO_SEARCH_RESULTS_TITLE",
                    comment: "Title shown on the 'Select Contact' view when no contacts match the user's search.",
                )
            }
        }

        var subtitle: NSAttributedString? {
            let font = UIFont.dynamicTypeBodyClamped
            let color = UIColor.Signal.secondaryLabel
            switch self {
            case .noContacts:
                return OWSLocalizedString(
                    "SELECT_CONTACT_FOR_SHARING_NO_CONTACTS_SUBTITLE",
                    comment: "Subtitle shown on the 'Select Contact' view when the user has no contacts.",
                ).styled(with: .font(font), .color(color), .alignment(.center))
            case .noContactsWithAccessDenied:
                return ContactSharingPickerViewController.allowAccessInSettingsText
                    .styled(with: .font(font), .color(color), .alignment(.center))
            case .noContactsWithAccessRestricted:
                return ContactSharingPickerViewController.accessRestrictedText
                    .styled(with: .font(font), .color(color), .alignment(.center))
            case .noSearchResults:
                return nil
            }
        }

        var showsLearnMoreButton: Bool {
            switch self {
            case .noContactsWithAccessDenied: true
            case .noContacts, .noContactsWithAccessRestricted, .noSearchResults: false
            }
        }
    }

    private let emptyStateTitleLabel: UILabel = {
        let label = UILabel.explanationTextLabel(text: "")
        label.font = .dynamicTypeTitle3.semibold()
        label.adjustsFontForContentSizeCategory = true
        return label
    }()

    private lazy var emptyStateSubtitleTextView: LinkingTextView = {
        let textView = LinkingTextView { [weak self] url in
            self?.didTapLink(url)
            return false
        }
        textView.linkTextAttributes = [.foregroundColor: UIColor.Signal.label]
        return textView
    }()

    private lazy var emptyStateLearnMoreButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.title = CommonStrings.learnMore
        configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeBodyClamped.semibold())
        configuration.baseForegroundColor = .Signal.label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        return UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.presentContactAccessDeniedSheet()
        })
    }()

    private lazy var emptyStateLearnMoreButtonContainer: UIView = {
        let container = UIView.container()
        container.addSubview(emptyStateLearnMoreButton)
        emptyStateLearnMoreButton.autoPinHeightToSuperview()
        emptyStateLearnMoreButton.autoHCenterInSuperview()
        emptyStateLearnMoreButton.autoPinEdge(toSuperviewEdge: .leading, relation: .greaterThanOrEqual)
        return container
    }()

    private lazy var emptyStateMessageView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [
            emptyStateTitleLabel,
            emptyStateSubtitleTextView,
            emptyStateLearnMoreButtonContainer,
        ])
        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.setCustomSpacing(0, after: emptyStateSubtitleTextView)
        return stackView
    }()

    private lazy var emptyStateView: UIView = {
        let scrollView = UIScrollView()
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.preservesSuperviewLayoutMargins = true

        let contentView = UIView.container()
        contentView.preservesSuperviewLayoutMargins = true
        scrollView.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let containerView = UIView.container()
        containerView.preservesSuperviewLayoutMargins = true
        containerView.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: containerView.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.keyboardLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        contentView.addSubview(emptyStateMessageView)
        emptyStateMessageView.translatesAutoresizingMaskIntoConstraints = false
        let centerYConstraint = emptyStateMessageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        centerYConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            emptyStateMessageView.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            emptyStateMessageView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.layoutMarginsGuide.bottomAnchor),
            emptyStateMessageView.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            emptyStateMessageView.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            centerYConstraint,
        ])

        containerView.isHidden = true
        return containerView
    }()

    private lazy var limitedContactsAccessCell: UITableViewCell = {
        let cell = ContactAccessLimitedReminderTableViewCell()
        if #available(iOS 18, *) {
            cell.contentConfiguration = UIHostingConfiguration {
                ContactAccessLimitedReminderView { [weak self] in
                    Task { await self?.viewModel.reloadAfterLimitedContactsAccessChange() }
                }
            }
        }
        return cell
    }()

    private var cachedAvatars = [Row.Identity: CachedAvatar]()
    private var displayedRows: ContactSharingPickerViewModel.DisplayedRows?

    override public func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "SELECT_CONTACT_FOR_SHARING_VIEW_TITLE",
            comment: "Title for the 'Select Contact' view",
        )

        navigationItem.leftBarButtonItem = .cancelButton { [weak self] in
            guard let self else { return }
            self.contactSharingDelegate?.contactSharingPickerDidCancel(self)
        }

        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        defaultSeparatorInsetLeading = Self.cellHInnerMargin
            + ContactSharingRowCell.avatarDiameter
            + ContactSharingRowCell.avatarTextSpacing

        tableView.register(ContactSharingRowCell.self, forCellReuseIdentifier: ContactSharingRowCell.reuseIdentifier)
        tableView.backgroundView = emptyStateView

        viewModel.loadData()

        viewModel.displayedRowsPublisher
            .sink { [weak self] displayedRows in
                self?.updateTableContents(displayedRows: displayedRows)
            }
            .store(in: &cancellables)
    }

    override public func contentSizeCategoryDidChange() {
        super.contentSizeCategoryDidChange()

        if let displayedRows {
            updateTableContents(displayedRows: displayedRows)
        }
    }

    private func updateTableContents(displayedRows: ContactSharingPickerViewModel.DisplayedRows) {
        self.displayedRows = displayedRows

        let contents = OWSTableContents()
        defer { self.contents = contents }

        let rows = displayedRows.rows

        let emptyState: EmptyState? = switch (rows.isEmpty, displayedRows.isSearching, displayedRows.contactsAccessPrompt) {
        case (false, _, _): nil
        case (true, true, _): .noSearchResults
        case (true, false, .allowAccessInSettings): .noContactsWithAccessDenied
        case (true, false, .explainRestrictedAccess): .noContactsWithAccessRestricted
        case (true, false, .manageLimitedAccess), (true, false, nil): .noContacts
        }
        showEmptyState(emptyState)
        showSearchBar(!rows.isEmpty || displayedRows.isSearching)

        if let section = contactsAccessPromptSection(prompt: displayedRows.contactsAccessPrompt) {
            contents.add(section)
        }

        guard !rows.isEmpty else {
            return
        }

        guard !displayedRows.isSearching else {
            contents.add(OWSTableSection(items: rows.map(item(for:))))
            return
        }

        let collatedSectionOffset = contents.sections.count
        contents.add(sections: collatedSections(for: rows))

        switch displayedRows.contactsAccessPrompt {
        case .allowAccessInSettings:
            contents.add(allowAccessInSettingsSection())
        case .explainRestrictedAccess:
            contents.add(OWSTableSection(title: nil, items: [], footerTitle: Self.accessRestrictedText))
        case .manageLimitedAccess, nil:
            break
        }

        contents.sectionForSectionIndexTitleBlock = { [weak contents, weak self] _, index in
            guard let self, let contents else { return 0 }
            let sectionIndex = self.collation.section(forSectionIndexTitle: index) + collatedSectionOffset
            guard sectionIndex >= collatedSectionOffset, sectionIndex < contents.sections.count else {
                return 0
            }
            return sectionIndex
        }
        contents.sectionIndexTitlesForTableViewBlock = { [weak self] in
            self?.collation.sectionTitles ?? []
        }
    }

    private func collatedSections(for rows: [Row]) -> [OWSTableSection] {
        var collatedRows = collation.sectionTitles.map { _ in [Row]() }

        for row in rows {
            let section = row.collationSection(in: collation)
            guard section >= 0, section < collatedRows.count else {
                continue
            }
            collatedRows[section].append(row)
        }

        return collatedRows.enumerated().map { index, sectionRows in
            guard !sectionRows.isEmpty else {
                return OWSTableSection()
            }
            return OWSTableSection(
                title: collation.sectionTitles[index].uppercased(),
                items: sectionRows.map(item(for:)),
            )
        }
    }

    private func item(for row: Row) -> OWSTableItem {
        OWSTableItem(
            dequeueCellBlock: { [weak self] tableView in
                guard let cell = tableView.dequeueReusableCell(ContactSharingRowCell.self) else {
                    return UITableViewCell()
                }
                cell.configure(
                    avatarImage: self?.avatarImage(for: row),
                    displayName: row.displayName,
                    shouldShowContactIcon: row.shouldShowContactIcon,
                )
                return cell
            },
            actionBlock: { [weak self] in
                self?.didSelect(row: row)
            },
        )
    }

    private func didSelect(row: Row) {
        guard navigationController?.topViewController === self else {
            // Only push the next view controller if we are still the main
            // view controller on screen.
            return
        }

        contactSharingDelegate?.contactSharingPicker(
            self,
            didSelect: viewModel.contactShareDraft(forRow: row),
        )
    }

    private func contactsAccessPromptSection(prompt: ContactsAccessPrompt?) -> OWSTableSection? {
        switch prompt {
        case .manageLimitedAccess:
            limitedContactsAccessSection()
        case .allowAccessInSettings, .explainRestrictedAccess, nil:
            nil
        }
    }

    private func allowAccessInSettingsSection() -> OWSTableSection {
        let section = OWSTableSection()
        section.footerAttributedTitle = NSAttributedString.composed(of: [
            Self.allowAccessInSettingsText,
            " ",
            CommonStrings.learnMore.styled(with: .link(Constants.learnMoreURL), .font(Self.defaultFooterFont.semibold())),
        ]).styled(with: .font(Self.defaultFooterFont), .color(Self.defaultFooterTextColor))
        section.footerTextViewDelegate = self
        return section
    }

    private static var accessRestrictedText: String {
        OWSLocalizedString(
            "SELECT_CONTACT_FOR_SHARING_ACCESS_RESTRICTED",
            comment: "Shown on the 'Select Contact' view when access to the user's contacts is restricted, for example by Screen Time or device management.",
        )
    }

    private static var allowAccessInSettingsText: String {
        OWSLocalizedString(
            "SELECT_CONTACT_FOR_SHARING_ALLOW_ACCESS_IN_SETTINGS_FOOTER",
            comment: "Shown on the 'Select Contact' view when the user has denied access to their contacts. Followed by a 'Learn More' link.",
        )
    }

    private func presentContactAccessDeniedSheet() {
        ContactsViewHelper.presentContactReadAccessDeniedAlert(purpose: .share, viewController: self)
    }

    private func limitedContactsAccessSection() -> OWSTableSection? {
        guard #available(iOS 18, *) else {
            return nil
        }
        return OWSTableSection(items: [
            OWSTableItem(customCellBlock: { [weak self] in
                self?.limitedContactsAccessCell ?? UITableViewCell()
            }),
        ])
    }

    private func didTapLink(_ url: URL) {
        switch url {
        case Constants.learnMoreURL:
            presentContactAccessDeniedSheet()
        default:
            break
        }
    }

    private func showEmptyState(_ emptyState: EmptyState?) {
        emptyStateView.isHidden = emptyState == nil

        emptyStateTitleLabel.text = emptyState?.title
        let subtitle = emptyState?.subtitle
        emptyStateSubtitleTextView.attributedText = subtitle
        emptyStateSubtitleTextView.isHidden = subtitle == nil
        emptyStateLearnMoreButtonContainer.isHidden = !(emptyState?.showsLearnMoreButton ?? false)
        tableView.isScrollEnabled = emptyState == nil
    }

    private func showSearchBar(_ showsSearchBar: Bool) {
        let searchController = showsSearchBar ? self.searchController : nil
        if navigationItem.searchController !== searchController {
            navigationItem.searchController = searchController
        }
    }

    private func avatarImage(for row: Row) -> UIImage? {
        if let cachedAvatar = cachedAvatars[row.identity] {
            return cachedAvatar.image
        }

        let avatarImage = viewModel.avatarImage(for: row, diameterPoints: AvatarBuilder.smallAvatarSizePoints)

        cachedAvatars[row.identity] = avatarImage.map { .image($0) } ?? .noImage
        return avatarImage
    }

    private enum Constants {
        static let learnMoreURL = URL(string: "https://support.signal.org/")!
    }

    // MARK: - UITextViewDelegate

    public func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction,
    ) -> Bool {
        guard interaction == .invokeDefaultAction else {
            return false
        }
        didTapLink(URL)
        return false
    }

    // MARK: - UISearchResultsUpdating

    public func updateSearchResults(for searchController: UISearchController) {
        viewModel.setSearchText(searchController.searchBar.text?.stripped ?? "")
    }
}
