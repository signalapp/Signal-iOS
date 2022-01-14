// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

@objc
public protocol GlobalSearchViewDelegate: AnyObject {
    func globalSearchViewWillBeginDragging()
    
    func globalSearchDidSelectSearchResult(thread: ThreadViewModel, messageId: String?)
}

@objc
public class GlobalSearchViewController: UITableViewController {
    
    @objc
    public weak var delegate: GlobalSearchViewDelegate?
    
    @objc
    public var searchText = "" {
        didSet {
            AssertIsOnMainThread()

            // Use a slight delay to debounce updates.
            refreshSearchResults()
        }
    }

    var searchResultSet: HomeScreenSearchResultSet = HomeScreenSearchResultSet.empty
    private var lastSearchText: String?

    var searcher: FullTextSearcher {
        return FullTextSearcher.shared
    }

    enum SearchSection: Int {
        case noResults
        case contacts
        case messages
    }
    
    // MARK: Dependencies

    var dbReadConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().dbReadConnection
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
        tableView.register(ConversationCell.self, forCellReuseIdentifier: ConversationCell.reuseIdentifier)

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
            guard let strongSelf = self else {
                return
            }

            strongSelf.updateSearchResults(searchText: strongSelf.searchText)
            strongSelf.refreshTimer = nil
        }
    }
    
    private func updateSearchResults(searchText rawSearchText: String) {

        let searchText = rawSearchText.stripped
        guard searchText.count > 0 else {
            searchResultSet = HomeScreenSearchResultSet.empty
            lastSearchText = nil
            reloadTableData()
            return
        }
        guard lastSearchText != searchText else {
            // Ignoring redundant search.
            return
        }

        lastSearchText = searchText

        var searchResults: HomeScreenSearchResultSet?
        self.dbReadConnection.asyncRead({[weak self] transaction in
            guard let strongSelf = self else { return }
            searchResults = strongSelf.searcher.searchForHomeScreen(searchText: searchText, transaction: transaction)
        }, completionBlock: { [weak self] in
            AssertIsOnMainThread()
            guard let self = self else { return }

            guard let results = searchResults else {
                owsFailDebug("searchResults was unexpectedly nil")
                return
            }
            guard self.lastSearchText == searchText else {
                // Discard results from stale search.
                return
            }

            self.searchResultSet = results
            self.reloadTableData()
        })
    }

}

// MARK: - UITableView
extension GlobalSearchViewController {
    
    // MARK: UITableViewDelegate
    
    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)

        guard let searchSection = SearchSection(rawValue: indexPath.section) else { return }

        switch searchSection {
        case .noResults:
            SNLog("shouldn't be able to tap 'no results' section")
        case .contacts:
            let sectionResults = searchResultSet.conversations
            guard let searchResult = sectionResults[safe: indexPath.row] else { return }
            delegate?.globalSearchDidSelectSearchResult(thread: searchResult.thread, messageId: searchResult.messageId)
        case .messages:
            let sectionResults = searchResultSet.messages
            guard let searchResult = sectionResults[safe: indexPath.row] else { return }
            delegate?.globalSearchDidSelectSearchResult(thread: searchResult.thread, messageId: searchResult.messageId)
        }
    }

    // MARK: UITableViewDataSource

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let searchSection = SearchSection(rawValue: section) else { return 0 }
        switch searchSection {
        case .noResults:
            return searchResultSet.isEmpty ? 1 : 0
        case .contacts:
            return searchResultSet.conversations.count
        case .messages:
            return searchResultSet.messages.count
        }
    }

    public override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        guard let searchSection = SearchSection(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch searchSection {
        case .noResults:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: EmptySearchResultCell.reuseIdentifier) as? EmptySearchResultCell, indexPath.row == 0 else { return UITableViewCell() }
            cell.configure(searchText: searchText)
            return cell
        case .contacts, .messages:
            // TODO: return correct cell
            guard let cell = tableView.dequeueReusableCell(withIdentifier: EmptySearchResultCell.reuseIdentifier) as? EmptySearchResultCell else { return UITableViewCell() }
            cell.configure(searchText: searchText)
            return cell
        }
    }
}

// MARK: - UIScrollViewDelegate

extension GlobalSearchViewController {
    public override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        delegate?.globalSearchViewWillBeginDragging()
    }
}

// MARK: -

class EmptySearchResultCell: UITableViewCell {
    static let reuseIdentifier = "EmptySearchResultCell"

    let messageLabel: UILabel
    let activityIndicator = UIActivityIndicatorView(style: .whiteLarge)
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        self.messageLabel = UILabel()
        super.init(style: style, reuseIdentifier: reuseIdentifier)

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
        notImplemented()
    }

    public func configure(searchText: String) {
        if searchText.isEmpty {
            activityIndicator.color = Colors.text
            activityIndicator.isHidden = false
            activityIndicator.startAnimating()
            messageLabel.isHidden = true
            messageLabel.text = nil
        } else {
            activityIndicator.stopAnimating()
            activityIndicator.isHidden = true
            messageLabel.isHidden = false
            messageLabel.text = NSLocalizedString("CONVERSATION_SEARCH_NO_RESULTS", comment: "")
            messageLabel.textColor = Colors.text
        }
    }
}
