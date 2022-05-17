// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit
import SignalUtilitiesKit

class GlobalSearchViewController: BaseVC, UITableViewDelegate, UITableViewDataSource {
    private struct SearchResultSet {
        let contactsAndGroups: [ConversationCell.ViewModel]
        let messages: [ConversationCell.ViewModel]
    }
    
    let isRecentSearchResultsEnabled = false

    @objc public var searchText = "" {
        didSet {
            AssertIsOnMainThread()
            // Use a slight delay to debounce updates.
            refreshSearchResults()
        }
    }
    var defaultSearchResults: HomeScreenSearchResultSet = HomeScreenSearchResultSet.noteToSelfOnly
    
    var searchResultSet: [ArraySection<SearchSection, ConversationCell.ViewModel>] = []
    private var termForCurrentSearchResultSet: String = ""
    
    
    private var lastSearchText: String?
    var searcher: FullTextSearcher {
        return FullTextSearcher.shared
    }
    var isLoading = false

    enum SearchSection: Int, Differentiable {
        case noResults
        case contactsAndGroups
        case messages
    }

    // MARK: - UI Components

    internal lazy var searchBar: SearchBar = {
        let result: SearchBar = SearchBar()
        result.tintColor = Colors.text
        result.delegate = self
        result.showsCancelButton = true
        return result
    }()

    internal lazy var tableView: UITableView = {
        let result: UITableView = UITableView(frame: .zero, style: .grouped)
        result.rowHeight = UITableView.automaticDimension
        result.estimatedRowHeight = 60
        result.separatorStyle = .none
        result.keyboardDismissMode = .onDrag
        result.register(view: EmptySearchResultCell.self)
        result.register(view: ConversationCell.self)
        result.showsVerticalScrollIndicator = false
        
        return result
    }()

    // MARK: - View Lifecycle
    
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
        let searchBarContainer: UIView = UIView()
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

    // MARK: - Update Search Results

    var refreshTimer: Timer?

    private func refreshSearchResults() {
        refreshTimer?.invalidate()
        refreshTimer = WeakTimer.scheduledTimer(timeInterval: 0.1, target: self, userInfo: nil, repeats: false) { [weak self] _ in
            self?.updateSearchResults(searchText: (self?.searchText ?? ""))
        }
    }

    private func updateSearchResults(searchText rawSearchText: String) {

        let searchText = rawSearchText.stripped
        guard searchText.count > 0 else {
            searchResultSet = defaultSearchResults
            lastSearchText = nil
            reloadTableData()
            return
        }
        guard lastSearchText != searchText else { return }

        lastSearchText = searchText

        GRDBStorage.shared
            .read { db -> Result<SearchResultSet, Error> in
                do {
                    let contactsAndGroupsResults: [ConversationCell.ViewModel] = try ConversationCell.ViewModel
                        .contactsAndGroupsQuery(
                            userPublicKey: getUserHexEncodedPublicKey(db),
                            pattern: try ConversationCell.ViewModel.pattern(db, searchTerm: searchText),
                            searchTerm: searchText
                        )
                        .fetchAll(db)
                    
                    let messageResults: [ConversationCell.ViewModel] = try ConversationCell.ViewModel
                        .messagesQuery(
                            userPublicKey: getUserHexEncodedPublicKey(db),
                            pattern: try ConversationCell.ViewModel.pattern(db, searchTerm: searchText)
                        )
                        .fetchAll(db)
                    
                    return .success(SearchResultSet(
                        contactsAndGroups: contactsAndGroupsResults,
                        messages: messageResults
                    ))
                }
                catch {
                    return .failure(error)
                }
            }
            .map { [weak self] result in
                switch result {
                    case .success(let resultSet):
                        self?.termForCurrentSearchResultSet = searchText
                        self?.searchResultSet = [
                            ArraySection(model: .contactsAndGroups, elements: resultSet.contactsAndGroups),
                            ArraySection(model: .messages, elements: resultSet.messages)
                        ]
                        self?.isLoading = false
                        self?.reloadTableData()
                        self?.refreshTimer = nil
                        
                        
                    case .failure: break
                }
            }
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

    // MARK: - UITableViewDelegate

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        
        guard let searchSection = SearchSection(rawValue: indexPath.section) else { return }
        
        switch searchSection {
            case .noResults:
                SNLog("shouldn't be able to tap 'no results' section")
                
            case .contactsAndGroups:
                break
                
            case .messages:
                break
        }
    }

    private func show(_ thread: TSThread, highlightedMessageID: String?, animated: Bool, isFromRecent: Bool = false) {
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

    // MARK: - UITableViewDataSource

    public func numberOfSections(in tableView: UITableView) -> Int {
        return self.searchResultSet.count
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
        guard let title: String = self.tableView(tableView, titleForHeaderInSection: section) else {
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

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let section: ArraySection<SearchSection, ConversationCell.ViewModel> = self.searchResultSet[section]
        switch section.model {
            case .noResults: return nil
            case .contactsAndGroups: return (section.elements.isEmpty ? nil : "SEARCH_SECTION_CONTACTS".localized())
            case .messages: return (section.elements.isEmpty ? nil : "SEARCH_SECTION_MESSAGES".localized())
        }
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.searchResultSet[section].elements.count
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section: ArraySection<SearchSection, ConversationCell.ViewModel> = self.searchResultSet[indexPath.section]
        
        switch section.model {
            case .noResults:
                let cell: EmptySearchResultCell = tableView.dequeue(type: EmptySearchResultCell.self, for: indexPath)
                cell.configure(isLoading: isLoading)
                return cell
                
            case .contactsAndGroups:
                let cell: ConversationCell = tableView.dequeue(type: ConversationCell.self, for: indexPath)
                cell.updateForContactAndGroupSearchResult(with: section.elements[indexPath.row], searchText: self.termForCurrentSearchResultSet)
                return cell
                
            case .messages:
                let cell: ConversationCell = tableView.dequeue(type: ConversationCell.self, for: indexPath)
                cell.updateForMessageSearchResult(with: section.elements[indexPath.row], searchText: self.termForCurrentSearchResultSet)
                return cell
        }
    }
}
