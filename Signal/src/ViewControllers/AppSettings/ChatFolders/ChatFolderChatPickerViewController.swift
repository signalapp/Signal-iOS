//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class ChatFolderChatPickerViewController: OWSTableViewController2, NewMembersBarDelegate, UISearchResultsUpdating {

    // MARK: - Helper types

    struct Selection {
        var orderedThreadRowIds: OrderedSet<Int64>
        var includeAllIndividualChats: Bool
        var includeAllGroupChats: Bool

        var threadRowIds: Set<Int64> { orderedThreadRowIds.unorderedMembers }

        init(threadRowIds: Set<Int64>, includeAllIndividualChats: Bool, includeAllGroupChats: Bool) {
            self.orderedThreadRowIds = OrderedSet(threadRowIds.sorted())
            self.includeAllIndividualChats = includeAllIndividualChats
            self.includeAllGroupChats = includeAllGroupChats
        }

        func isChatTypeSelected(_ chatType: ChatFolderChatType) -> Bool {
            switch chatType {
            case .individual: includeAllIndividualChats
            case .group: includeAllGroupChats
            }
        }

        mutating func setChatType(_ chatType: ChatFolderChatType, isSelected: Bool) {
            switch chatType {
            case .individual: includeAllIndividualChats = isSelected
            case .group: includeAllGroupChats = isSelected
            }
        }
    }

    private class Chat: NSObject {
        let thread: TSThread
        let rowId: Int64
        let recipient: PickedRecipient
        let configuration: ContactCellView.Configuration
        let member: NewMember
        let name: String
        let comparableName: DisplayName.ComparableValue

        @objc
        var collationString: String {
            switch comparableName {
            case .nameValue(let name), .phoneNumber(let name): name
            case .other: ""
            }
        }

        init?(
            thread: TSThread,
            contactManager: any ContactManager,
            nameSortConfig: DisplayName.ComparableValue.Config,
            tx: DBReadTransaction,
        ) {
            guard let rowId = thread.sqliteRowId else { return nil }
            let name = contactManager.displayName(for: thread, transaction: tx)
            let recipient: PickedRecipient
            let configuration: ContactCellView.Configuration
            let shortName: String
            switch thread {
            case let thread as TSContactThread:
                let displayName = contactManager.displayName(for: thread.contactAddress, tx: tx)
                recipient = .for(address: thread.contactAddress)
                configuration = .init(address: thread.contactAddress, localUserDisplayMode: .noteToSelf)
                shortName = thread.isNoteToSelf ? name : displayName.resolvedValue(useShortNameIfAvailable: true)
                comparableName = displayName.comparableValue(config: nameSortConfig)
            case let thread as TSGroupThread where thread.isGroupV2Thread:
                recipient = .for(groupThread: thread)
                configuration = .init(groupThread: thread, localUserDisplayMode: .noteToSelf)
                shortName = name
                comparableName = .nameValue(name)
            default:
                return nil
            }
            self.thread = thread
            self.rowId = rowId
            self.recipient = recipient
            self.configuration = configuration
            self.name = name
            self.member = NewMember(
                recipient: recipient,
                avatarDataSource: .thread(thread),
                shortName: shortName,
                localUserDisplayMode: .noteToSelf,
            )
        }
    }

    // MARK: - Properties

    private let db = DependenciesBridge.shared.db
    private let contactManager = SSKEnvironment.shared.contactManagerRef
    private let tsAccountManager = DependenciesBridge.shared.tsAccountManager
    private let searchableNameIndexer = DependenciesBridge.shared.searchableNameIndexer
    private let phoneNumberVisibilityFetcher = DependenciesBridge.shared.phoneNumberVisibilityFetcher
    private let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable

    private lazy var searchableNameFinder = SearchableNameFinder(
        contactManager: contactManager,
        searchableNameIndexer: searchableNameIndexer,
        phoneNumberVisibilityFetcher: phoneNumberVisibilityFetcher,
        recipientDatabaseTable: recipientDatabaseTable,
    )

    private let membership: ChatFolder.MembershipType
    private var selection: Selection
    private let didSave: (Selection) -> Void
    private var chats: [Chat] = []
    private var chatsByRowId: [Int64: Chat] = [:]
    private var unfilteredContents = OWSTableContents()
    private let memberBar = NewMembersBar()
    private let collation = UILocalizedIndexedCollation.current()
    private var searchTask: Task<Void, Never>?

    private lazy var searchController: UISearchController = {
        let controller = UISearchController(searchResultsController: nil)
        controller.obscuresBackgroundDuringPresentation = false
        controller.hidesNavigationBarDuringPresentation = false
        controller.searchResultsUpdater = self
        return controller
    }()

    private var searchText: String { searchController.searchBar.text?.stripped ?? "" }

    init(
        membership: ChatFolder.MembershipType,
        selection: Selection,
        didSave: @escaping (Selection) -> Void,
    ) {
        self.membership = membership
        self.selection = selection
        self.didSave = didSave
        super.init()
    }

    deinit {
        searchTask?.cancel()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = switch membership {
        case .included:
            ChatFolderStrings.includedChats
        case .excluded:
            ChatFolderStrings.excludedChats
        }
        navigationItem.rightBarButtonItem = .doneButton { [weak self] in
            guard let self else { return }
            self.didSave(self.selection)
            self.navigationController?.popViewController(animated: true)
        }
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        shouldAvoidKeyboard = true
        if #available(iOS 17, *) {
            view.keyboardLayoutGuide.usesBottomSafeArea = false
        }
        memberBar.delegate = self
        // memberBar is added as the topHeader on iOS 18-
        if #available(iOS 26, *) {
            view.addSubview(memberBar)
            memberBar.autoPinEdges(toSuperviewSafeAreaExcludingEdge: .bottom)
            let interaction = UIScrollEdgeElementContainerInteraction()
            interaction.scrollView = tableView
            interaction.edge = .top
            memberBar.addInteraction(interaction)
        }
        tableView.keyboardDismissMode = .onDrag
        tableView.register(ContactTableViewCell.self)
        tableView.register(ChatFolderTableViewCell.self)
        defaultSeparatorInsetLeading = Self.cellHInnerMargin
            + CGFloat(AvatarBuilder.smallAvatarSizePoints) + ContactCellView.avatarTextHSpacing

        loadChats()
        unfilteredContents = buildUnfilteredContents()
        contents = unfilteredContents
        updateSelection()
    }

    override func topHeader() -> UIView? {
        if #available(iOS 26, *) {
            // memberBar is added as a subview directly on iOS 26+
            return nil
        }
        return memberBar
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        memberBar.updateHeightConstraint()
    }

    // MARK: - Contents

    private func loadChats() {
        let nameSortConfig = DisplayName.ComparableValue.Config.current()
        chats = db.read { tx in
            var chats: [Chat] = []

            // Archived chats can be added to folders, but sort after non-archived ones.
            for isArchived in [false, true] {
                ThreadFinder().enumerateVisibleThreads(
                    isArchived: isArchived,
                    transaction: tx,
                ) { thread in
                    Chat(
                        thread: thread,
                        contactManager: contactManager,
                        nameSortConfig: nameSortConfig,
                        tx: tx,
                    ).flatMap { chats.append($0) }
                }
            }

            return chats
        }

        chatsByRowId = Dictionary(uniqueKeysWithValues: chats.map { ($0.rowId, $0) })
    }

    private func updateSelection() {
        var members: [NewMember] = []
        if membership == .included {
            for chatType in ChatFolderChatType.allCases where selection.isChatTypeSelected(chatType) {
                members.append(NewMember(symbol: chatType.symbol, shortName: chatType.name) { [weak self] in
                    guard let self else { return }
                    self.selection.setChatType(chatType, isSelected: false)
                    self.updateSelection()
                })
            }
        }
        members += selection.orderedThreadRowIds.orderedMembers.compactMap { chatsByRowId[$0]?.member }
        memberBar.setMembers(members)
        tableView.reloadData()
    }

    private func buildUnfilteredContents() -> OWSTableContents {
        let contents = OWSTableContents()

        if membership == .included {
            contents.add(OWSTableSection(
                title: OWSLocalizedString(
                    "CHAT_FOLDERS_CHAT_TYPES_HEADER",
                    comment: "Header for the chat types that can be included in a chat folder.",
                ),
                items: ChatFolderChatType.allCases.map(chatTypeItem(chatType:)),
            ))
        }

        let recentChats = Array(chats.prefix(25))
        if !recentChats.isEmpty {
            contents.add(OWSTableSection(
                title: OWSLocalizedString(
                    "CONVERSATION_PICKER_SECTION_RECENTS",
                    comment: "table section header for section containing recent conversations",
                ),
                items: recentChats.map(chatItem(chat:)),
            ))
        }

        let recentRowIds = Set(recentChats.map(\.rowId))
        var buckets = collation.sectionTitles.map { _ in [Chat]() }
        for chat in chats where !recentRowIds.contains(chat.rowId) {
            let index = collation.section(for: chat, collationStringSelector: #selector(getter: Chat.collationString))
            guard buckets.indices.contains(index) else { continue }
            buckets[index].append(chat)
        }
        let sectionOffset = contents.sections.count
        for (index, bucket) in buckets.enumerated() {
            contents.add(OWSTableSection(
                title: bucket.isEmpty ? nil : collation.sectionTitles[index],
                items: bucket.sorted {
                    $0.comparableName.isLessThanOrNilIfEqual($1.comparableName) ?? ($0.rowId < $1.rowId)
                }.map(chatItem(chat:)),
            ))
        }
        if buckets.contains(where: { !$0.isEmpty }) {
            contents.sectionIndexTitlesForTableViewBlock = { [collation] in collation.sectionIndexTitles }
            contents.sectionForSectionIndexTitleBlock = { [collation] _, index in
                sectionOffset + collation.section(forSectionIndexTitle: index)
            }
        }

        return contents
    }

    private func chatItem(chat: Chat) -> OWSTableItem {
        OWSTableItem(
            dequeueCellBlock: { [weak self] tableView in
                guard let self, let cell = tableView.dequeueReusableCell(ContactTableViewCell.self) else {
                    return UITableViewCell()
                }
                let isSelected = self.selection.orderedThreadRowIds.contains(chat.rowId)
                let indicator = SelectionIndicatorView()
                indicator.isSelected = isSelected
                var configuration = chat.configuration
                configuration.accessory = .init(
                    accessoryView: indicator,
                    size: indicator.intrinsicContentSize,
                )
                self.db.read { cell.configure(configuration: configuration, transaction: $0) }
                cell.accessibilityTraits = isSelected ? [.button, .selected] : .button
                return cell
            },
            actionBlock: { [weak self] in
                guard let self else { return }
                let isAdding = !self.selection.orderedThreadRowIds.contains(chat.rowId)
                if isAdding {
                    self.selection.orderedThreadRowIds.append(chat.rowId)
                } else {
                    self.selection.orderedThreadRowIds.remove(chat.rowId)
                }
                self.updateSelection()
                if isAdding {
                    self.memberBar.scrollToRecipient(chat.recipient)
                }
            },
        )
    }

    private func chatTypeItem(chatType: ChatFolderChatType) -> OWSTableItem {
        OWSTableItem(
            dequeueCellBlock: { [weak self] tableView in
                guard let self, let cell = tableView.dequeueReusableCell(ChatFolderTableViewCell.self) else {
                    return UITableViewCell()
                }
                let indicator = SelectionIndicatorView()
                indicator.isSelected = self.selection.isChatTypeSelected(chatType)
                cell.configure(symbol: chatType.symbol, title: chatType.name, trailingView: indicator)
                cell.accessibilityTraits = indicator.isSelected ? [.button, .selected] : .button
                return cell
            },
            actionBlock: { [weak self] in
                guard let self else { return }
                self.selection.setChatType(chatType, isSelected: !self.selection.isChatTypeSelected(chatType))
                self.updateSelection()
                if self.selection.isChatTypeSelected(chatType) {
                    let index = chatType == .group && self.selection.includeAllIndividualChats ? 1 : 0
                    self.memberBar.scrollToMember(at: index)
                }
            },
        )
    }

    // MARK: - NewMembersBarDelegate

    func removeRecipient(_ recipient: PickedRecipient) {
        guard let chat = chats.first(where: { $0.recipient == recipient }) else { return }
        selection.orderedThreadRowIds.remove(chat.rowId)
        updateSelection()
    }

    func newMembersBarHeightDidChange(to height: CGFloat) {
        guard #available(iOS 26, *) else { return }
        let change = tableView.contentInset.top - height
        let updateInsets = {
            self.tableView.contentInset.top = height
            self.tableView.verticalScrollIndicatorInsets.top = height
        }
        if achievedLifecycleStates.contains(.appeared) {
            let animator = UIViewPropertyAnimator(duration: 0.3, springDamping: 1, springResponse: 0.3)
            animator.addAnimations {
                self.tableView.contentOffset.y += change
                updateInsets()
            }
            animator.startAnimation()
        } else {
            updateInsets()
            tableView.contentOffset.y += change
        }
    }

    // MARK: - Search

    func updateSearchResults(for searchController: UISearchController) {
        searchTask?.cancel()
        let searchText = self.searchText
        guard !searchText.isEmpty else {
            contents = unfilteredContents
            return
        }

        searchTask = Task { [weak self, db, tsAccountManager, searchableNameFinder] in
            do throws(CancellationError) {
                let matches = try await Self.search(
                    searchText: searchText,
                    db: db,
                    tsAccountManager: tsAccountManager,
                    searchableNameFinder: searchableNameFinder,
                )
                guard let self, !Task.isCancelled else { return }
                let chats = self.chats.filter {
                    matches.contains($0.thread.uniqueId) || $0.name.localizedStandardContains(searchText)
                }
                let contents = OWSTableContents()
                if !chats.isEmpty {
                    contents.add(OWSTableSection(items: chats.map(self.chatItem)))
                }
                self.contents = contents
            } catch {
            }
        }
    }

    @concurrent
    private static func search(
        searchText: String,
        db: any DB,
        tsAccountManager: any TSAccountManager,
        searchableNameFinder: SearchableNameFinder,
    ) async throws(CancellationError) -> Set<String> {
        try db.read { tx throws(CancellationError) in
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else { return [] }
            var matches = Set<String>()
            let addresses = try searchableNameFinder.searchNames(
                for: searchText,
                maxResults: Int.max,
                localIdentifiers: localIdentifiers,
                tx: tx,
                addGroupThread: { matches.insert($0.uniqueId) },
                addStoryThread: { _ in },
            )
            for address in addresses {
                if let thread = TSContactThread.getWithContactAddress(address, transaction: tx) {
                    matches.insert(thread.uniqueId)
                }
            }
            return matches
        }
    }
}
