//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class ChatFoldersSettingsViewController:
    OWSViewController,
    OWSNavigationChildController,
    UITableViewDelegate,
    DatabaseChangeDelegate
{

    // MARK: - Helper types

    private enum Section: Hashable {
        case folders
        case suggestedFolders
    }

    private enum Row: Hashable {
        case createFolder
        case folder(chatFolderId: UUID)
        case suggestedFolder(SuggestedChatFolder)
    }

    /// What a folder's row shows.
    private struct FolderRow: Equatable {
        let chatFolderId: UUID
        let symbol: SignalSymbol
        let name: String
        let subtitle: String?
        let isAllChats: Bool
    }

    // MARK: - Properties

    private var db: any DB { DependenciesBridge.shared.db }
    private var chatFolderManager: ChatFolderManager { DependenciesBridge.shared.chatFolderManager }
    private var databaseChangeObserver: DatabaseChangeObserver { DependenciesBridge.shared.databaseChangeObserver }

    private var folderRows: [FolderRow] = [] {
        didSet {
            folderRowsById = Dictionary(
                folderRows.map { ($0.chatFolderId, $0) },
                uniquingKeysWith: { first, _ in first },
            )
        }
    }

    private var folderRowsById: [UUID: FolderRow] = [:]
    private var suggestedFolders: [SuggestedChatFolder] = []

    // MARK: - OWSNavigationChildController

    var navbarBackgroundColorOverride: UIColor? {
        .Signal.groupedBackground
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        OWSTableViewController2.removeBackButtonText(viewController: self)
        title = OWSLocalizedString(
            "CHAT_FOLDERS_SETTINGS_TITLE",
            comment: "Title for the chat folders settings screen.",
        )

        view.backgroundColor = .Signal.groupedBackground
        view.addSubview(tableView)
        tableView.autoPinEdgesToSuperviewEdges()

        databaseChangeObserver.appendDatabaseChangeDelegate(self)

        reloadFolders(animated: false)
    }

    // MARK: - Views

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.delegate = self
        tableView.preservesSuperviewLayoutMargins = true
        tableView.isEditing = true
        tableView.allowsSelectionDuringEditing = true
        tableView.rowHeight = UITableView.automaticDimension
        tableView.backgroundColor = .Signal.groupedBackground
        tableView.register(ChatFolderTableViewCell.self)
        return tableView
    }()

    private lazy var dataSource: OWSTableViewDiffableDataSource<Section, Row> = {
        let dataSource = OWSTableViewDiffableDataSource<Section, Row>(
            tableView: tableView,
        ) { [weak self] tableView, indexPath, row in
            guard let self else { return UITableViewCell() }
            let cell = tableView.dequeueReusableCell(ChatFolderTableViewCell.self, for: indexPath)

            switch row {
            case .createFolder:
                cell.configure(
                    symbol: .plus,
                    title: OWSLocalizedString(
                        "CHAT_FOLDERS_SETTINGS_CREATE_FOLDER",
                        comment: "Button in chat folder settings to create a new chat folder.",
                    ),
                )
            case .folder(let chatFolderId):
                guard let folderRow = folderRowsById[chatFolderId] else {
                    owsFailDebug("Missing folder for row!")
                    return UITableViewCell()
                }
                cell.configure(symbol: folderRow.symbol, title: folderRow.name, subtitle: folderRow.subtitle)
            case .suggestedFolder(let suggestedFolder):
                cell.configure(
                    symbol: suggestedFolder.symbol,
                    title: suggestedFolder.name,
                    subtitle: suggestedFolder.description,
                    trailingView: buildAddButton(for: suggestedFolder),
                )
            }

            return cell
        }

        dataSource.canMoveRow = { [weak dataSource] indexPath in
            switch dataSource?.itemIdentifier(for: indexPath) {
            case .folder:
                true
            case .suggestedFolder, .createFolder, nil:
                false
            }
        }

        dataSource.didMoveRow = { [weak self] sourceIndexPath, destinationIndexPath in
            self?.didMoveFolder(from: sourceIndexPath, to: destinationIndexPath)
        }

        // .automatic briefly shows square corners and looks buggy
        dataSource.defaultRowAnimation = .fade

        return dataSource
    }()

    private func sectionHeaderView(title: String, description: String? = nil) -> UIView {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 16

        if let description {
            let descriptionLabel = UILabel()
            descriptionLabel.text = description
            descriptionLabel.font = .dynamicTypeSubheadlineClamped
            descriptionLabel.adjustsFontForContentSizeCategory = true
            descriptionLabel.textColor = .Signal.secondaryLabel
            descriptionLabel.textAlignment = .center
            descriptionLabel.numberOfLines = 0
            stackView.addArrangedSubview(descriptionLabel)
        }

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .dynamicTypeHeadlineClamped
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .Signal.label
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header
        stackView.addArrangedSubview(titleLabel)

        // The table sizes a plain view at its full width but shows it inset by
        // its layout margins, which cuts off wrapped text. A header view's
        // content view is sized at the width it's shown at.
        let headerView = UITableViewHeaderFooterView(reuseIdentifier: nil)
        headerView.contentView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(hMargin: 12, vMargin: 12))
        return headerView
    }

    private func buildAddButton(for suggestedFolder: SuggestedChatFolder) -> UIButton {
        var configuration = UIButton.Configuration.smallSecondary(title: OWSLocalizedString(
            "CHAT_FOLDERS_SETTINGS_ADD_SUGGESTED_FOLDER",
            comment: "Button in chat folder settings to add a suggested chat folder.",
        ))
        configuration.background.backgroundColor = .Signal.quaternaryFill
        configuration.cornerStyle = .capsule
        return UIButton(
            configuration: configuration,
            primaryAction: UIAction { [weak self] action in
                // Disable a second tap while animating
                (action.sender as? UIButton)?.isEnabled = false
                self?.addSuggestedFolder(suggestedFolder)
            },
        )
    }

    // MARK: - Contents

    private func reloadFolders(animated: Bool) {
        let folders = db.read { tx in
            chatFolderManager.fetchFoldersForDisplay(tx: tx)
        }

        let oldFolderRows = self.folderRowsById

        var suggestedFolders = SuggestedChatFolder.allCases
        var updatedFolderRowIds: [UUID] = []
        folderRows = folders.map { folder in
            // Loose check that determines whether to remove the suggestion
            suggestedFolders.removeAll { $0.isCovered(by: folder) }

            // Strict check to make the icon and subtitle match the suggestion
            let matchingSuggestedFolder: SuggestedChatFolder? = .matching(folder)

            let folderRow = FolderRow(
                chatFolderId: folder.chatFolderId,
                symbol: matchingSuggestedFolder?.symbol ?? .folder,
                name: folder.displayName,
                subtitle: matchingSuggestedFolder?.description ?? folder.contentsSummary,
                isAllChats: folder.folderType == .all,
            )

            // Check if the row needs to be reloaded in-place
            if
                let oldFolderRow = oldFolderRows[folder.chatFolderId],
                oldFolderRow != folderRow
            {
                updatedFolderRowIds.append(folder.chatFolderId)
            }

            return folderRow
        }
        self.suggestedFolders = suggestedFolders

        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()

        // Folders section
        snapshot.appendSections([.folders])
        snapshot.appendItems(
            [.createFolder] + folderRows.map { .folder(chatFolderId: $0.chatFolderId) },
            toSection: .folders,
        )

        // Suggested folders section
        if !suggestedFolders.isEmpty {
            snapshot.appendSections([.suggestedFolders])
            snapshot.appendItems(suggestedFolders.map { .suggestedFolder($0) }, toSection: .suggestedFolders)
        }

        // Updates
        snapshot.reconfigureItems(updatedFolderRowIds.map { .folder(chatFolderId: $0) })

        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    // MARK: - Reordering

    private func didMoveFolder(from sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        // Catch the data source up from the table view moving the row
        defer { reloadFolders(animated: false) }

        guard
            case .folder(let chatFolderId) = dataSource.itemIdentifier(for: sourceIndexPath),
            case .folder = dataSource.itemIdentifier(for: destinationIndexPath),
            let sourceIndex = folderRows.firstIndex(where: { $0.chatFolderId == chatFolderId })
        else {
            owsFailDebug("Moved a row that isn't a folder!")
            return
        }
        // Rows in the folders section are offset by the "Create a Folder" row.
        let destinationIndex = destinationIndexPath.row - 1

        var chatFolderIds = folderRows.map(\.chatFolderId)
        chatFolderIds.remove(at: sourceIndex)
        chatFolderIds.insert(chatFolderId, at: destinationIndex)

        db.write { tx in
            chatFolderManager.reorder(chatFolderIds: chatFolderIds, tx: tx)
        }
    }

    // MARK: - Adding

    private func addSuggestedFolder(_ suggestedFolder: SuggestedChatFolder) {
        db.write { tx in
            _ = chatFolderManager.save(suggestedFolder.draft, tx: tx)
        }
        reloadFolders(animated: true)

        presentToast(text: String.nonPluralLocalizedStringWithFormat(
            OWSLocalizedString(
                "CHAT_FOLDERS_SETTINGS_FOLDER_ADDED_TOAST_FORMAT",
                comment: "Toast shown after adding a suggested chat folder. Embeds {{ folder name }}.",
            ),
            suggestedFolder.name,
        ))
    }

    // MARK: - Deleting

    static func presentDeleteConfirmation(
        from viewController: UIViewController,
        deleteAction: @escaping () -> Void,
    ) {
        let actionSheet = ActionSheetController(title: OWSLocalizedString(
            "CHAT_FOLDERS_DELETE_FOLDER_CONFIRMATION_TITLE",
            comment: "Title of the confirmation shown before deleting a chat folder.",
        ))
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.deleteButton,
            style: .destructive,
        ) { _ in
            deleteAction()
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        viewController.presentActionSheet(actionSheet)
    }

    private func confirmDeleteFolder(chatFolderId: UUID) {
        Self.presentDeleteConfirmation(from: self) { [weak self] in
            guard let self else { return }
            db.write { tx in
                self.chatFolderManager.delete(chatFolderId: chatFolderId, tx: tx)
            }
            reloadFolders(animated: true)
        }
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch dataSource.sectionIdentifier(for: section) {
        case .folders:
            return sectionHeaderView(
                title: OWSLocalizedString(
                    "CHAT_FOLDERS_SETTINGS_FOLDERS_HEADER",
                    comment: "Header for the list of chat folders in chat folder settings.",
                ),
                description: OWSLocalizedString(
                    "CHAT_FOLDERS_SETTINGS_DESCRIPTION",
                    comment: "Description at the top of the chat folders settings screen.",
                ),
            )
        case .suggestedFolders:
            return sectionHeaderView(title: OWSLocalizedString(
                "CHAT_FOLDERS_SETTINGS_SUGGESTED_HEADER",
                comment: "Header for the list of suggested chat folders in chat folder settings.",
            ))
        case nil:
            return nil
        }
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return false
    }

    func tableView(
        _ tableView: UITableView,
        editingStyleForRowAt indexPath: IndexPath,
    ) -> UITableViewCell.EditingStyle {
        return .none
    }

    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        return false
    }

    func tableView(
        _ tableView: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath,
    ) -> IndexPath {
        let foldersSection = sourceIndexPath.section
        if proposedDestinationIndexPath.section < foldersSection {
            return IndexPath(row: 1, section: foldersSection)
        }
        if proposedDestinationIndexPath.section > foldersSection {
            return IndexPath(row: tableView.numberOfRows(inSection: foldersSection) - 1, section: foldersSection)
        }
        return IndexPath(row: max(proposedDestinationIndexPath.row, 1), section: foldersSection)
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard
            case .folder(let chatFolderId) = dataSource.itemIdentifier(for: indexPath),
            let folderRow = folderRowsById[chatFolderId],
            !folderRow.isAllChats
        else {
            return nil
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                // [Chat Folders] TODO: Edit Folder action
                UIAction(
                    title: OWSLocalizedString(
                        "CHAT_FOLDERS_DELETE_FOLDER",
                        comment: "Action that deletes a chat folder.",
                    ),
                    image: Theme.iconImage(.contextMenuDelete),
                    attributes: .destructive,
                ) { _ in
                    self?.confirmDeleteFolder(chatFolderId: chatFolderId)
                },
            ])
        }
    }

    // MARK: - DatabaseChangeDelegate

    private func reloadFoldersAfterDatabaseChange() {
        // In case the user is reordering. `didMoveFolder` will reload folders instead
        guard !tableView.hasUncommittedUpdates else {
            return
        }
        reloadFolders(animated: true)
    }

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        if ChatFolderStore.databaseTableNames.contains(where: { databaseChanges.didUpdate(tableName: $0) }) {
            reloadFoldersAfterDatabaseChange()
        }
    }

    func databaseChangesDidUpdateExternally() {
        reloadFoldersAfterDatabaseChange()
    }

    func databaseChangesDidReset() {
        reloadFoldersAfterDatabaseChange()
    }
}

// MARK: - SuggestedChatFolder

private enum SuggestedChatFolder: CaseIterable {
    case unread
    case individualChats
    case groups

    var name: String {
        switch self {
        case .unread:
            OWSLocalizedString(
                "CHAT_FOLDERS_SUGGESTED_UNREAD_NAME",
                comment: "Name of the suggested chat folder that shows unread chats.",
            )
        case .individualChats:
            OWSLocalizedString(
                "CHAT_FOLDERS_SUGGESTED_INDIVIDUAL_CHATS_NAME",
                comment: "Name of the suggested chat folder that shows 1:1 chats.",
            )
        case .groups:
            OWSLocalizedString(
                "CHAT_FOLDERS_SUGGESTED_GROUPS_NAME",
                comment: "Name of the suggested chat folder that shows group chats.",
            )
        }
    }

    var description: String {
        switch self {
        case .unread:
            OWSLocalizedString(
                "CHAT_FOLDERS_SUGGESTED_UNREAD_DESCRIPTION",
                comment: "Describes the suggested chat folder that shows unread chats.",
            )
        case .individualChats:
            OWSLocalizedString(
                "CHAT_FOLDERS_SUGGESTED_INDIVIDUAL_CHATS_DESCRIPTION",
                comment: "Describes the suggested chat folder that shows 1:1 chats.",
            )
        case .groups:
            OWSLocalizedString(
                "CHAT_FOLDERS_SUGGESTED_GROUPS_DESCRIPTION",
                comment: "Describes the suggested chat folder that shows group chats.",
            )
        }
    }

    var symbol: SignalSymbol {
        switch self {
        case .unread: .messageBadge
        case .individualChats: .person
        case .groups: .group
        }
    }

    var draft: ChatFolderDraft {
        return ChatFolderDraft(
            name: name,
            showOnlyUnread: self == .unread,
            includeAllIndividualChats: self != .groups,
            includeAllGroupChats: self != .individualChats,
        )
    }

    /// Loose check that determines whether to remove the suggestion.
    func isCovered(by folder: ChatFolder) -> Bool {
        guard
            folder.folderType == .custom,
            folder.includedThreadRowIds.isEmpty,
            folder.excludedThreadRowIds.isEmpty
        else {
            return false
        }
        switch self {
        case .unread:
            return folder.showOnlyUnread && folder.includeAllIndividualChats && folder.includeAllGroupChats
        case .individualChats:
            return folder.includeAllIndividualChats && !folder.includeAllGroupChats
        case .groups:
            return folder.includeAllGroupChats && !folder.includeAllIndividualChats
        }
    }

    /// Strict check to make the icon and subtitle match the suggestion
    static func matching(_ folder: ChatFolder) -> Self? {
        return allCases.first { $0.matches(folder) }
    }

    private func matches(_ folder: ChatFolder) -> Bool {
        var suggested = draft
        suggested.name = folder.name
        return folder.folderType == .custom && folder.draft == suggested
    }
}
