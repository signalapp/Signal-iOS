//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import SignalServiceKit
import SignalUI

/* From BonMot 6.0.0: If you're targeting iOS 15 or higher, you may want to check out [AttributedString](https://developer.apple.com/documentation/foundation/attributedstring) instead.
 If you're an existing user of BonMot using Xcode 13, you may want to add the following `typealias` somewhere in your project to avoid a conflict with `Foundation.StringStyle`: */
typealias StringStyle = BonMot.StringStyle

protocol ConversationSearchViewDelegate: AnyObject {
    func conversationSearchViewWillBeginDragging()
    func conversationSearchDidSelectRow()
}

class ConversationSearchViewController: OWSViewController {

    weak var delegate: ConversationSearchViewDelegate?

    private var hasEverAppeared = false
    private var lastReloadDate: Date?
    private let cellContentCache = LRUCache<String, CLVCellContentToken>(maxSize: 256)

    private lazy var spoilerAnimationManager = SpoilerAnimationManager()

    enum SearchSection: Int {
        case noResults
        case contactThreads
        case groupThreads
        case contacts
        case messages
    }

    private var hasThemeChanged = false

    // MARK: View Controller

    override init() {
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .Signal.background
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.separatorColor = .clear
        tableView.separatorInset = .zero
        tableView.separatorStyle = .none

        tableView.register(EmptySearchResultCell.self, forCellReuseIdentifier: EmptySearchResultCell.reuseIdentifier)
        tableView.register(ChatListCell.self, forCellReuseIdentifier: ChatListCell.reuseIdentifier)
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        tableView.autoPinHeight(toHeightOf: view)
        tableViewHorizontalEdgeConstraints = [
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: tableView.trailingAnchor),
        ]
        NSLayoutConstraint.activate(tableViewHorizontalEdgeConstraints)
        updateTableViewPaddingIfNeeded()

        DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(blockListDidChange),
            name: BlockingManager.blockListDidChange,
            object: nil,
        )

        updateSeparators()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard hasThemeChanged else {
            return
        }
        hasThemeChanged = false

        reloadTableData()
        self.hasEverAppeared = true
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateTableViewPaddingIfNeeded()
    }

    override func themeDidChange() {
        super.themeDidChange()

        reloadTableData()

        hasThemeChanged = true
    }

    @objc
    private func blockListDidChange(_ notification: NSNotification) {
        refreshSearchResults()
    }

    // MARK: Table View

    private let tableView = UITableView(frame: .zero, style: .grouped)

    /// Set to `true` when list is displayed in split view controller's "sidebar" on iOS 26 and later.
    /// Setting this to `true` would add an extra padding on both sides of the table view.
    /// This value is also passed down to table view cells that make their own layout choices based on the value.
    private var useSidebarTableViewCellAppearance = false {
        didSet {
            guard oldValue != useSidebarTableViewCellAppearance else { return }
            tableViewHorizontalEdgeConstraints.forEach {
                $0.constant = useSidebarTableViewCellAppearance ? 16 : 0
            }
            tableView.reloadData()
        }
    }

    private var tableViewHorizontalEdgeConstraints: [NSLayoutConstraint] = []

    /// iOS 26+: checks if this VC is displayed in the collapsed split view controller and updates `useSidebarCallListCellAppearance` accordingly.
    /// Does nothing on prior iOS versions.
    private func updateTableViewPaddingIfNeeded() {
        guard #available(iOS 26, *) else { return }

        if let splitViewController = presentingViewController?.splitViewController, !splitViewController.isCollapsed {
            useSidebarTableViewCellAppearance = true
        } else {
            useSidebarTableViewCellAppearance = false
        }
    }

    private func reloadTableData() {
        lastReloadDate = Date()
        cellContentCache.clear()
        tableView.reloadData()
    }

    private func updateSeparators() {
        tableView.separatorStyle = searchResultSet.isEmpty ? .none : .singleLine
    }

    // MARK: Search

    // Search is triggered with this is set externally by ChatListViewController.
    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }

            // Use a slight delay to debounce updates.
            refreshSearchResults()
        }
    }

    private var searchResultSet: HomeScreenSearchResultSet = HomeScreenSearchResultSet.empty {
        didSet {
            updateSeparators()
        }
    }

    private var lastSearchText: String?

    private var refreshTimer: Timer?

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

        refreshTimer = WeakTimer.scheduledTimer(timeInterval: 0.1, target: self, userInfo: nil, repeats: false) { [weak self] _ in
            guard let strongSelf = self else {
                return
            }

            strongSelf.updateSearchResults(searchText: strongSelf.searchText)
            strongSelf.refreshTimer = nil
        }
    }

    private var currentSearchTask: Task<Void, Never>?

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

        currentSearchTask?.cancel()
        currentSearchTask = Task {
            let searchResultSet: HomeScreenSearchResultSet
            do throws(CancellationError) {
                searchResultSet = try await fetchSearchResults(searchText: searchText)
                if Task.isCancelled {
                    throw CancellationError()
                }
            } catch {
                return
            }
            self.searchResultSet = searchResultSet
            self.reloadTableData()
        }
    }

    private nonisolated func fetchSearchResults(searchText: String) async throws(CancellationError) -> HomeScreenSearchResultSet {
        if searchText.isEmpty {
            return .empty
        }

        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        return try databaseStorage.read { tx throws(CancellationError) in
            return try FullTextSearcher.shared.searchForHomeScreen(searchText: searchText, tx: tx)
        }
    }
}

// MARK: -

extension ConversationSearchViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
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

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)

        guard let searchSection = SearchSection(rawValue: indexPath.section) else {
            owsFailDebug("unknown section selected.")
            return
        }

        delegate?.conversationSearchDidSelectRow()

        switch searchSection {
        case .noResults:
            owsFailDebug("shouldn't be able to tap 'no results' section")
        case .contactThreads:
            let sectionResults = searchResultSet.contactThreadResults
            guard let searchResult = sectionResults[safe: indexPath.row] else {
                owsFailDebug("unknown row selected.")
                return
            }

            let threadViewModel = searchResult.threadViewModel
            SignalApp.shared.presentConversationForThread(threadUniqueId: threadViewModel.threadUniqueId, action: .compose, animated: true)
        case .groupThreads:
            let sectionResults = searchResultSet.groupThreadResults
            guard let searchResult = sectionResults[safe: indexPath.row] else {
                owsFailDebug("unknown row selected.")
                return
            }

            let threadViewModel = searchResult.threadViewModel
            SignalApp.shared.presentConversationForThread(threadUniqueId: threadViewModel.threadUniqueId, action: .compose, animated: true)
        case .contacts:
            let sectionResults = searchResultSet.contactResults
            guard let searchResult = sectionResults[safe: indexPath.row] else {
                owsFailDebug("unknown row selected.")
                return
            }

            SignalApp.shared.presentConversationForAddress(searchResult.recipientAddress, action: .compose, animated: true)
        case .messages:
            let sectionResults = searchResultSet.messageResults
            guard let searchResult = sectionResults[safe: indexPath.row] else {
                owsFailDebug("unknown row selected.")
                return
            }

            let threadViewModel = searchResult.threadViewModel
            SignalApp.shared.presentConversationForThread(
                threadUniqueId: threadViewModel.threadUniqueId,
                focusMessageId: searchResult.messageId,
                animated: true,
            )
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let cell = cell as? ChatListCell else { return }

        cell.isCellVisible = true
    }

    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let cell = cell as? ChatListCell else { return }

        cell.isCellVisible = false
    }
}

// MARK: -

extension ConversationSearchViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let searchSection = SearchSection(rawValue: section) else {
            owsFailDebug("unknown section: \(section)")
            return 0
        }

        switch searchSection {
        case .noResults:
            return searchResultSet.isEmpty ? 1 : 0
        case .contactThreads:
            return searchResultSet.contactThreadResults.count
        case .groupThreads:
            return searchResultSet.groupThreadResults.count
        case .contacts:
            return searchResultSet.contactResults.count
        case .messages:
            return searchResultSet.messageResults.count
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let searchSection = SearchSection(rawValue: indexPath.section) else {
            owsFailDebug("Invalid section: \(indexPath.section).")
            return UITableView.automaticDimension
        }

        switch searchSection {
        case .noResults, .contacts:
            return UITableView.automaticDimension
        case .contactThreads, .groupThreads, .messages:
            guard let configuration = cellConfiguration(searchSection: searchSection, row: indexPath.row) else {
                owsFailDebug("Missing configuration.")
                return UITableView.automaticDimension
            }
            let cellContentToken = cellContentToken(forConfiguration: configuration)
            return ChatListCell.measureCellHeight(cellContentToken: cellContentToken)
        }
    }

    private func cellContentToken(forConfiguration configuration: ChatListCell.Configuration, useCache: Bool = true) -> CLVCellContentToken {

        // If we have an existing CLVCellContentToken, use it.
        // Cell measurement/arrangement is expensive.
        let cacheKey = "\(configuration.threadViewModel.threadRecord.uniqueId).\(configuration.overrideSnippet?.text.hashValue ?? 0)"
        if useCache {
            if let cellContentToken = cellContentCache.get(key: cacheKey) {
                return cellContentToken
            }
        }

        let cellContentToken = ChatListCell.buildCellContentToken(for: configuration)
        cellContentCache.set(key: cacheKey, value: cellContentToken)
        return cellContentToken
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
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

            cell.configure(searchText: searchResultSet.searchText)
            return cell

        case .contacts:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier) as? ContactTableViewCell else {
                owsFailDebug("cell was unexpectedly nil")
                return UITableViewCell()
            }

            guard let searchResult = searchResultSet.contactResults[safe: indexPath.row] else {
                owsFailDebug("searchResult was unexpectedly nil")
                return UITableViewCell()
            }

            cell.configureWithSneakyTransaction(address: searchResult.recipientAddress, localUserDisplayMode: .noteToSelf)
            return cell

        case .contactThreads, .groupThreads, .messages:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ChatListCell.reuseIdentifier) as? ChatListCell else {
                owsFailDebug("cell was unexpectedly nil")
                return UITableViewCell()
            }
            guard let configuration = cellConfiguration(searchSection: searchSection, row: indexPath.row) else {
                owsFailDebug("Missing configuration.")
                return UITableViewCell()
            }

            let cellContentToken = cellContentToken(forConfiguration: configuration)
            cell.configure(cellContentToken: cellContentToken, spoilerAnimationManager: spoilerAnimationManager)
            cell.useSidebarAppearance = useSidebarTableViewCellAppearance
            return cell
        }
    }

    private class var matchSnippetStyle: StringStyle {
        StringStyle(
            .color(.Signal.secondaryLabel),
            .xmlRules([
                .style(FullTextSearchIndexer.matchTag, StringStyle(.font(UIFont.dynamicTypeSubheadline.semibold()))),
            ]),
        )
    }

    private func cellConfiguration(searchSection: SearchSection, row: Int) -> ChatListCell.Configuration? {
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
            guard let searchResult = searchResultSet.contactThreadResults[safe: row] else {
                owsFailDebug("searchResult was unexpectedly nil")
                return nil
            }
            return ChatListCell.Configuration(
                threadViewModel: searchResult.threadViewModel,
                lastReloadDate: lastReloadDate,
            )

        case .groupThreads:
            guard let searchResult = searchResultSet.groupThreadResults[safe: row] else {
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
                threadViewModel: searchResult.threadViewModel,
                lastReloadDate: lastReloadDate,
                overrideSnippet: overrideSnippet,
                overrideDate: nil,
            )

        case .contacts:
            owsFailDebug("Invalid section.")
            return nil

        case .messages:
            guard let searchResult = searchResultSet.messageResults[safe: row] else {
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
                threadViewModel: searchResult.threadViewModel,
                lastReloadDate: lastReloadDate,
                overrideSnippet: overrideSnippet,
                overrideDate: overrideDate,
            )
        }
    }

    private func titleForHeaderInSection(_ section: Int) -> String? {
        guard let searchSection = SearchSection(rawValue: section) else {
            owsFailDebug("unknown section: \(section)")
            return nil
        }

        switch searchSection {
        case .noResults:
            return nil

        case .contactThreads:
            guard searchResultSet.contactThreadResults.count > 0 else { return nil }

            return OWSLocalizedString(
                "SEARCH_SECTION_CONVERSATIONS",
                comment: "section header for search results that match existing 1:1 chats",
            )

        case .groupThreads:
            guard searchResultSet.groupThreadResults.count > 0 else { return nil }

            return OWSLocalizedString(
                "SEARCH_SECTION_GROUPS",
                comment: "section header for search results that match existing groups",
            )

        case .contacts:
            guard searchResultSet.contactResults.count > 0 else { return nil }

            return OWSLocalizedString(
                "SEARCH_SECTION_CONTACTS",
                comment: "section header for search results that match a contact who doesn't have an existing conversation",
            )

        case .messages:
            guard searchResultSet.messageResults.count > 0 else { return nil }

            return OWSLocalizedString(
                "SEARCH_SECTION_MESSAGES",
                comment: "section header for search results that match a message in a conversation",
            )
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return 5
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard nil != titleForHeaderInSection(section) else {
            return .leastNonzeroMagnitude
        }
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let title = titleForHeaderInSection(section) else {
            return UIView()
        }

        let label = UILabel()
        label.textColor = .Signal.label
        label.font = .dynamicTypeHeadline
        label.text = title
        label.translatesAutoresizingMaskIntoConstraints = false

        let headerView = UITableViewHeaderFooterView(reuseIdentifier: nil)
        headerView.directionalLayoutMargins.top = 14
        headerView.directionalLayoutMargins.bottom = 8
        headerView.contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: headerView.contentView.layoutMarginsGuide.topAnchor),
            label.leadingAnchor.constraint(equalTo: headerView.contentView.layoutMarginsGuide.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: headerView.contentView.layoutMarginsGuide.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: headerView.contentView.layoutMarginsGuide.bottomAnchor),
        ])

        return headerView
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        // Without returning a footer with a non-zero height, Grouped
        // table view will use a default spacing between sections. We
        // do not want that spacing so we use the smallest possible height.
        return .leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView()
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        return trailingSwipeActionsConfiguration(for: getThreadViewModelFor(indexPath: indexPath))
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        return leadingSwipeActionsConfiguration(for: getThreadViewModelFor(indexPath: indexPath))
    }

    private func getThreadViewModelFor(indexPath: IndexPath) -> ThreadViewModel? {
        guard let searchSection = SearchSection(rawValue: indexPath.section) else { return nil }

        if searchSection == .contactThreads {
            return searchResultSet.contactThreadResults[indexPath.row].threadViewModel
        } else if searchSection == .groupThreads {
            return searchResultSet.groupThreadResults[indexPath.row].threadViewModel
        }
        return nil
    }
}

// MARK: - UIScrollViewDelegate

extension ConversationSearchViewController {

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        delegate?.conversationSearchViewWillBeginDragging()
    }
}

// MARK: -

class EmptySearchResultCell: UITableViewCell {

    static let reuseIdentifier = "EmptySearchResultCell"

    private let messageLabel = UILabel()

    private let activityIndicator = UIActivityIndicatorView(style: .large)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none
        automaticallyUpdatesBackgroundConfiguration = false

        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 3

        contentView.addSubview(messageLabel)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(activityIndicator)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            messageLabel.heightAnchor.constraint(equalToConstant: 150),
            messageLabel.topAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.topAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: contentView.layoutMarginsGuide.centerYAnchor),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.layoutMarginsGuide.leadingAnchor),
            messageLabel.centerXAnchor.constraint(equalTo: contentView.layoutMarginsGuide.centerXAnchor),

            activityIndicator.centerXAnchor.constraint(equalTo: contentView.layoutMarginsGuide.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: contentView.layoutMarginsGuide.centerYAnchor),
        ])
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        var configuration = UIBackgroundConfiguration.clear()
        configuration.backgroundColor = .Signal.background
        backgroundConfiguration = configuration
    }

    func configure(searchText: String) {
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
                comment: "Format string when search returns no results. Embeds {{search term}}",
            )
            messageLabel.text = String(format: format, searchText)

            messageLabel.textColor = .Signal.label
            messageLabel.font = UIFont.dynamicTypeBody
        }
    }
}

// MARK: -

extension ConversationSearchViewController: DatabaseChangeDelegate {

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        guard databaseChanges.didUpdateThreads || databaseChanges.didUpdateInteractions else {
            return
        }

        refreshSearchResults()
    }

    func databaseChangesDidUpdateExternally() {
        refreshSearchResults()
    }

    func databaseChangesDidReset() {
        refreshSearchResults()
    }
}

// MARK: -

extension ConversationSearchViewController: ThreadSwipeHandler {

    func updateUIAfterSwipeAction() { }
}
