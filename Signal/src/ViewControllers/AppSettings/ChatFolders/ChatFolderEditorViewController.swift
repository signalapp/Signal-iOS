//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ChatFolderEditorViewController:
    OWSViewController,
    OWSNavigationChildController,
    UITableViewDelegate,
    UITextFieldDelegate
{

    // MARK: - Helper types

    private enum Section: Hashable {
        case name
        case includedChats
        case excludedChats
        case onlyUnread
        case includeMuted
        case delete
    }

    private enum Row: Hashable {
        case name
        case addChats(ChatFolder.MembershipType)
        case chatType(ChatFolderChatType)
        case chat(ChatFolder.MembershipType, threadRowId: Int64)
        case showAll(ChatFolder.MembershipType)
        case onlyUnread
        case includeMuted
        case delete
    }

    private struct Chat {
        let threadRowId: Int64
        let configuration: ContactCellView.Configuration
    }

    // MARK: - Properties

    private static let collapsedChatCount = 5

    private let db = DependenciesBridge.shared.db
    private let chatFolderManager = DependenciesBridge.shared.chatFolderManager
    private let threadStore = DependenciesBridge.shared.threadStore

    private let chatFolderId: UUID?
    private let originalDraft: ChatFolderDraft
    private var draft: ChatFolderDraft

    private var includedChats: [Chat] = []
    private var excludedChats: [Chat] = []
    private var isIncludedExpanded = false
    private var isExcludedExpanded = false

    init(folder: ChatFolder? = nil) {
        var draft = folder?.draft ?? ChatFolderDraft()
        draft.name = Self.normalizedName(draft.name)
        self.chatFolderId = folder?.chatFolderId
        self.originalDraft = draft
        self.draft = draft

        super.init()
    }

    private static func normalizedName(_ name: String) -> String {
        return String(name.prefix(ChatFolder.maxNameLength)).trimmingCharacters(in: .whitespacesAndNewlines).filterForDisplay
    }

    private func nameDidChange() {
        draft.name = Self.normalizedName(nameTextField.text ?? "")
        updateNavigationBar()
    }

    private var hasUnsavedChanges: Bool {
        return draft != originalDraft
    }

    private var canSave: Bool {
        return !draft.name.isEmpty && hasUnsavedChanges
    }

    // MARK: - OWSNavigationChildController

    var navbarBackgroundColorOverride: UIColor? {
        .Signal.groupedBackground
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = chatFolderId == nil
            ? OWSLocalizedString(
                "CHAT_FOLDERS_CREATE_FOLDER_TITLE",
                comment: "Title for the screen that creates a new chat folder.",
            )
            : OWSLocalizedString(
                "CHAT_FOLDERS_EDIT_FOLDER_TITLE",
                comment: "Title for the screen that edits an existing chat folder.",
            )

        navigationItem.leftBarButtonItem = .cancelButton(
            dismissingFrom: self,
            hasUnsavedChanges: { [weak self] in self?.hasUnsavedChanges },
        )
        navigationItem.rightBarButtonItem = .doneButton { [weak self] in
            self?.didTapDone()
        }

        view.backgroundColor = .Signal.groupedBackground
        view.addSubview(tableView)
        tableView.autoPinEdges(toSuperviewEdgesExcludingEdge: .bottom)
        tableView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor).isActive = true
        if #available(iOS 17, *) {
            view.keyboardLayoutGuide.usesBottomSafeArea = false
        }

        loadChats()
        applySnapshot(animated: false)
        updateNavigationBar()
    }

    override func viewDidAppear(_ animated: Bool) {
        let isFirstAppearance = !achievedLifecycleStates.contains(.appeared)
        super.viewDidAppear(animated)

        if chatFolderId == nil, isFirstAppearance {
            nameTextField.becomeFirstResponder()
        }
    }

    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set {}
    }

    private func updateNavigationBar() {
        navigationItem.rightBarButtonItem?.isEnabled = canSave
    }

    // MARK: - Views

    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.delegate = self
        tableView.preservesSuperviewLayoutMargins = true
        tableView.rowHeight = UITableView.automaticDimension
        tableView.backgroundColor = .Signal.groupedBackground
        tableView.register(ChatFolderTableViewCell.self)
        tableView.register(ChatCell.self)
        return tableView
    }()

    private lazy var dataSource: OWSTableViewDiffableDataSource<Section, Row> = {
        let dataSource = OWSTableViewDiffableDataSource<Section, Row>(
            tableView: tableView,
        ) { [weak self] tableView, indexPath, row in
            self?.cell(for: row, in: tableView, at: indexPath) ?? UITableViewCell()
        }
        dataSource.defaultRowAnimation = .fade
        dataSource.canEditRow = { [weak dataSource] indexPath in
            switch dataSource?.itemIdentifier(for: indexPath) {
            case .chatType, .chat:
                true
            case .name, .addChats, .showAll, .onlyUnread, .includeMuted, .delete, nil:
                false
            }
        }
        return dataSource
    }()

    private lazy var nameTextField: UITextField = {
        let textField = UITextField()
        textField.text = draft.name
        textField.font = .dynamicTypeBody
        textField.textColor = .Signal.label
        textField.placeholder = OWSLocalizedString(
            "CHAT_FOLDERS_FOLDER_NAME_PLACEHOLDER",
            comment: "Placeholder for the name field when creating or editing a chat folder.",
        )
        textField.returnKeyType = .done
        textField.autocapitalizationType = .words
        textField.delegate = self
        textField.addAction(
            UIAction { [weak self] _ in
                self?.nameDidChange()
            },
            for: .editingChanged,
        )
        return textField
    }()

    private lazy var nameCell: UITableViewCell = {
        let cell = OWSTableItem.newCell()
        cell.selectionStyle = .none
        cell.contentView.addSubview(nameTextField)
        nameTextField.autoPinEdgesToSuperviewMargins()
        return cell
    }()

    private func cell(for row: Row, in tableView: UITableView, at indexPath: IndexPath) -> UITableViewCell {
        switch row {
        case .name:
            return nameCell
        case .addChats(let membership):
            let title = switch membership {
            case .included:
                OWSLocalizedString(
                    "CHAT_FOLDERS_ADD_CHATS",
                    comment: "Button to choose chats to include in a chat folder.",
                )
            case .excluded:
                OWSLocalizedString(
                    "CHAT_FOLDERS_EXCLUDE_CHATS",
                    comment: "Button to choose chats to exclude from a chat folder.",
                )
            }
            let cell = tableView.dequeueReusableCell(ChatFolderTableViewCell.self, for: indexPath)
            cell.configure(symbol: .plus, title: title)
            return cell
        case .chatType(let chatType):
            let cell = tableView.dequeueReusableCell(ChatFolderTableViewCell.self, for: indexPath)
            cell.configure(symbol: chatType.symbol, title: chatType.name)
            return cell
        case .chat(let membership, let threadRowId):
            let cell = tableView.dequeueReusableCell(ChatCell.self, for: indexPath)
            if let chat = chats(membership: membership).first(where: { $0.threadRowId == threadRowId }) {
                db.read { tx in
                    cell.configure(configuration: chat.configuration, transaction: tx)
                }
            }
            cell.selectionStyle = .none
            return cell
        case .showAll:
            let cell = tableView.dequeueReusableCell(ChatFolderTableViewCell.self, for: indexPath)
            cell.configure(symbol: .chevronDown, title: CommonStrings.seeAllButton)
            return cell
        case .onlyUnread:
            return switchCell(
                title: OWSLocalizedString(
                    "CHAT_FOLDERS_ONLY_UNREAD",
                    comment: "Chat folder setting that hides chats without unread messages.",
                ),
                isOn: draft.showOnlyUnread,
            ) { [weak self] isOn in
                self?.draft.showOnlyUnread = isOn
                self?.updateNavigationBar()
            }
        case .includeMuted:
            return switchCell(
                title: OWSLocalizedString(
                    "CHAT_FOLDERS_INCLUDE_MUTED",
                    comment: "Chat folder setting that shows muted chats in the folder.",
                ),
                isOn: draft.showMutedChats,
            ) { [weak self] isOn in
                self?.draft.showMutedChats = isOn
                self?.updateNavigationBar()
            }
        case .delete:
            return OWSTableItem.buildCell(
                itemName: ChatFolderStrings.deleteFolder,
                textColor: .Signal.red,
            )
        }
    }

    private func switchCell(title: String, isOn: Bool, didChange: @escaping (Bool) -> Void) -> UITableViewCell {
        let cell = OWSTableItem.buildImageCell(itemName: title)
        let cellSwitch = UISwitch()
        cellSwitch.isOn = isOn
        cellSwitch.addAction(
            UIAction { [unowned cellSwitch] _ in didChange(cellSwitch.isOn) },
            for: .valueChanged,
        )
        cell.accessoryView = cellSwitch
        cell.selectionStyle = .none
        return cell
    }

    private static func sectionHeaderView(title: String) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .dynamicTypeHeadlineClamped
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .Signal.label
        label.numberOfLines = 0
        label.accessibilityTraits = .header
        return headerFooterView(wrapping: label)
    }

    private static func sectionFooterView(text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .dynamicTypeFootnoteClamped
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .Signal.secondaryLabel
        label.numberOfLines = 0
        return headerFooterView(wrapping: label)
    }

    private static func headerFooterView(wrapping label: UILabel) -> UIView {
        let view = UITableViewHeaderFooterView(reuseIdentifier: nil)
        view.contentView.addSubview(label)
        label.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(hMargin: 12, vMargin: 12))
        return view
    }

    // MARK: - Contents

    private func loadChats() {
        (includedChats, excludedChats) = db.read { tx in
            (
                fetchChats(threadRowIds: draft.includedThreadRowIds, tx: tx),
                fetchChats(threadRowIds: draft.excludedThreadRowIds, tx: tx),
            )
        }
    }

    private func fetchChats(threadRowIds: Set<Int64>, tx: DBReadTransaction) -> [Chat] {
        return threadRowIds.sorted().compactMap { rowId in
            guard
                let thread = threadStore.fetchThread(rowId: rowId, tx: tx),
                let configuration = Self.contactCellConfiguration(thread: thread)
            else {
                return nil
            }
            return Chat(threadRowId: rowId, configuration: configuration)
        }
    }

    private func chats(membership: ChatFolder.MembershipType) -> [Chat] {
        switch membership {
        case .included: includedChats
        case .excluded: excludedChats
        }
    }

    private static func contactCellConfiguration(thread: TSThread) -> ContactCellView.Configuration? {
        switch thread {
        case let thread as TSGroupThread where thread.isGroupV2Thread:
            ContactCellView.Configuration(
                groupThread: thread,
                localUserDisplayMode: .noteToSelf,
            )
        case let thread as TSContactThread:
            ContactCellView.Configuration(
                address: thread.contactAddress,
                localUserDisplayMode: .noteToSelf,
            )
        default:
            nil
        }
    }

    private func applySnapshot(animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()

        snapshot.appendSections([.name])
        snapshot.appendItems([.name], toSection: .name)

        var includedRows: [Row] = [.addChats(.included)]
        if draft.includeAllIndividualChats {
            includedRows.append(.chatType(.individual))
        }
        if draft.includeAllGroupChats {
            includedRows.append(.chatType(.group))
        }
        includedRows += chatRows(.included)
        snapshot.appendSections([.includedChats])
        snapshot.appendItems(includedRows, toSection: .includedChats)

        snapshot.appendSections([.excludedChats])
        snapshot.appendItems([.addChats(.excluded)], toSection: .excludedChats)
        snapshot.appendItems(chatRows(.excluded), toSection: .excludedChats)

        snapshot.appendSections([.onlyUnread, .includeMuted])
        snapshot.appendItems([.onlyUnread], toSection: .onlyUnread)
        snapshot.appendItems([.includeMuted], toSection: .includeMuted)
        if chatFolderId != nil {
            snapshot.appendSections([.delete])
            snapshot.appendItems([.delete], toSection: .delete)
        }

        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private func chatRows(_ membership: ChatFolder.MembershipType) -> [Row] {
        let rows = chats(membership: membership).map { chat in
            Row.chat(membership, threadRowId: chat.threadRowId)
        }

        let isExpanded = switch membership {
        case .included: isIncludedExpanded
        case .excluded: isExcludedExpanded
        }
        guard !isExpanded, rows.count > Self.collapsedChatCount else {
            return rows
        }
        return Array(rows.prefix(Self.collapsedChatCount)) + [.showAll(membership)]
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let title: String
        switch dataSource.sectionIdentifier(for: section) {
        case .name:
            title = OWSLocalizedString(
                "CHAT_FOLDERS_FOLDER_NAME_HEADER",
                comment: "Header for the name field when creating or editing a chat folder.",
            )
        case .includedChats:
            title = ChatFolderStrings.includedChats
        case .excludedChats:
            title = ChatFolderStrings.excludedChats
        case .onlyUnread:
            title = OWSLocalizedString(
                "CHAT_FOLDERS_MORE_OPTIONS_HEADER",
                comment: "Header for additional chat folder settings.",
            )
        case .includeMuted, .delete, nil:
            return nil
        }
        return Self.sectionHeaderView(title: title)
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let text: String
        switch dataSource.sectionIdentifier(for: section) {
        case .includedChats:
            text = OWSLocalizedString(
                "CHAT_FOLDERS_INCLUDED_CHATS_FOOTER",
                comment: "Footer for the list of chats included in a chat folder.",
            )
        case .excludedChats:
            text = OWSLocalizedString(
                "CHAT_FOLDERS_EXCLUDED_CHATS_FOOTER",
                comment: "Footer for the list of chats excluded from a chat folder.",
            )
        case .onlyUnread:
            text = OWSLocalizedString(
                "CHAT_FOLDERS_ONLY_UNREAD_FOOTER",
                comment: "Footer for the chat folder setting that hides chats without unread messages.",
            )
        case .name, .includeMuted, .delete, nil:
            return nil
        }
        return Self.sectionFooterView(text: text)
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        switch dataSource.itemIdentifier(for: indexPath) {
        case .name, .showAll, .delete, .addChats:
            return true
        case .chatType, .chat, .onlyUnread, .includeMuted, nil:
            return false
        }
    }

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        return self.tableView(tableView, shouldHighlightRowAt: indexPath) ? indexPath : nil
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch dataSource.itemIdentifier(for: indexPath) {
        case .name:
            nameTextField.becomeFirstResponder()
        case .showAll(let membership):
            switch membership {
            case .included: isIncludedExpanded = true
            case .excluded: isExcludedExpanded = true
            }
            applySnapshot(animated: true)
        case .delete:
            didTapDelete()
        case .addChats(let membership):
            showChatPicker(membership: membership)
        case .chatType, .chat, .onlyUnread, .includeMuted, nil:
            break
        }
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        let row = dataSource.itemIdentifier(for: indexPath)
        switch row {
        case .chatType, .chat:
            break
        case .name, .addChats, .showAll, .onlyUnread, .includeMuted, .delete, nil:
            return nil
        }

        let deleteAction = ContextualActionBuilder.makeContextualAction(
            style: .destructive,
            color: .Signal.red,
            image: .trashFill,
            title: CommonStrings.deleteButton,
        ) { [weak self] completion in
            self?.removeRow(row)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    // MARK: - Actions

    private func removeRow(_ row: Row?) {
        switch row {
        case .chatType(.individual):
            draft.includeAllIndividualChats = false
        case .chatType(.group):
            draft.includeAllGroupChats = false
        case .chat(.included, let threadRowId):
            draft.includedThreadRowIds.remove(threadRowId)
            includedChats.removeAll { $0.threadRowId == threadRowId }
        case .chat(.excluded, let threadRowId):
            draft.excludedThreadRowIds.remove(threadRowId)
            excludedChats.removeAll { $0.threadRowId == threadRowId }
        case .name, .addChats, .showAll, .onlyUnread, .includeMuted, .delete, nil:
            return
        }
        applySnapshot(animated: true)
        updateNavigationBar()
    }

    private func showChatPicker(membership: ChatFolder.MembershipType) {
        let selection = ChatFolderChatPickerViewController.Selection(
            threadRowIds: membership == .included ? draft.includedThreadRowIds : draft.excludedThreadRowIds,
            includeAllIndividualChats: draft.includeAllIndividualChats,
            includeAllGroupChats: draft.includeAllGroupChats,
        )
        let picker = ChatFolderChatPickerViewController(membership: membership, selection: selection, didSave: { [weak self] selection in
            guard let self else { return }
            switch membership {
            case .included:
                self.draft.includedThreadRowIds = selection.threadRowIds
                self.draft.excludedThreadRowIds.subtract(selection.threadRowIds)
                self.draft.includeAllIndividualChats = selection.includeAllIndividualChats
                self.draft.includeAllGroupChats = selection.includeAllGroupChats
            case .excluded:
                self.draft.excludedThreadRowIds = selection.threadRowIds
                self.draft.includedThreadRowIds.subtract(selection.threadRowIds)
            }
            self.loadChats()
            self.applySnapshot(animated: true)
            self.updateNavigationBar()
        })
        navigationController?.pushViewController(picker, animated: true)
    }

    private func didTapDone() {
        guard canSave else {
            return
        }

        db.write { tx in
            if let chatFolderId {
                chatFolderManager.update(
                    chatFolderId: chatFolderId,
                    draft: draft,
                    tx: tx,
                )
            } else {
                _ = chatFolderManager.save(draft, tx: tx)
            }
        }
        dismiss(animated: true)
    }

    private func didTapDelete() {
        ChatFoldersSettingsViewController.presentDeleteConfirmation(from: self) { [weak self] in
            self?.deleteFolder()
        }
    }

    private func deleteFolder() {
        guard let chatFolderId else { return }
        db.write { tx in
            chatFolderManager.delete(chatFolderId: chatFolderId, tx: tx)
        }
        dismiss(animated: true)
    }

    // MARK: - UITextFieldDelegate

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString: String,
    ) -> Bool {
        let shouldChange = TextFieldHelper.textField(
            textField,
            shouldChangeCharactersInRange: range,
            replacementString: replacementString,
            maxGlyphCount: ChatFolder.maxNameLength,
        )
        if !shouldChange {
            nameDidChange()
        }
        return shouldChange
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }
}

// MARK: - ChatCell

private class ChatCell: ContactTableViewCell {
    override class var reuseIdentifier: String { "ChatFolderEditorChatCell" }

    override func layoutSubviews() {
        super.layoutSubviews()

        let separatorLeading = contentView.directionalLayoutMargins.leading
            + CGFloat(AvatarBuilder.smallAvatarSizePoints)
            + ContactCellView.avatarTextHSpacing
        if separatorInset.left != separatorLeading {
            separatorInset.left = separatorLeading
        }
    }
}
