// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import UIKit
import NVActivityIndicatorView

@objc
public protocol GlobalSearchViewDelegate: AnyObject {
    func globalSearchViewWillBeginDragging()
}

@objc
public class GlobalSearchViewController: UITableViewController {
    
    @objc
    public static let minimumSearchTextLength: Int = 2
    
    private let maxSearchResultCount: Int = 200
    
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
        tableView.showsVerticalScrollIndicator = false
        tableView.keyboardDismissMode = .interactive

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
            guard let self = self else {
                return
            }

            self.updateSearchResults(searchText: self.searchText)
            self.refreshTimer = nil
        }
    }
    
    private func updateSearchResults(searchText rawSearchText: String) {

        let searchText = rawSearchText.stripped
        guard searchText.count >= GlobalSearchViewController.minimumSearchTextLength else {
            searchResultSet = HomeScreenSearchResultSet.empty
            lastSearchText = nil
            reloadTableData()
            return
        }
        guard lastSearchText != searchText else { return }

        lastSearchText = searchText

        var searchResults: HomeScreenSearchResultSet?
        self.dbReadConnection.asyncRead({[weak self] transaction in
            guard let self = self else { return }
            searchResults = self.searcher.searchForHomeScreen(searchText: searchText, maxSearchResults: self.maxSearchResultCount,  transaction: transaction)
        }, completionBlock: { [weak self] in
            AssertIsOnMainThread()
            guard let self = self, let results = searchResults, self.lastSearchText == searchText else { return }
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
            guard let searchResult = sectionResults[safe: indexPath.row], let threadId = searchResult.thread.threadRecord.uniqueId, let thread = TSThread.fetch(uniqueId: threadId) else { return }
            show(thread, highlightedMessageID: nil, animated: true)
        case .messages:
            let sectionResults = searchResultSet.messages
            guard let searchResult = sectionResults[safe: indexPath.row], let threadId = searchResult.thread.threadRecord.uniqueId, let thread = TSThread.fetch(uniqueId: threadId) else { return }
            show(thread, highlightedMessageID: searchResult.messageId, animated: true)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    private func show(_ thread: TSThread, highlightedMessageID: String?, animated: Bool) {
        DispatchMainThreadSafe {
            if let presentedVC = self.presentedViewController {
                presentedVC.dismiss(animated: false, completion: nil)
            }
            let conversationVC = ConversationVC(thread: thread, focusedMessageID: highlightedMessageID)
            self.navigationController?.pushViewController(conversationVC, animated: true)
        }
    }

    // MARK: UITableViewDataSource
    
    public override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
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
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        
        let container = UIView()
        container.backgroundColor = Colors.cellBackground
        container.layoutMargins = UIEdgeInsets(top: Values.smallSpacing, left: Values.mediumSpacing, bottom: Values.smallSpacing, right: Values.mediumSpacing)
        container.addSubview(titleLabel)
        titleLabel.autoPinEdgesToSuperviewMargins()

        return container
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
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
        }
    }

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
            cell.configure(messageDate: searchResult?.messageDate, snippet: searchResult?.snippet, searchText: searchResultSet.searchText)
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

    private lazy var messageLabel: UILabel = {
        let result = UILabel()
        result.textAlignment = .center
        result.numberOfLines = 3
        result.textColor = Colors.text
        result.text = NSLocalizedString("CONVERSATION_SEARCH_NO_RESULTS", comment: "")
        return result
    }()
    
    private lazy var spinner: NVActivityIndicatorView = {
        let result = NVActivityIndicatorView(frame: CGRect.zero, type: .circleStrokeSpin, color: Colors.text, padding: nil)
        result.set(.width, to: 40)
        result.set(.height, to: 40)
        return result
    }()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
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

        contentView.addSubview(spinner)
        spinner.autoCenterInSuperview()
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    public func configure(searchText: String) {
        if searchText.count < GlobalSearchViewController.minimumSearchTextLength {
            spinner.stopAnimating()
            spinner.startAnimating()
            messageLabel.isHidden = true
        } else {
            spinner.stopAnimating()
            messageLabel.isHidden = false
        }
    }
}
