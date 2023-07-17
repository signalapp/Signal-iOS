//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import Foundation
import SignalServiceKit
import SignalUI

/* From BonMot 6.0.0: If you're targeting iOS 15 or higher, you may want to check out [AttributedString](https://developer.apple.com/documentation/foundation/attributedstring) instead.
 If you're an existing user of BonMot using Xcode 13, you may want to add the following `typealias` somewhere in your project to avoid a conflict with `Foundation.StringStyle`: */
typealias StringStyle = BonMot.StringStyle

public protocol ConversationSearchViewDelegate: AnyObject {
    func conversationSearchViewWillBeginDragging()
}

public class ConversationSearchViewController: UITableViewController {

    // MARK: -

    public weak var delegate: ConversationSearchViewDelegate?

    private var hasEverAppeared = false
    private var lastReloadDate: Date?
    private let cellContentCache = LRUCache<String, CLVCellContentToken>(maxSize: 256)

    private lazy var spoilerAnimationManager = SpoilerAnimationManager()

    public var searchText = "" {
        didSet {
            AssertIsOnMainThread()

            // Use a slight delay to debounce updates.
            refreshSearchResults()
        }
    }

    var searchResultSet: HomeScreenSearchResultSet = HomeScreenSearchResultSet.empty {
        didSet {
            AssertIsOnMainThread()

            updateSeparators()
        }
    }
    private var lastSearchText: String?

    var searcher: FullTextSearcher {
        return FullTextSearcher.shared
    }

    enum SearchSection: Int {
        case noResults
        case contactThreads
        case groupThreads
        case contacts
        case messages
    }

    private var hasThemeChanged = false

    class var matchSnippetStyle: StringStyle {
        StringStyle(
            .color(Theme.secondaryTextAndIconColor),
            .xmlRules([
                .style(FullTextSearchFinder.matchTag, StringStyle(.font(UIFont.dynamicTypeBody2.semibold())))
            ])
        )
    }

    // MARK: View Lifecycle

    init() {
        super.init(style: .grouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.separatorColor = .clear
        tableView.separatorInset = .zero
        tableView.separatorStyle = .none

        tableView.register(EmptySearchResultCell.self, forCellReuseIdentifier: EmptySearchResultCell.reuseIdentifier)
        tableView.register(ChatListCell.self, forCellReuseIdentifier: ChatListCell.reuseIdentifier)
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)

        databaseStorage.appendDatabaseChangeDelegate(self)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: .themeDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(blockListDidChange),
                                               name: BlockingManager.blockListDidChange,
                                               object: nil)

        applyTheme()
        updateSeparators()
    }

    private func reloadTableData() {
        self.lastReloadDate = Date()
        self.cellContentCache.clear()
        self.tableView.reloadData()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard hasThemeChanged else {
            return
        }
        hasThemeChanged = false

        applyTheme()
        reloadTableData()
        self.hasEverAppeared = true
    }

    @objc
    internal func themeDidChange(notification: NSNotification) {
        AssertIsOnMainThread()

        applyTheme()
        reloadTableData()

        hasThemeChanged = true
    }

    @objc
    private func blockListDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        refreshSearchResults()
    }

    private func applyTheme() {
        AssertIsOnMainThread()

        self.view.backgroundColor = Theme.backgroundColor
        self.tableView.backgroundColor = Theme.backgroundColor
    }

    private func updateSeparators() {
        AssertIsOnMainThread()

        self.tableView.separatorStyle = (searchResultSet.isEmpty
                                            ? UITableViewCell.SeparatorStyle.none
                                            : UITableViewCell.SeparatorStyle.singleLine)
    }

    // MARK: UITableViewDelegate

    public override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard let searchSection = SearchSection(rawValue: indexPath.section) else {
            owsFailDebug("unknown section selected.")
            return nil
        }

        switch searchSection {
        case .noResults:
            return nil
        case .contactThreads, .groupThreads, .contacts, .messages:
            return indexPath
        }
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)

        guard let searchSection = SearchSection(rawValue: indexPath.section) else {
            owsFailDebug("unknown section selected.")
            return
        }

        switch searchSection {
        case .noResults:
            owsFailDebug("shouldn't be able to tap 'no results' section")
        case .contactThreads:
            let sectionResults = searchResultSet.contactThreads
            guard let searchResult = sectionResults[safe: indexPath.row] else {
                owsFailDebug("unknown row selected.")
                return
            }

            let thread = searchResult.thread
            SignalApp.shared.presentConversationForThread(thread.threadRecord, action: .compose, animated: true)
        case .groupThreads:
            let sectionResults = searchResultSet.groupThreads
            guard let searchResult = sectionResults[safe: indexPath.row] else {
                owsFailDebug("unknown row selected.")
                return
            }

            let thread = searchResult.thread
            SignalApp.shared.presentConversationForThread(thread.threadRecord, action: .compose, animated: true)
        case .contacts:
            let sectionResults = searchResultSet.contacts
            guard let searchResult = sectionResults[safe: indexPath.row] else {
                owsFailDebug("unknown row selected.")
                return
            }

            SignalApp.shared.presentConversationForAddress(searchResult.recipientAddress, action: .compose, animated: true)

        case .messages:
            let sectionResults = searchResultSet.messages
            guard let searchResult = sectionResults[safe: indexPath.row] else {
                owsFailDebug("unknown row selected.")
                return
            }

            let thread = searchResult.thread
            SignalApp.shared.presentConversationForThread(thread.threadRecord,
                                                            focusMessageId: searchResult.messageId,
                                                            animated: true)
        }
    }

    public override func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        AssertIsOnMainThread()

        guard let cell = cell as? ChatListCell else {
            return
        }
        cell.isCellVisible = true
    }

    public override func tableView(
        _ tableView: UITableView,
        didEndDisplaying cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        AssertIsOnMainThread()

        guard let cell = cell as? ChatListCell else {
            return
        }
        cell.isCellVisible = false
    }

    // MARK: UITableViewDataSource

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let searchSection = SearchSection(rawValue: section) else {
            owsFailDebug("unknown section: \(section)")
            return 0
        }

        switch searchSection {
        case .noResults:
            return searchResultSet.isEmpty ? 1 : 0
        case .contactThreads:
            return searchResultSet.contactThreads.count
        case .groupThreads:
            return searchResultSet.groupThreads.count
        case .contacts:
            return searchResultSet.contacts.count
        case .messages:
            return searchResultSet.messages.count
        }
    }

    public override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        AssertIsOnMainThread()

        guard let searchSection = SearchSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return UITableView.automaticDimension
        }

        switch searchSection {
        case .noResults, .contacts:
            return UITableView.automaticDimension
        case .contactThreads, .groupThreads, .messages:
            guard let configuration = self.cellConfiguration(searchSection: searchSection, row: indexPath.row) else {
                owsFailDebug("Missing configuration.")
                return UITableView.automaticDimension
            }
            let cellContentToken = cellContentToken(forConfiguration: configuration)
            return ChatListCell.measureCellHeight(cellContentToken: cellContentToken)
        }
    }

    private func cellContentToken(forConfiguration configuration: ChatListCell.Configuration, useCache: Bool = true) -> CLVCellContentToken {
        AssertIsOnMainThread()

        // If we have an existing CLVCellContentToken, use it.
        // Cell measurement/arrangement is expensive.
        let cacheKey = "\(configuration.thread.threadRecord.uniqueId).\(configuration.overrideSnippet?.text.hashValue ?? 0)"
        if useCache {
            if let cellContentToken = cellContentCache.get(key: cacheKey) {
                return cellContentToken
            }
        }

        let cellContentToken = ChatListCell.buildCellContentToken(forConfiguration: configuration)
        cellContentCache.set(key: cacheKey, value: cellContentToken)
        return cellContentToken
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        guard let searchSection = SearchSection(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch searchSection {
        case .noResults:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: EmptySearchResultCell.reuseIdentifier) as? EmptySearchResultCell else {
                owsFailDebug("cell was unexpectedly nil")
                return UITableViewCell()
            }

            guard indexPath.row == 0 else {
                owsFailDebug("searchResult was unexpected index")
                return UITableViewCell()
            }

            OWSTableItem.configureCell(cell)

            let searchText = self.searchResultSet.searchText
            cell.configure(searchText: searchText)
            return cell
        case .contacts:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                owsFailDebug("cell was unexpectedly nil")
                return UITableViewCell()
            }

            guard let searchResult = self.searchResultSet.contacts[safe: indexPath.row] else {
                owsFailDebug("searchResult was unexpectedly nil")
                return UITableViewCell()
            }
            cell.configureWithSneakyTransaction(address: searchResult.signalAccount.recipientAddress,
                                                localUserDisplayMode: .noteToSelf)
            return cell
        case .contactThreads, .groupThreads, .messages:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ChatListCell.reuseIdentifier) as? ChatListCell else {
                owsFailDebug("cell was unexpectedly nil")
                return UITableViewCell()
            }
            guard let configuration = self.cellConfiguration(searchSection: searchSection, row: indexPath.row) else {
                owsFailDebug("Missing configuration.")
                return UITableViewCell()
            }
            let cellContentToken = cellContentToken(forConfiguration: configuration)
            cell.configure(cellContentToken: cellContentToken, spoilerAnimationManager: spoilerAnimationManager)
            return cell
        }
    }

    private func cellConfiguration(searchSection: SearchSection, row: Int) -> ChatListCell.Configuration? {
        AssertIsOnMainThread()

        let lastReloadDate: Date? = {
            guard self.hasEverAppeared else {
                return nil
            }
            return self.lastReloadDate
        }()

        switch searchSection {
        case .noResults:
            owsFailDebug("Invalid section.")
            return nil
        case .contactThreads:
            guard let searchResult = self.searchResultSet.contactThreads[safe: row] else {
                owsFailDebug("searchResult was unexpectedly nil")
                return nil
            }
            return ChatListCell.Configuration(
                thread: searchResult.thread,
                lastReloadDate: lastReloadDate,
                isBlocked: isBlocked(thread: searchResult.thread)
            )
        case .groupThreads:
            guard let searchResult = self.searchResultSet.groupThreads[safe: row] else {
                owsFailDebug("searchResult was unexpectedly nil")
                return nil
            }
            let overrideSnippet: ChatListCell.Configuration.OverrideSnippet?
            if let snippet = searchResult.matchedMembersSnippet?.styled(with: Self.matchSnippetStyle) {
                overrideSnippet = .init(text: .attributedText(snippet), config: .conversationListSearchResultSnippet())
            } else {
                overrideSnippet = nil
            }
            return ChatListCell.Configuration(
                thread: searchResult.thread,
                lastReloadDate: lastReloadDate,
                isBlocked: isBlocked(thread: searchResult.thread),
                overrideSnippet: overrideSnippet,
                overrideDate: nil
            )
        case .contacts:
            owsFailDebug("Invalid section.")
            return nil
        case .messages:
            guard let searchResult = self.searchResultSet.messages[safe: row] else {
                owsFailDebug("searchResult was unexpectedly nil")
                return nil
            }
            var overrideDate: Date?
            if searchResult.messageId != nil {
                if let messageDate = searchResult.messageDate {
                    overrideDate = messageDate
                } else {
                    owsFailDebug("message search result is missing message timestamp")
                }
            }
            let overrideSnippet: ChatListCell.Configuration.OverrideSnippet?
            if let snippet = searchResult.snippet {
                overrideSnippet = .init(text: snippet, config: .conversationListSearchResultSnippet())
            } else {
                overrideSnippet = nil
            }
            return ChatListCell.Configuration(
                thread: searchResult.thread,
                lastReloadDate: lastReloadDate,
                isBlocked: isBlocked(thread: searchResult.thread),
                overrideSnippet: overrideSnippet,
                overrideDate: overrideDate
            )
        }
    }

    public override func numberOfSections(in tableView: UITableView) -> Int {
        return 5
    }

    public override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView()
    }

    public override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        .leastNonzeroMagnitude
    }

    public override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard nil != self.tableView(tableView, titleForHeaderInSection: section) else {
            return .leastNonzeroMagnitude
        }
        return UITableView.automaticDimension
    }

    public override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let title = self.tableView(tableView, titleForHeaderInSection: section) else {
            return UIView()
        }

        let textView = LinkingTextView()
        textView.textColor = Theme.isDarkThemeEnabled ? UIColor.ows_gray05 : UIColor.ows_gray90
        textView.font = UIFont.dynamicTypeBodyClamped.semibold()
        textView.text = title

        var textContainerInset = UIEdgeInsets(
            top: 14,
            left: OWSTableViewController2.cellHOuterLeftMargin(in: view),
            bottom: 8,
            right: OWSTableViewController2.cellHOuterRightMargin(in: view)
        )
        textContainerInset.left += tableView.safeAreaInsets.left
        textContainerInset.right += tableView.safeAreaInsets.right
        textView.textContainerInset = textContainerInset

        return textView
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let searchSection = SearchSection(rawValue: section) else {
            owsFailDebug("unknown section: \(section)")
            return nil
        }

        switch searchSection {
        case .noResults:
            return nil
        case .contactThreads:
            if searchResultSet.contactThreads.count > 0 {
                return OWSLocalizedString("SEARCH_SECTION_CONVERSATIONS", comment: "section header for search results that match existing 1:1 chats")
            } else {
                return nil
            }
        case .groupThreads:
            if searchResultSet.groupThreads.count > 0 {
                return OWSLocalizedString("SEARCH_SECTION_GROUPS", comment: "section header for search results that match existing groups")
            } else {
                return nil
            }
        case .contacts:
            if searchResultSet.contacts.count > 0 {
                return OWSLocalizedString("SEARCH_SECTION_CONTACTS", comment: "section header for search results that match a contact who doesn't have an existing conversation")
            } else {
                return nil
            }
        case .messages:
            if searchResultSet.messages.count > 0 {
                return OWSLocalizedString("SEARCH_SECTION_MESSAGES", comment: "section header for search results that match a message in a conversation")
            } else {
                return nil
            }
        }
    }

    public override func tableView(_ tableView: UITableView,
                                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        return trailingSwipeActionsConfiguration(for: getThreadViewModelFor(indexPath: indexPath))
    }

    public override func tableView(_ tableView: UITableView,
                                   leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        return leadingSwipeActionsConfiguration(for: getThreadViewModelFor(indexPath: indexPath))
    }

    // MARK: Update Search Results

    var refreshTimer: Timer?

    private func refreshSearchResults() {
        AssertIsOnMainThread()

        guard !searchResultSet.isEmpty else {
            // To avoid incorrectly showing the "no results" state,
            // always search immediately if the current result set is empty.
            refreshTimer?.invalidate()
            refreshTimer = nil

            updateSearchResults(searchText: searchText)
            return
        }

        if refreshTimer != nil {
            // Don't start a new refresh timer if there's already one active.
            return
        }

        refreshTimer?.invalidate()
        refreshTimer = WeakTimer.scheduledTimer(timeInterval: 0.1, target: self, userInfo: nil, repeats: false) { [weak self] _ in
            guard let strongSelf = self else {
                return
            }

            strongSelf.updateSearchResults(searchText: strongSelf.searchText)
            strongSelf.refreshTimer = nil
        }
    }

    private let currentSearchCounter = AtomicUInt(0, lock: AtomicLock())

    private func updateSearchResults(searchText: String) {
        let searchText = searchText.stripped
        let lastSearchText = self.lastSearchText
        self.lastSearchText = searchText

        if searchText != lastSearchText {
            // The query has changed; perform a search.
        } else if tableView.visibleCells.contains(where: { $0 is ChatListCell }) {
            // The database may have been updated, and that'll lead to a duplicate
            // query for the same search text. In that case, perform a search if
            // there's a cell that needs to be updated.
        } else {
            // Nothing has changed, so don't perform a search.
            return
        }

        currentSearchCounter.increment()
        let searchCounter = currentSearchCounter.get()

        let isCanceled: () -> Bool = { [weak currentSearchCounter] in currentSearchCounter?.get() != searchCounter }

        fetchSearchResults(
            searchText: searchText,
            isCanceled: isCanceled
        ).done(on: DispatchQueue.main) { [weak self] searchResultSet in
            guard let self, let searchResultSet, !isCanceled() else {
                return
            }
            self.searchResultSet = searchResultSet
            self.reloadTableData()
        }
    }

    private func fetchSearchResults(searchText: String, isCanceled: @escaping () -> Bool) -> Guarantee<HomeScreenSearchResultSet?> {
        if searchText.isEmpty {
            return .value(.empty)
        }

        let (result, future) = Guarantee<HomeScreenSearchResultSet?>.pending()
        databaseStorage.asyncRead { [weak self] transaction in
            future.resolve(self?.searcher.searchForHomeScreen(
                searchText: searchText,
                isCanceled: isCanceled,
                transaction: transaction
            ))
        }
        return result
    }

    // MARK: -

    private func getThreadViewModelFor(indexPath: IndexPath) -> ThreadViewModel? {
        if let searchSection = SearchSection(rawValue: indexPath.section) {
            if searchSection == .contactThreads {
                return searchResultSet.contactThreads[indexPath.row].thread
            } else if searchSection == .groupThreads {
                return searchResultSet.groupThreads[indexPath.row].thread
            }
        }
        return nil
    }

    private func isBlocked(thread: ThreadViewModel) -> Bool { thread.isBlocked }
}

// MARK: - UIScrollViewDelegate

extension ConversationSearchViewController {
    public override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        delegate?.conversationSearchViewWillBeginDragging()
    }
}

// MARK: -

class EmptySearchResultCell: UITableViewCell {
    static let reuseIdentifier = "EmptySearchResultCell"

    let messageLabel: UILabel
    let activityIndicator = UIActivityIndicatorView(style: .large)
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        self.messageLabel = UILabel()
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        self.selectionStyle = .none

        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 3

        contentView.addSubview(messageLabel)

        messageLabel.autoSetDimension(.height, toSize: 150)

        messageLabel.autoPinEdge(toSuperviewMargin: .top, relation: .greaterThanOrEqual)
        messageLabel.autoPinEdge(toSuperviewMargin: .leading, relation: .greaterThanOrEqual)
        messageLabel.autoPinEdge(toSuperviewMargin: .bottom, relation: .greaterThanOrEqual)
        messageLabel.autoPinEdge(toSuperviewMargin: .trailing, relation: .greaterThanOrEqual)

        messageLabel.autoVCenterInSuperview()
        messageLabel.autoHCenterInSuperview()

        messageLabel.setContentHuggingHigh()
        messageLabel.setCompressionResistanceHigh()

        contentView.addSubview(activityIndicator)
        activityIndicator.autoCenterInSuperview()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(searchText: String) {
        if searchText.isEmpty {
            activityIndicator.color = Theme.primaryIconColor
            activityIndicator.isHidden = false
            activityIndicator.startAnimating()
            messageLabel.isHidden = true
            messageLabel.text = nil
        } else {
            activityIndicator.stopAnimating()
            activityIndicator.isHidden = true
            messageLabel.isHidden = false

            let format = OWSLocalizedString(
                "HOME_VIEW_SEARCH_NO_RESULTS_FORMAT",
                comment: "Format string when search returns no results. Embeds {{search term}}"
            )
            messageLabel.text = String(format: format, searchText)

            messageLabel.textColor = Theme.primaryTextColor
            messageLabel.font = UIFont.dynamicTypeBody
        }
    }
}

// MARK: -

extension ConversationSearchViewController: DatabaseChangeDelegate {

    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        AssertIsOnMainThread()

        guard databaseChanges.didUpdateThreads || databaseChanges.didUpdateInteractions else {
            return
        }

        refreshSearchResults()
    }

    public func databaseChangesDidUpdateExternally() {
        AssertIsOnMainThread()

        refreshSearchResults()
    }

    public func databaseChangesDidReset() {
        AssertIsOnMainThread()

        refreshSearchResults()
    }
}

// MARK: -

extension ConversationSearchViewController: ThreadSwipeHandler {

    func updateUIAfterSwipeAction() { }
}
