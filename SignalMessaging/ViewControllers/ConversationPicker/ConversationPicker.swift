//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public protocol ConversationPickerDelegate: AnyObject {
    func conversationPickerSelectionDidChange(_ conversationPickerViewController: ConversationPickerViewController)

    func conversationPickerDidCompleteSelection(_ conversationPickerViewController: ConversationPickerViewController)

    func conversationPickerCanCancel(_ conversationPickerViewController: ConversationPickerViewController) -> Bool

    func conversationPickerDidCancel(_ conversationPickerViewController: ConversationPickerViewController)

    func approvalMode(_ conversationPickerViewController: ConversationPickerViewController) -> ApprovalMode

    var conversationPickerHasTextInput: Bool { get }

    var conversationPickerTextInputDefaultText: String? { get }

    func conversationPickerDidBeginEditingText()

    func conversationPickerSearchBarActiveDidChange(_ conversationPickerViewController: ConversationPickerViewController)
}

// MARK: -

@objc
open class ConversationPickerViewController: OWSTableViewController2 {

    public weak var pickerDelegate: ConversationPickerDelegate?

    private let kMaxPickerSelection = 5

    public let selection: ConversationPickerSelection

    private let footerView = ApprovalFooterView()

    private lazy var searchBar: OWSSearchBar = {
        let searchBar = OWSSearchBar()
        searchBar.placeholder = CommonStrings.searchPlaceholder
        searchBar.delegate = self
        return searchBar
    }()

    private let searchBarWrapper: UIStackView = {
        let searchBarWrapper = UIStackView()
        searchBarWrapper.axis = .vertical
        searchBarWrapper.alignment = .fill
        return searchBarWrapper
    }()

    public var textInput: String? {
        footerView.textInput
    }

    private var conversationCollection: ConversationCollection = .empty {
        didSet {
            updateTableContents()
        }
    }

    public init(selection: ConversationPickerSelection) {
        self.selection = selection

        super.init()

        self.selectionBehavior = .toggleSelectionWithAction
        self.shouldAvoidKeyboard = true
        searchBarWrapper.addArrangedSubview(searchBar)
        self.topHeader = searchBarWrapper
        self.bottomFooter = footerView
    }

    private var approvalMode: ApprovalMode {
        pickerDelegate?.approvalMode(self) ?? .send
    }

    public func updateApprovalMode() { footerView.updateContents() }

    public var shouldShowSearchBar: Bool = true {
        didSet {
            if isViewLoaded {
                ensureSearchBarVisibility()
            }
        }
    }

    public var shouldHideSearchBarIfCancelled = false

    private func ensureSearchBarVisibility() {
        AssertIsOnMainThread()

        searchBar.isHidden = !shouldShowSearchBar
    }

    public func selectSearchBar() {
        AssertIsOnMainThread()

        shouldShowSearchBar = true
        searchBar.becomeFirstResponder()
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        if pickerDelegate?.conversationPickerCanCancel(self) ?? false {
            let cancelButton = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(onTouchCancelButton))
            self.navigationItem.leftBarButtonItem = cancelButton
        }

        ensureSearchBarVisibility()

        title = Strings.title

        tableView.allowsMultipleSelection = true
        tableView.register(ConversationPickerCell.self, forCellReuseIdentifier: ConversationPickerCell.reuseIdentifier)

        footerView.delegate = self

        conversationCollection = buildConversationCollection()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(blockListDidChange),
                                               name: BlockingManager.blockListDidChange,
                                               object: nil)
    }

    // MARK: - ConversationCollection

    private func restoreSelection() {
        AssertIsOnMainThread()

        tableView.indexPathsForSelectedRows?.forEach { tableView.deselectRow(at: $0, animated: false) }

        for selectedConversation in selection.conversations {
            guard let index = conversationCollection.indexPath(conversation: selectedConversation) else {
                // This can happen when restoring selection while the currently displayed results
                // are filtered.
                continue
            }
            tableView.selectRow(at: index, animated: false, scrollPosition: .none)
        }

        updateUIForCurrentSelection(animated: false)
    }

    func buildSearchResults(searchText: String) -> Promise<ComposeScreenSearchResultSet?> {
        guard searchText.count > 1 else {
            return Promise.value(nil)
        }

        return firstly(on: .global()) {
            Self.databaseStorage.read { transaction in
                self.fullTextSearcher.searchForComposeScreen(searchText: searchText,
                                                             omitLocalUser: false,
                                                             transaction: transaction)
            }
        }
    }

    func buildGroupItem(_ groupThread: TSGroupThread, transaction: SDSAnyReadTransaction) -> GroupConversationItem {
        let isBlocked = self.blockingManager.isThreadBlocked(groupThread)
        let dmConfig = groupThread.disappearingMessagesConfiguration(with: transaction)
        return GroupConversationItem(groupThreadId: groupThread.uniqueId,
                                     isBlocked: isBlocked,
                                     disappearingMessagesConfig: dmConfig)
    }

    func buildContactItem(_ address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> ContactConversationItem {
        let isBlocked = self.blockingManager.isAddressBlocked(address)
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

    fileprivate func buildConversationCollection() -> ConversationCollection {
        self.databaseStorage.read { transaction in
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
                guard thread.canSendChatMessagesToThread(ignoreAnnouncementOnly: true) else {
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
                                          groupConversations: groupItems,
                                          isSearchResults: false)
        }
    }

    fileprivate func buildConversationCollection(searchResults: ComposeScreenSearchResultSet?) -> Promise<ConversationCollection> {
        guard let searchResults = searchResults else {
            return Promise.value(buildConversationCollection())
        }

        return firstly(on: .global()) {
            Self.databaseStorage.read { transaction in
                let groupItems = searchResults.groupThreads.compactMap { groupThread -> GroupConversationItem? in
                    guard groupThread.canSendChatMessagesToThread(ignoreAnnouncementOnly: true) else {
                        return nil
                    }
                    return self.buildGroupItem(groupThread, transaction: transaction)
                }
                let contactItems = searchResults.signalAccounts.map { self.buildContactItem($0.recipientAddress, transaction: transaction) }

                return ConversationCollection(contactConversations: contactItems,
                                              recentConversations: [],
                                              groupConversations: groupItems,
                                              isSearchResults: true)
            }
        }
    }

    public func conversation(for indexPath: IndexPath) -> ConversationItem? {
        conversationCollection.conversation(for: indexPath)
    }

    public func conversation(for thread: TSThread) -> ConversationItem? {
        conversationCollection.conversation(for: thread)
    }

    // MARK: - Button Actions

    @objc func onTouchCancelButton() {
        pickerDelegate?.conversationPickerDidCancel(self)
    }

    @objc
    private func blockListDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        self.conversationCollection = buildConversationCollection()
    }

    private func updateTableContents() {
        AssertIsOnMainThread()

        self.defaultSeparatorInsetLeading = (OWSTableViewController2.cellHInnerMargin +
                                                CGFloat(ContactCellView.avatarDiameterPoints) +
                                                ContactCellView.avatarTextHSpacing)

        let conversationCollection = self.conversationCollection

        let contents = OWSTableContents()

        var hasContents = false

        // Recents Section
        do {
            let section = OWSTableSection()
            if !conversationCollection.recentConversations.isEmpty {
                section.headerTitle = Strings.recentsSection
                addConversations(toSection: section,
                                 conversations: conversationCollection.recentConversations)
                hasContents = true
            }
            contents.addSection(section)
        }

        // Contacts Section
        do {
            let section = OWSTableSection()
            if !conversationCollection.contactConversations.isEmpty {
                section.headerTitle = Strings.signalContactsSection
                addConversations(toSection: section,
                                 conversations: conversationCollection.contactConversations)
                hasContents = true
            }
            contents.addSection(section)
        }

        // Groups Section
        do {
            let section = OWSTableSection()
            if !conversationCollection.groupConversations.isEmpty {
                section.headerTitle = Strings.groupsSection
                addConversations(toSection: section,
                                 conversations: conversationCollection.groupConversations)
                hasContents = true
            }
            contents.addSection(section)
        }

        // "No matches" Section
        if conversationCollection.isSearchResults,
           !hasContents {
            let section = OWSTableSection()
            section.add(.label(withText: NSLocalizedString("CONVERSATION_SEARCH_NO_RESULTS",
                                                           comment: "keyboard toolbar label when no messages match the search string")))
            contents.addSection(section)
        }

        self.contents = contents
        restoreSelection()
    }

    private func addConversations(toSection section: OWSTableSection,
                                  conversations: [ConversationItem]) {
        for conversation in conversations {
            section.add(OWSTableItem(dequeueCellBlock: { tableView in
                guard let cell = tableView.dequeueReusableCell(withIdentifier: ConversationPickerCell.reuseIdentifier) as? ConversationPickerCell else {
                    owsFailDebug("Missing cell.")
                    return UITableViewCell()
                }
                Self.databaseStorage.read { transaction in
                    cell.configure(conversationItem: conversation, transaction: transaction)
                }
                return cell
            },
            actionBlock: { [weak self] in
                self?.didToggleSection(conversation: conversation)
            }))
        }
    }

    public override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard let indexPath = super.tableView(tableView, willSelectRowAt: indexPath) else {
            return nil
        }

        guard selection.conversations.count < kMaxPickerSelection else {
            showTooManySelectedToast()
            return nil
        }

        guard let conversation = conversation(for: indexPath) else {
            owsFailDebug("item was unexpectedly nil")
            return nil
        }

        guard !conversation.isBlocked else {
            showUnblockUI(conversation: conversation)
            return nil
        }

        return indexPath
    }

    private func showUnblockUI(conversation: ConversationItem) {
        switch conversation.messageRecipient {
        case .contact(let address):
            BlockListUIUtils.showUnblockAddressActionSheet(address,
                                                           from: self) { isStillBlocked in
                AssertIsOnMainThread()

                guard !isStillBlocked else {
                    return
                }

                self.conversationCollection = self.buildConversationCollection()
            }
        case .group(let groupThreadId):
            guard let groupThread = databaseStorage.read(block: { transaction in
                return TSGroupThread.anyFetchGroupThread(uniqueId: groupThreadId, transaction: transaction)
            }) else {
                owsFailDebug("Missing group thread for blocked thread")
                return
            }
            BlockListUIUtils.showUnblockThreadActionSheet(groupThread,
                                                          from: self) { isStillBlocked in
                AssertIsOnMainThread()

                guard !isStillBlocked else {
                    return
                }

                self.conversationCollection = self.buildConversationCollection()
            }
        }
    }

    fileprivate func didToggleSection(conversation: ConversationItem) {
        AssertIsOnMainThread()

        if selection.isSelected(conversation: conversation) {
            didDeselect(conversation: conversation)
        } else {
            didSelect(conversation: conversation)
        }
    }

    private func didSelect(conversation: ConversationItem) {
        AssertIsOnMainThread()

        let isBlocked: Bool = databaseStorage.write { transaction in
            guard let thread = conversation.thread(transaction: transaction) else {
                return false
            }
            return !thread.canSendChatMessagesToThread(ignoreAnnouncementOnly: false)
        }
        guard !isBlocked else {
            restoreSelection()
            showBlockedByAnnouncementOnlyToast()
            return
        }
        selection.add(conversation)
        updateUIForCurrentSelection(animated: true)
    }

    private func showBlockedByAnnouncementOnlyToast() {
        Logger.info("")

        let toastFormat = NSLocalizedString("CONVERSATION_PICKER_BLOCKED_BY_ANNOUNCEMENT_ONLY",
                                            comment: "Message indicating that only administrators can send message to an announcement-only group.")

        let toastText = String(format: toastFormat, NSNumber(value: kMaxPickerSelection))
        showToast(message: toastText)
    }

    private func didDeselect(conversation: ConversationItem) {
        AssertIsOnMainThread()

        selection.remove(conversation)
        updateUIForCurrentSelection(animated: true)
    }

    private func updateUIForCurrentSelection(animated: Bool) {
        let conversations = selection.conversations
        let labelText = conversations.map { $0.title }.joined(separator: ", ")
        footerView.setNamesText(labelText, animated: animated)
    }

    private func showTooManySelectedToast() {
        Logger.info("")

        let toastFormat = NSLocalizedString("CONVERSATION_PICKER_CAN_SELECT_NO_MORE_CONVERSATIONS",
                                            comment: "Momentarily shown to the user when attempting to select more conversations than is allowed. Embeds {{max number of conversations}} that can be selected.")

        let toastText = String(format: toastFormat, NSNumber(value: kMaxPickerSelection))
        showToast(message: toastText)
    }

    private func showToast(message: String) {
        Logger.info("")

        let toastController = ToastController(text: message)

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
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

    public func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
        pickerDelegate?.conversationPickerSearchBarActiveDidChange(self)
        restoreSelection()
    }

    public func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
        pickerDelegate?.conversationPickerSearchBarActiveDidChange(self)
        restoreSelection()
    }

    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = nil
        searchBar.resignFirstResponder()
        if shouldHideSearchBarIfCancelled {
            self.shouldShowSearchBar = false
        }
        conversationCollection = buildConversationCollection()
        pickerDelegate?.conversationPickerSearchBarActiveDidChange(self)
    }

    public var isSearchBarActive: Bool {
        searchBar.isFirstResponder
    }
}

// MARK: -

extension ConversationPickerViewController: ApprovalFooterDelegate {
    public func approvalFooterDelegateDidRequestProceed(_ approvalFooterView: ApprovalFooterView) {
        guard let pickerDelegate = pickerDelegate else {
            owsFailDebug("Missing delegate.")
            return
        }
        let conversations = selection.conversations
        guard conversations.count > 0 else {
            Logger.warn("No conversations selected.")
            return
        }
        pickerDelegate.conversationPickerDidCompleteSelection(self)
    }

    public func approvalMode(_ approvalFooterView: ApprovalFooterView) -> ApprovalMode {
        return approvalMode
    }

    public var approvalFooterHasTextInput: Bool {
        pickerDelegate?.conversationPickerHasTextInput ?? false
    }

    public var approvalFooterTextInputDefaultText: String? {
        pickerDelegate?.conversationPickerTextInputDefaultText ?? nil
    }

    public func approvalFooterDidBeginEditingText() {
        AssertIsOnMainThread()

        pickerDelegate?.conversationPickerDidBeginEditingText()
        shouldShowSearchBar = false
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
    open override class var reuseIdentifier: String { "ConversationPickerCell" }

    // MARK: - UITableViewCell

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        applySelection()
    }

    private func applySelection() {
        selectedBadgeView.isHidden = !self.isSelected
        unselectedBadgeView.isHidden = self.isSelected
    }

    // MARK: - ContactTableViewCell

    public func configure(conversationItem: ConversationItem, transaction: SDSAnyReadTransaction) {
        let content: ConversationContent
        switch conversationItem.messageRecipient {
        case .contact(let address):
            content = ConversationContent.forAddress(address, transaction: transaction)
        case .group(let groupThreadId):
            guard let groupThread = TSGroupThread.anyFetchGroupThread(
                uniqueId: groupThreadId,
                transaction: transaction
            ) else {
                owsFailDebug("Failed to find group thread")
                return
            }
            content = ConversationContent.forThread(groupThread)
        }
        let configuration = ContactCellConfiguration(content: content,
                                                     localUserDisplayMode: .noteToSelf)
        if conversationItem.isBlocked {
            configuration.accessoryMessage = MessageStrings.conversationIsBlocked
        } else {
            configuration.accessoryView = buildAccessoryView(disappearingMessagesConfig: conversationItem.disappearingMessagesConfig)
        }
        super.configure(configuration: configuration, transaction: transaction)

        // Apply theme.
        unselectedBadgeView.layer.borderColor = Theme.primaryIconColor.cgColor

        selectionStyle = .none
        applySelection()
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

    func buildAccessoryView(disappearingMessagesConfig: OWSDisappearingMessagesConfiguration?) -> ContactCellAccessoryView {

        selectionView.removeFromSuperview()
        let selectionWrapper = ManualLayoutView.wrapSubviewUsingIOSAutoLayout(selectionView)

        guard let disappearingMessagesConfig = disappearingMessagesConfig,
              disappearingMessagesConfig.isEnabled else {
            return ContactCellAccessoryView(accessoryView: selectionWrapper,
                                            size: selectionBadgeSize)
        }

        let timerView = DisappearingTimerConfigurationView(durationSeconds: disappearingMessagesConfig.durationSeconds)
        timerView.tintColor = Theme.middleGrayColor
        let timerSize = CGSize(square: 44)

        let stackView = ManualStackView(name: "stackView")
        let stackConfig = OWSStackView.Config(axis: .horizontal,
                                              alignment: .center,
                                              spacing: 0,
                                              layoutMargins: .zero)
        let stackMeasurement = stackView.configure(config: stackConfig,
                                                   subviews: [timerView, selectionWrapper],
                                                   subviewInfos: [
                                                    timerSize.asManualSubviewInfo,
                                                    selectionBadgeSize.asManualSubviewInfo
                                                   ])
        let stackSize = stackMeasurement.measuredSize
        return ContactCellAccessoryView(accessoryView: stackView, size: stackSize)
    }

    lazy var unselectedBadgeView: UIView = {
        let circleView = CircleView()
        circleView.autoSetDimensions(to: selectionBadgeSize)
        circleView.layer.borderWidth = 1.0
        circleView.layer.borderColor = Theme.primaryIconColor.cgColor
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

// MARK: -

extension ConversationPickerViewController: ConversationPickerSelectionDelegate {
    func conversationPickerSelectionDidChange() {
        AssertIsOnMainThread()

        pickerDelegate?.conversationPickerSelectionDidChange(self)
    }
}

// MARK: -

protocol ConversationPickerSelectionDelegate: AnyObject {
    func conversationPickerSelectionDidChange()
}

// MARK: -

public class ConversationPickerSelection {
    fileprivate weak var delegate: ConversationPickerSelectionDelegate?

    public private(set) var conversations: [ConversationItem] = []

    public required init() {}

    public func add(_ conversation: ConversationItem) {
        conversations.append(conversation)
        delegate?.conversationPickerSelectionDidChange()
    }

    public func remove(_ conversation: ConversationItem) {
        conversations.removeAll { $0.messageRecipient == conversation.messageRecipient }
        delegate?.conversationPickerSelectionDidChange()
    }

    public func isSelected(conversation: ConversationItem) -> Bool {
        !conversations.filter { $0.messageRecipient == conversation.messageRecipient }.isEmpty
    }
}

// MARK: -

private struct ConversationCollection {
    static let empty: ConversationCollection = ConversationCollection(contactConversations: [],
                                                                      recentConversations: [],
                                                                      groupConversations: [],
                                                                      isSearchResults: false)

    let contactConversations: [ConversationItem]
    let recentConversations: [ConversationItem]
    let groupConversations: [ConversationItem]
    let isSearchResults: Bool

    var allConversations: [ConversationItem] {
        recentConversations + contactConversations + groupConversations
    }

    private func conversations(section: Section) -> [ConversationItem] {
        switch section {
        case .recents:
            return recentConversations
        case .signalContacts:
            return contactConversations
        case .groups:
            return groupConversations
        }
    }

    private enum Section: Int, CaseIterable {
        case recents, signalContacts, groups
    }

    fileprivate func indexPath(conversation: ConversationItem) -> IndexPath? {
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

    fileprivate func conversation(for indexPath: IndexPath) -> ConversationItem? {
        guard let section = Section(rawValue: indexPath.section) else {
            owsFailDebug("section was unexpectedly nil")
            return nil
        }
        return conversations(section: section)[indexPath.row]
    }

    fileprivate func conversation(for thread: TSThread) -> ConversationItem? {
        allConversations.first { item in
            if let thread = thread as? TSGroupThread, case .group(let otherThreadId) = item.messageRecipient {
                return thread.uniqueId == otherThreadId
            } else if let thread = thread as? TSContactThread, case .contact(let otherAddress) = item.messageRecipient {
                return thread.contactAddress == otherAddress
            } else {
                return false
            }
        }
    }
}
