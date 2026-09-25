//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Combine
public import SignalServiceKit
import UIKit

public class ContactSharingPickerViewController: OWSTableViewController2, UISearchResultsUpdating {

    public weak var contactSharingDelegate: (any ContactSharingPickerDelegate)?

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

    private var cachedAvatars = [Row.Identity: CachedAvatar]()

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

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        defaultSeparatorInsetLeading = Self.cellHInnerMargin
            + ContactSharingRowCell.avatarDiameter
            + ContactSharingRowCell.avatarTextSpacing

        tableView.register(ContactSharingRowCell.self, forCellReuseIdentifier: ContactSharingRowCell.reuseIdentifier)

        viewModel.loadData()

        viewModel.displayedRowsPublisher
            .sink { [weak self] displayedRows in
                self?.updateTableContents(displayedRows: displayedRows)
            }
            .store(in: &cancellables)
    }

    private func updateTableContents(displayedRows: ContactSharingPickerViewModel.DisplayedRows) {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        let rows = displayedRows.rows

        guard !rows.isEmpty else {
            contents.add(emptySection(isSearching: displayedRows.isSearching))
            return
        }

        guard !displayedRows.isSearching else {
            contents.add(OWSTableSection(items: rows.map(item(for:))))
            return
        }

        contents.add(sections: collatedSections(for: rows))

        contents.sectionForSectionIndexTitleBlock = { [weak contents, weak self] _, index in
            guard let self, let contents else { return 0 }
            let sectionIndex = self.collation.section(forSectionIndexTitle: index)
            guard sectionIndex >= 0, sectionIndex < contents.sections.count else {
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

    private func emptySection(isSearching: Bool) -> OWSTableSection {
        guard !isSearching else {
            return OWSTableSection(items: [
                OWSTableItem.softCenterLabel(withText: OWSLocalizedString(
                    "SETTINGS_BLOCK_LIST_NO_SEARCH_RESULTS",
                    comment: "A label that indicates the user's search has no matching results.",
                )),
            ])
        }

        switch SSKEnvironment.shared.contactManagerImplRef.sharingAuthorization {
        case .denied, .notDetermined:
            return OWSTableSection()
        case .authorized:
            return OWSTableSection(items: [
                OWSTableItem.softCenterLabel(withText: OWSLocalizedString(
                    "SETTINGS_BLOCK_LIST_NO_CONTACTS",
                    comment: "A label that indicates the user has no Signal contacts that they haven't blocked.",
                )),
            ])
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

    // MARK: - UISearchResultsUpdating

    public func updateSearchResults(for searchController: UISearchController) {
        viewModel.setSearchText(searchController.searchBar.text?.stripped ?? "")
    }
}
