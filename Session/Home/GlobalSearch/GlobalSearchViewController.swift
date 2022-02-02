// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

@objc
class GlobalSearchViewController: BaseVC, UITableViewDelegate, UITableViewDataSource {
    
    let isRecentSearchResultsEnabled = false
    
    @objc public var searchText = "" {
        didSet {
            AssertIsOnMainThread()
            // Use a slight delay to debounce updates.
            refreshSearchResults()
        }
    }
    var recentSearchResults: [String] = Array(Storage.shared.getRecentSearchResults().reversed())
    var searchResultSet: HomeScreenSearchResultSet = HomeScreenSearchResultSet.empty
    private var lastSearchText: String?
    var searcher: FullTextSearcher {
        return FullTextSearcher.shared
    }
    var isLoading = false

    enum SearchSection: Int {
        case noResults
        case contacts
        case messages
        case recent
    }
    
    // MARK: UI Components
    
    internal lazy var searchBar: SearchBar = {
        let result = SearchBar()
        result.tintColor = Colors.text
        result.delegate = self
        result.showsCancelButton = true
        return result
    }()
    
    internal lazy var tableView: UITableView = {
        let result = UITableView(frame: .zero, style: .grouped)
        result.rowHeight = UITableView.automaticDimension
        result.estimatedRowHeight = 60
        result.separatorStyle = .none
        result.keyboardDismissMode = .onDrag
        result.register(EmptySearchResultCell.self, forCellReuseIdentifier: EmptySearchResultCell.reuseIdentifier)
        result.register(ConversationCell.self, forCellReuseIdentifier: ConversationCell.reuseIdentifier)
        result.showsVerticalScrollIndicator = false
        return result
    }()
    
    // MARK: Dependencies

    var dbReadConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().dbReadConnection
    }
    
    // MARK: View Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        setUpGradientBackground()
        
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.pin(.leading, to: .leading, of: view)
        tableView.pin(.top, to: .top, of: view, withInset: Values.smallSpacing)
        tableView.pin(.trailing, to: .trailing, of: view)
        tableView.pin(.bottom, to: .bottom, of: view)

        navigationItem.hidesBackButton = true
        setupNavigationBar()
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        searchBar.becomeFirstResponder()
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        searchBar.resignFirstResponder()
    }
    
    private func setupNavigationBar() {
        // This is a workaround for a UI issue that the navigation bar can be a bit higher if
        // the search bar is put directly to be the titleView. And this can cause the tableView
        // in home screen doing a weird scrolling when going back to home screen.
        let searchBarContainer = UIView()
        searchBarContainer.layoutMargins = UIEdgeInsets.zero
        searchBar.sizeToFit()
        searchBar.layoutMargins = UIEdgeInsets.zero
        searchBarContainer.set(.height, to: 44)
        searchBarContainer.set(.width, to: UIScreen.main.bounds.width - 32)
        searchBarContainer.addSubview(searchBar)
        searchBar.autoPinEdgesToSuperviewMargins()
        navigationItem.titleView = searchBarContainer
    }
    
    private func reloadTableData() {
        tableView.reloadData()
    }
    
    // MARK: Update Search Results

    var refreshTimer: Timer?
    
    private func refreshSearchResults() {

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
            guard let self = self else {
                return
            }

            self.updateSearchResults(searchText: self.searchText)
            self.refreshTimer = nil
        }
    }
    
    private func updateSearchResults(searchText rawSearchText: String) {

        let searchText = rawSearchText.stripped
        guard searchText.count > 0 else {
            searchResultSet = HomeScreenSearchResultSet.noteToSelfOnly
            lastSearchText = nil
            reloadTableData()
            return
        }
        guard lastSearchText != searchText else { return }

        lastSearchText = searchText

        var searchResults: HomeScreenSearchResultSet?
        self.dbReadConnection.asyncRead({[weak self] transaction in
            guard let self = self else { return }
            self.isLoading = true
            // The max search result count is set according to the keyword length. This is just a workaround for performance issue.
            // The longer and more accurate the keyword is, the less search results should there be.
            searchResults = self.searcher.searchForHomeScreen(searchText: searchText, maxSearchResults: min(searchText.count * 50, 500),  transaction: transaction)
        }, completionBlock: { [weak self] in
            AssertIsOnMainThread()
            guard let self = self, let results = searchResults, self.lastSearchText == searchText else { return }
            self.searchResultSet = results
            self.isLoading = false
            self.reloadTableData()
        })
    }
    
    // MARK: Interaction
    @objc func clearRecentSearchResults() {
        recentSearchResults = []
        tableView.reloadSections([ SearchSection.recent.rawValue ], with: .top)
        Storage.shared.clearRecentSearchResults()
    }

}

// MARK: - UISearchBarDelegate
extension GlobalSearchViewController: UISearchBarDelegate {
    public func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        self.updateSearchText()
    }
    
    public func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        self.updateSearchText()
    }
    
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.updateSearchText()
    }
    
    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = nil
        searchBar.resignFirstResponder()
        self.navigationController?.popViewController(animated: true)
    }
    
    func updateSearchText() {
        guard let searchText = searchBar.text?.ows_stripped() else { return }
        self.searchText = searchText
    }
}

// MARK: - UITableViewDelegate & UITableViewDataSource
extension GlobalSearchViewController {
    
    // MARK: UITableViewDelegate
    
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard let searchSection = SearchSection(rawValue: indexPath.section) else { return }
        switch searchSection {
        case .noResults:
            SNLog("shouldn't be able to tap 'no results' section")
        case .contacts:
            let sectionResults = searchResultSet.conversations
            guard let searchResult = sectionResults[safe: indexPath.row], let threadId = searchResult.thread.threadRecord.uniqueId, let thread = TSThread.fetch(uniqueId: threadId) else { return }
            show(thread, highlightedMessageID: nil, animated: true)
        case .messages:
            let sectionResults = searchResultSet.messages
            guard let searchResult = sectionResults[safe: indexPath.row], let threadId = searchResult.thread.threadRecord.uniqueId, let thread = TSThread.fetch(uniqueId: threadId) else { return }
            show(thread, highlightedMessageID: searchResult.messageId, animated: true)
        case .recent:
            guard let threadId = recentSearchResults[safe: indexPath.row], let thread = TSThread.fetch(uniqueId: threadId) else { return }
            show(thread, highlightedMessageID: nil, animated: true, isFromRecent: true)
        }
    }
    
    private func show(_ thread: TSThread, highlightedMessageID: String?, animated: Bool, isFromRecent: Bool = false) {
        if let threadId = thread.uniqueId {
            recentSearchResults = Array(Storage.shared.addSearchResults(threadID: threadId).reversed())
        }
        
        DispatchMainThreadSafe {
            if let presentedVC = self.presentedViewController {
                presentedVC.dismiss(animated: false, completion: nil)
            }
            let conversationVC = ConversationVC(thread: thread, focusedMessageID: highlightedMessageID)
            var viewControllers = self.navigationController?.viewControllers
            if isFromRecent, let index = viewControllers?.firstIndex(of: self) { viewControllers?.remove(at: index) }
            viewControllers?.append(conversationVC)
            self.navigationController?.setViewControllers(viewControllers!, animated: true)
        }
    }

    // MARK: UITableViewDataSource
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }
    
    public func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView()
    }

    public func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        .leastNonzeroMagnitude
    }

    public func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard nil != self.tableView(tableView, titleForHeaderInSection: section) else {
            return .leastNonzeroMagnitude
        }
        return UITableView.automaticDimension
    }
    
    public func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let searchSection = SearchSection(rawValue: section) else { return nil }
        
        guard let title = self.tableView(tableView, titleForHeaderInSection: section) else {
            return UIView()
        }
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        
        let container = UIView()
        container.backgroundColor = Colors.cellBackground
        container.layoutMargins = UIEdgeInsets(top: Values.smallSpacing, left: Values.mediumSpacing, bottom: Values.smallSpacing, right: Values.mediumSpacing)
        container.addSubview(titleLabel)
        titleLabel.autoPinEdgesToSuperviewMargins()
        
        if searchSection == .recent {
            let clearButton = UIButton()
            clearButton.setTitle("Clear", for: .normal)
            clearButton.setTitleColor(Colors.text, for: UIControl.State.normal)
            clearButton.titleLabel!.font = .boldSystemFont(ofSize: Values.smallFontSize)
            clearButton.addTarget(self, action: #selector(clearRecentSearchResults), for: .touchUpInside)
            container.addSubview(clearButton)
            clearButton.autoPinTrailingToSuperviewMargin()
            clearButton.autoVCenterInSuperview()
        }

        return container
    }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let searchSection = SearchSection(rawValue: section) else { return nil }

        switch searchSection {
        case .noResults:
            return nil
        case .contacts:
            if searchResultSet.conversations.count > 0 {
                return NSLocalizedString("SEARCH_SECTION_CONTACTS", comment: "")
            } else {
                return nil
            }
        case .messages:
            if searchResultSet.messages.count > 0 {
                return NSLocalizedString("SEARCH_SECTION_MESSAGES", comment: "")
            } else {
                return nil
            }
        case .recent:
            if recentSearchResults.count > 0  && searchText.isEmpty && isRecentSearchResultsEnabled {
                return NSLocalizedString("SEARCH_SECTION_RECENT", comment: "")
            } else {
                return nil
            }
        }
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let searchSection = SearchSection(rawValue: section) else { return 0 }
        switch searchSection {
        case .noResults:
            return (searchText.count > 0 && searchResultSet.isEmpty) ? 1 : 0
        case .contacts:
            return searchResultSet.conversations.count
        case .messages:
            return searchResultSet.messages.count
        case .recent:
            return searchText.isEmpty && isRecentSearchResultsEnabled ? recentSearchResults.count : 0
        }
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        guard let searchSection = SearchSection(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch searchSection {
        case .noResults:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: EmptySearchResultCell.reuseIdentifier) as? EmptySearchResultCell, indexPath.row == 0 else { return UITableViewCell() }
            cell.configure(isLoading: isLoading)
            return cell
        case .contacts:
            let sectionResults = searchResultSet.conversations
            let cell = tableView.dequeueReusableCell(withIdentifier: ConversationCell.reuseIdentifier) as! ConversationCell
            cell.isShowingGlobalSearchResult = true
            let searchResult = sectionResults[safe: indexPath.row]
            cell.threadViewModel = searchResult?.thread
            cell.configure(messageDate: searchResult?.messageDate, snippet: searchResult?.snippet, searchText: searchResultSet.searchText)
            return cell
        case .messages:
            let sectionResults = searchResultSet.messages
            let cell = tableView.dequeueReusableCell(withIdentifier: ConversationCell.reuseIdentifier) as! ConversationCell
            cell.isShowingGlobalSearchResult = true
            let searchResult = sectionResults[safe: indexPath.row]
            cell.threadViewModel = searchResult?.thread
            var message: TSMessage? = nil
            if let messageId = searchResult?.messageId { message = TSMessage.fetch(uniqueId: messageId) }
            cell.configure(messageDate: searchResult?.messageDate, snippet: searchResult?.snippet, searchText: searchResultSet.searchText, message: message)
            return cell
        case .recent:
            let cell = tableView.dequeueReusableCell(withIdentifier: ConversationCell.reuseIdentifier) as! ConversationCell
            cell.isShowingGlobalSearchResult = true
            dbReadConnection.read { transaction in
                guard let threadId = self.recentSearchResults[safe: indexPath.row], let thread = TSThread.fetch(uniqueId: threadId, transaction: transaction) else { return }
                cell.threadViewModel = ThreadViewModel(thread: thread, transaction: transaction)
            }
            cell.configureForRecent()
            return cell
        }
    }
}
