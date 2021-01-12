//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public protocol ConversationPickerDelegate: AnyObject {
    var selectedConversationsForConversationPicker: [ConversationItem] { get }

    func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
                            didSelectConversation conversation: ConversationItem)

    func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
                            didDeselectConversation conversation: ConversationItem)

    func conversationPickerDidCompleteSelection(_ conversationPickerViewController: ConversationPickerViewController)

    func conversationPickerCanCancel(_ conversationPickerViewController: ConversationPickerViewController) -> Bool

    func conversationPickerDidCancel(_ conversationPickerViewController: ConversationPickerViewController)

    func approvalMode(_ conversationPickerViewController: ConversationPickerViewController) -> ApprovalMode
}

@objc
open class ConversationPickerViewController: OWSViewController {

    public weak var delegate: ConversationPickerDelegate?

    enum Section: Int, CaseIterable {
        case recents, signalContacts, groups
    }

    let kMaxPickerSelection = 32

    private let tableView = UITableView()
    private let footerView = ApprovalFooterView()
    private var footerOffsetConstraint: NSLayoutConstraint!
    private lazy var searchBar: OWSSearchBar = {
        let searchBar = OWSSearchBar()
        searchBar.placeholder = CommonStrings.searchPlaceholder
        searchBar.delegate = self
        return searchBar
    }()

    // MARK: - UIViewController

    public override var canBecomeFirstResponder: Bool {
        return true
    }

    var currentInputAcccessoryView: UIView? {
        didSet {
            if oldValue != currentInputAcccessoryView {
                searchBar.inputAccessoryView = currentInputAcccessoryView
                searchBar.reloadInputViews()
                reloadInputViews()
            }
        }
    }

    public override var inputAccessoryView: UIView? {
        return currentInputAcccessoryView
    }

    private var approvalMode: ApprovalMode {
        guard let delegate = delegate else {
            return .send
        }
        return delegate.approvalMode(self)
    }

    public override func loadView() {
        self.view = UIView()
        view.backgroundColor = Theme.backgroundColor
        view.addSubview(tableView)
        tableView.separatorColor = Theme.cellSeparatorColor
        tableView.backgroundColor = Theme.backgroundColor
        tableView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        self.autoPinView(toBottomOfViewControllerOrKeyboard: tableView, avoidNotch: true)

        searchBar.sizeToFit()
        tableView.tableHeaderView = searchBar

        if delegate?.conversationPickerCanCancel(self) ?? false {
            let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(onTouchCancelButton))
            self.navigationItem.leftBarButtonItem = cancelButton
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = Strings.title
        blockListCache.startObservingAndSyncState(delegate: self)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = true
        tableView.register(ConversationPickerCell.self, forCellReuseIdentifier: ConversationPickerCell.reuseIdentifier)
        tableView.register(DarkThemeTableSectionHeader.self, forHeaderFooterViewReuseIdentifier: DarkThemeTableSectionHeader.reuseIdentifier)

        footerView.delegate = self

        conversationCollection = buildConversationCollection()
        restoreSelection(tableView: tableView)
    }

    // MARK: - ConversationCollection

    func restoreSelection(tableView: UITableView) {
        guard let delegate = delegate else { return }

        tableView.indexPathsForSelectedRows?.forEach { tableView.deselectRow(at: $0, animated: false) }

        for selectedConversation in delegate.selectedConversationsForConversationPicker {
            guard let index = conversationCollection.indexPath(conversation: selectedConversation) else {
                // This can happen when restoring selection while the currently displayed results
                // are filtered.
                continue
            }
            tableView.selectRow(at: index, animated: false, scrollPosition: .none)
        }
        updateUIForCurrentSelection(animated: false)
    }

    let blockListCache = BlockListCache()

    func buildSearchResults(searchText: String) -> Promise<ComposeScreenSearchResultSet?> {
        guard searchText.count > 1 else {
            return Promise.value(nil)
        }

        return DispatchQueue.global().async(.promise) {
            return self.databaseStorage.read { transaction in
                return self.fullTextSearcher.searchForComposeScreen(searchText: searchText,
                                                                    omitLocalUser: false,
                                                                    transaction: transaction)
            }
        }
    }

    func buildGroupItem(_ groupThread: TSGroupThread, transaction: SDSAnyReadTransaction) -> GroupConversationItem {
        let isBlocked = self.blockListCache.isBlocked(thread: groupThread)
        let dmConfig = groupThread.disappearingMessagesConfiguration(with: transaction)
        return GroupConversationItem(groupThread: groupThread,
                                     isBlocked: isBlocked,
                                     disappearingMessagesConfig: dmConfig)
    }

    func buildContactItem(_ address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> ContactConversationItem {
        let isBlocked = self.blockListCache.isBlocked(address: address)
        let dmConfig = TSContactThread.getWithContactAddress(address, transaction: transaction)?.disappearingMessagesConfiguration(with: transaction)

        let contactName = contactsManager.displayName(for: address,
                                                      transaction: transaction)

        let comparableName = contactsManager.comparableName(for: address,
                                                            transaction: transaction)

        return ContactConversationItem(address: address,
                                       isBlocked: isBlocked,
                                       disappearingMessagesConfig: dmConfig,
                                       contactName: contactName,
                                       comparableName: comparableName)
    }

    func buildConversationCollection() -> ConversationCollection {
        return self.databaseStorage.uiRead { transaction in
            var pinnedItemsByThreadId: [String: RecentConversationItem] = [:]
            var recentItems: [RecentConversationItem] = []
            var contactItems: [ContactConversationItem] = []
            var groupItems: [GroupConversationItem] = []
            var seenAddresses: Set<SignalServiceAddress> = Set()

            let pinnedThreadIds = PinnedThreadManager.pinnedThreadIds

            // We append any pinned threads at the start of the "recent"
            // section, so we decrease our maximum recent items based
            // on how many threads are currently pinned.
            let maxRecentCount = 25 - pinnedThreadIds.count

            let addThread = { (thread: TSThread) -> Void in
                guard thread.canSendToThread else {
                    return
                }

                switch thread {
                case let contactThread as TSContactThread:
                    let item = self.buildContactItem(contactThread.contactAddress, transaction: transaction)
                    seenAddresses.insert(contactThread.contactAddress)
                    if pinnedThreadIds.contains(thread.uniqueId) {
                        let recentItem = RecentConversationItem(backingItem: .contact(item))
                        pinnedItemsByThreadId[thread.uniqueId] = recentItem
                    } else if recentItems.count < maxRecentCount {
                        let recentItem = RecentConversationItem(backingItem: .contact(item))
                        recentItems.append(recentItem)
                    } else {
                        contactItems.append(item)
                    }
                case let groupThread as TSGroupThread:
                    guard groupThread.isLocalUserFullMember else {
                        return
                    }
                    let item = self.buildGroupItem(groupThread, transaction: transaction)
                    if pinnedThreadIds.contains(thread.uniqueId) {
                        let recentItem = RecentConversationItem(backingItem: .group(item))
                        pinnedItemsByThreadId[thread.uniqueId] = recentItem
                    } else if recentItems.count < maxRecentCount {
                        let recentItem = RecentConversationItem(backingItem: .group(item))
                        recentItems.append(recentItem)
                    } else {
                        groupItems.append(item)
                    }
                default:
                    owsFailDebug("unexpected thread: \(thread.uniqueId)")
                }
            }

            try! AnyThreadFinder().enumerateVisibleThreads(isArchived: false, transaction: transaction) { thread in
                addThread(thread)
            }

            try! AnyThreadFinder().enumerateVisibleThreads(isArchived: true, transaction: transaction) { thread in
                addThread(thread)
            }

            SignalAccount.anyEnumerate(transaction: transaction) { signalAccount, _ in
                let address = signalAccount.recipientAddress
                guard !seenAddresses.contains(address) else {
                    return
                }
                seenAddresses.insert(address)

                let contactItem = self.buildContactItem(address, transaction: transaction)
                contactItems.append(contactItem)
            }
            contactItems.sort()

            let pinnedItems = pinnedItemsByThreadId.sorted { lhs, rhs in
                guard let lhsIndex = pinnedThreadIds.firstIndex(of: lhs.key),
                    let rhsIndex = pinnedThreadIds.firstIndex(of: rhs.key) else {
                    owsFailDebug("Unexpectedly have pinned item without pinned thread id")
                    return false
                }

                return lhsIndex < rhsIndex
            }.map { $0.value }

            return ConversationCollection(contactConversations: contactItems,
                                          recentConversations: pinnedItems + recentItems,
                                          groupConversations: groupItems)
        }
    }

    func buildConversationCollection(searchResults: ComposeScreenSearchResultSet?) -> Promise<ConversationCollection> {
        guard let searchResults = searchResults else {
            return Promise.value(buildConversationCollection())
        }

        return DispatchQueue.global().async(.promise) {
            return self.databaseStorage.read { transaction in
                let groupItems = searchResults.groupThreads.compactMap { groupThread -> GroupConversationItem? in
                    guard groupThread.canSendToThread else {
                        return nil
                    }
                    return self.buildGroupItem(groupThread, transaction: transaction)
                }
                let contactItems = searchResults.signalAccounts.map { self.buildContactItem($0.recipientAddress, transaction: transaction) }

                return ConversationCollection(contactConversations: contactItems,
                                              recentConversations: [],
                                              groupConversations: groupItems)
            }
        }
    }

    func conversation(for indexPath: IndexPath) -> ConversationItem? {
        guard let section = Section(rawValue: indexPath.section) else {
            owsFailDebug("section was unexpectedly nil")
            return nil
        }

        return conversationCollection.conversations(section: section)[indexPath.row]
    }

    var conversationCollection: ConversationCollection = .empty

    struct ConversationCollection {
        static let empty: ConversationCollection = ConversationCollection(contactConversations: [],
                                                                          recentConversations: [],
                                                                          groupConversations: [])
        let contactConversations: [ConversationItem]
        let recentConversations: [ConversationItem]
        let groupConversations: [ConversationItem]

        func conversations(section: Section) -> [ConversationItem] {
            switch section {
            case .recents:
                return recentConversations
            case .signalContacts:
                return contactConversations
            case .groups:
                return groupConversations
            }
        }

        func indexPath(conversation: ConversationItem) -> IndexPath? {
            switch conversation.messageRecipient {
            case .contact:
                if let row = (recentConversations.map { $0.messageRecipient }).firstIndex(of: conversation.messageRecipient) {
                    return IndexPath(row: row, section: Section.recents.rawValue)
                } else if let row = (contactConversations.map { $0.messageRecipient }).firstIndex(of: conversation.messageRecipient) {
                    return IndexPath(row: row, section: Section.signalContacts.rawValue)
                } else {
                    return nil
                }
            case .group:
                if let row = (recentConversations.map { $0.messageRecipient }).firstIndex(of: conversation.messageRecipient) {
                    return IndexPath(row: row, section: Section.recents.rawValue)
                } else if let row = (groupConversations.map { $0.messageRecipient }).firstIndex(of: conversation.messageRecipient) {
                    return IndexPath(row: row, section: Section.groups.rawValue)
                } else {
                    return nil
                }
            }
        }
    }

    // MARK: - Button Actions

    @objc func onTouchCancelButton() {
        delegate?.conversationPickerDidCancel(self)
    }
}

// MARK: -

extension ConversationPickerViewController: BlockListCacheDelegate {
    public func blockListCacheDidUpdate(_ blocklistCache: BlockListCache) {
        Logger.debug("")
        self.conversationCollection = buildConversationCollection()
    }
}

// MARK: -

extension ConversationPickerViewController: UITableViewDataSource {
    public func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard !Theme.isDarkThemeEnabled else {
            // we build a custom header for dark theme
            return nil
        }

        return titleForHeader(inSection: section)
    }

    func titleForHeader(inSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else {
            owsFailDebug("section was unexpectedly nil")
            return nil
        }

        guard conversationCollection.conversations(section: section).count > 0 else {
            return nil
        }

        switch section {
        case .recents:
            return Strings.recentsSection
        case .signalContacts:
            return Strings.signalContactsSection
        case .groups:
            return Strings.groupsSection
        }
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else {
            owsFailDebug("section was unexpectedly nil")
            return 0
        }

        return conversationCollection.conversations(section: section).count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let conversationItem = conversation(for: indexPath) else {
            owsFail("conversation was unexpectedly nil")
        }

        guard let cell = tableView.dequeueReusableCell(withIdentifier: ConversationPickerCell.reuseIdentifier, for: indexPath) as? ConversationPickerCell else {
            owsFail("cell was unexpectedly nil for indexPath: \(indexPath)")
        }

        databaseStorage.uiRead { transaction in
            cell.configure(conversationItem: conversationItem, transaction: transaction)
        }

        return cell
    }

    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard Theme.isDarkThemeEnabled else {
            return nil
        }

        guard let title = titleForHeader(inSection: section) else {
            // empty sections will have no title - don't show a header.
            let dummyView = UIView()
            dummyView.backgroundColor = .yellow
            return dummyView
        }

        guard let sectionHeader = tableView.dequeueReusableHeaderFooterView(withIdentifier: DarkThemeTableSectionHeader.reuseIdentifier) as? DarkThemeTableSectionHeader else {
            owsFailDebug("unable to build section header for section: \(section)")
            return nil
        }

        sectionHeader.configure(title: title)

        return sectionHeader
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard titleForHeader(inSection: section) != nil else {
            // empty sections will have no title - don't show a header.
            return 0
        }

        return ThemeHeaderView.desiredHeight
    }
}

// MARK: -

extension ConversationPickerViewController: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard let delegate = delegate else { return nil }

        guard let item = conversation(for: indexPath) else {
            owsFailDebug("item was unexpectedly nil")
            return nil
        }

        guard delegate.selectedConversationsForConversationPicker.count < kMaxPickerSelection else {
            showTooManySelectedToast()
            return nil
        }

        guard !item.isBlocked else {
            // TODO remove these passed in dependencies.
            switch item.messageRecipient {
            case .contact(let address):
                BlockListUIUtils.showUnblockAddressActionSheet(address,
                                                               from: self) { isStillBlocked in
                                                                AssertIsOnMainThread()

                                                                guard !isStillBlocked else {
                                                                    return
                                                                }

                                                                self.conversationCollection = self.buildConversationCollection()
                                                                tableView.reloadData()
                                                                self.restoreSelection(tableView: tableView)
                }
            case .group(let groupThread):
                BlockListUIUtils.showUnblockThreadActionSheet(groupThread,
                                                              from: self) { isStillBlocked in
                                                                AssertIsOnMainThread()

                                                                guard !isStillBlocked else {
                                                                    return
                                                                }

                                                                self.conversationCollection = self.buildConversationCollection()
                                                                tableView.reloadData()
                                                                self.restoreSelection(tableView: tableView)
                }
            }

            return nil
        }

        return indexPath
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let conversation = conversation(for: indexPath) else {
            owsFailDebug("conversation was unexpectedly nil")
            return
        }
        delegate?.conversationPicker(self, didSelectConversation: conversation)
        updateUIForCurrentSelection(animated: true)
    }

    public func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard let conversation = conversation(for: indexPath) else {
            owsFailDebug("conversation was unexpectedly nil")
            return
        }
        delegate?.conversationPicker(self, didDeselectConversation: conversation)
        updateUIForCurrentSelection(animated: true)
    }

    private func updateUIForCurrentSelection(animated: Bool) {
        guard let delegate = delegate else { return }

        let conversations = delegate.selectedConversationsForConversationPicker
        if conversations.count == 0 {
            currentInputAcccessoryView = nil
        } else {
            currentInputAcccessoryView = footerView
        }

        let labelText = conversations.map { $0.title }.joined(separator: ", ")
        footerView.setNamesText(labelText, animated: animated)
    }

    private func showTooManySelectedToast() {
        Logger.info("")

        let toastFormat = NSLocalizedString("CONVERSATION_PICKER_CAN_SELECT_NO_MORE_CONVERSATIONS",
                                            comment: "Momentarily shown to the user when attempting to select more conversations than is allowed. Embeds {{max number of conversations}} that can be selected.")

        let toastText = String(format: toastFormat, NSNumber(value: kMaxPickerSelection))

        let toastController = ToastController(text: toastText)

        let bottomInset = (view.bounds.height - tableView.frame.height)
        let kToastInset: CGFloat = bottomInset + 10
        toastController.presentToastView(fromBottomOfView: view, inset: kToastInset)
    }
}

// MARK: -

extension ConversationPickerViewController: UISearchBarDelegate {
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        firstly {
            buildSearchResults(searchText: searchText)
        }.then { [weak self] searchResults -> Promise<ConversationCollection> in
            guard let self = self else {
                throw PMKError.cancelled
            }

            return self.buildConversationCollection(searchResults: searchResults)
        }.done { [weak self] conversationCollection in
            guard let self = self else { return }

            self.conversationCollection = conversationCollection
            self.tableView.reloadData()
            self.restoreSelection(tableView: self.tableView)
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
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

// MARK: -

extension ConversationPickerViewController: ApprovalFooterDelegate {
    public func approvalFooterDelegateDidRequestProceed(_ approvalFooterView: ApprovalFooterView) {
        guard let delegate = delegate else {
            owsFailDebug("Missing delegate.")
            return
        }
        let conversations = delegate.selectedConversationsForConversationPicker
        guard conversations.count > 0 else {
            owsFailDebug("No conversations selected.")
            return
        }
        delegate.conversationPickerDidCompleteSelection(self)
    }

    public func approvalMode(_ approvalFooterView: ApprovalFooterView) -> ApprovalMode {
        return approvalMode
    }
}

// MARK: -

extension ConversationPickerViewController {
    private struct Strings {
        static let title = NSLocalizedString("CONVERSATION_PICKER_TITLE", comment: "navbar header")
        static let recentsSection = NSLocalizedString("CONVERSATION_PICKER_SECTION_RECENTS", comment: "table section header for section containing recent conversations")
        static let signalContactsSection = NSLocalizedString("CONVERSATION_PICKER_SECTION_SIGNAL_CONTACTS", comment: "table section header for section containing contacts")
        static let groupsSection = NSLocalizedString("CONVERSATION_PICKER_SECTION_GROUPS", comment: "table section header for section containing groups")
    }
}

// MARK: - ConversationPickerCell

private class ConversationPickerCell: ContactTableViewCell {
    static let reuseIdentifier = "ConversationPickerCell"

    // MARK: - UITableViewCell

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        selectedBadgeView.isHidden = !selected
        unselectedBadgeView.isHidden = selected
    }

    // MARK: - ContactTableViewCell

    public func configure(conversationItem: ConversationItem, transaction: SDSAnyReadTransaction) {
        if conversationItem.isBlocked {
            setAccessoryMessage(MessageStrings.conversationIsBlocked)
        } else {
            ows_setAccessoryView(
                buildAccessoryView(disappearingMessagesConfig: conversationItem.disappearingMessagesConfig)
            )
        }

        switch conversationItem.messageRecipient {
        case .contact(let address):
            super.configure(withRecipientAddress: address, transaction: transaction)
        case .group(let groupThread):
            super.configure(with: groupThread, transaction: transaction)
        }

        selectionStyle = .none
    }

    // MARK: - Subviews

    static let selectedBadgeImage = #imageLiteral(resourceName: "image_editor_checkmark_full").withRenderingMode(.alwaysTemplate)

    let selectionBadgeSize = CGSize(square: 20)
    lazy var selectionView: UIView = {
        let container = UIView()
        container.layoutMargins = .zero
        container.autoSetDimensions(to: selectionBadgeSize)

        container.addSubview(unselectedBadgeView)
        unselectedBadgeView.autoPinEdgesToSuperviewMargins()

        container.addSubview(selectedBadgeView)
        selectedBadgeView.autoPinEdgesToSuperviewMargins()

        return container
    }()

    func buildAccessoryView(disappearingMessagesConfig: OWSDisappearingMessagesConfiguration?) -> UIView {
        guard let disappearingMessagesConfig = disappearingMessagesConfig,
            disappearingMessagesConfig.isEnabled else {
            return selectionView
        }

        let timerView = DisappearingTimerConfigurationView(durationSeconds: disappearingMessagesConfig.durationSeconds)
        timerView.tintColor = Theme.middleGrayColor
        timerView.autoSetDimensions(to: CGSize(square: 44))
        timerView.setCompressionResistanceHigh()

        let stackView = UIStackView(arrangedSubviews: [timerView, selectionView])
        stackView.alignment = .center
        stackView.setCompressionResistanceHigh()
        return stackView
    }

    lazy var unselectedBadgeView: UIView = {
        let circleView = CircleView()
        circleView.autoSetDimensions(to: selectionBadgeSize)
        circleView.layer.borderWidth = 1.0
        circleView.layer.borderColor = Theme.outlineColor.cgColor
        return circleView
    }()

    lazy var selectedBadgeView: UIView = {
        let imageView = UIImageView()
        imageView.autoSetDimensions(to: selectionBadgeSize)
        imageView.image = ConversationPickerCell.selectedBadgeImage
        imageView.tintColor = .ows_accentBlue
        return imageView
    }()
}
