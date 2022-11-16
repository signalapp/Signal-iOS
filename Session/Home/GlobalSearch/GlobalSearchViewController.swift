// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import DifferenceKit
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit
import SignalUtilitiesKit

class GlobalSearchViewController: BaseVC, UITableViewDelegate, UITableViewDataSource {
    fileprivate typealias SectionModel = ArraySection<SearchSection, SessionThreadViewModel>
    
    // MARK: - SearchSection
    
    enum SearchSection: Int, Differentiable {
        case noResults
        case contactsAndGroups
        case messages
    }
    
    // MARK: - Variables
    
    private lazy var defaultSearchResults: [SectionModel] = {
        let result: SessionThreadViewModel? = Storage.shared.read { db -> SessionThreadViewModel? in
            try SessionThreadViewModel
                .noteToSelfOnlyQuery(userPublicKey: getUserHexEncodedPublicKey(db))
                .fetchOne(db)
        }
        
        return [ result.map { ArraySection(model: .contactsAndGroups, elements: [$0]) } ]
            .compactMap { $0 }
    }()
    private var readConnection: Atomic<Database?> = Atomic(nil)
    private lazy var searchResultSet: [SectionModel] = self.defaultSearchResults
    private var termForCurrentSearchResultSet: String = ""
    private var lastSearchText: String?
    private var refreshTimer: Timer?
    
    var isLoading = false
    
    @objc public var searchText = "" {
        didSet {
            AssertIsOnMainThread()
            // Use a slight delay to debounce updates.
            refreshSearchResults()
        }
    }

    // MARK: - UI Components

    internal lazy var searchBar: SearchBar = {
        let result: SearchBar = SearchBar()
        result.themeTintColor = .textPrimary
        result.delegate = self
        result.showsCancelButton = true
        
        return result
    }()
    
    private var searchBarWidth: NSLayoutConstraint?

    internal lazy var tableView: UITableView = {
        let result: UITableView = UITableView(frame: .zero, style: .grouped)
        result.themeBackgroundColor = .clear
        result.rowHeight = UITableView.automaticDimension
        result.estimatedRowHeight = 60
        result.separatorStyle = .none
        result.keyboardDismissMode = .onDrag
        result.register(view: EmptySearchResultCell.self)
        result.register(view: FullConversationCell.self)
        result.showsVerticalScrollIndicator = false
        
        return result
    }()

    // MARK: - View Lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
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
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        searchBarWidth?.constant = size.width - 32
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
        searchBarWidth = searchBarContainer.set(.width, to: UIScreen.main.bounds.width - 32)
        searchBarContainer.addSubview(searchBar)
        navigationItem.titleView = searchBarContainer
        
        // On iPad, the cancel button won't show
        // See more https://developer.apple.com/documentation/uikit/uisearchbar/1624283-showscancelbutton?language=objc
        if UIDevice.current.isIPad {
            let ipadCancelButton = UIButton()
            ipadCancelButton.setTitle("Cancel", for: .normal)
            ipadCancelButton.setThemeTitleColor(.textPrimary, for: .normal)
            ipadCancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
            searchBarContainer.addSubview(ipadCancelButton)
            
            ipadCancelButton.pin(.trailing, to: .trailing, of: searchBarContainer)
            ipadCancelButton.autoVCenterInSuperview()
            searchBar.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets.zero, excludingEdge: .trailing)
            searchBar.pin(.trailing, to: .leading, of: ipadCancelButton, withInset: -Values.smallSpacing)
        }
        else {
            searchBar.autoPinEdgesToSuperviewMargins()
        }
    }

    private func reloadTableData() {
        tableView.reloadData()
    }

    // MARK: - Update Search Results

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

        DispatchQueue.global(qos: .default).async { [weak self] in
            self?.readConnection.wrappedValue?.interrupt()
            
            let result: Result<[SectionModel], Error>? = Storage.shared.read { db -> Result<[SectionModel], Error> in
                self?.readConnection.mutate { $0 = db }
                
                do {
                    let userPublicKey: String = getUserHexEncodedPublicKey(db)
                    let contactsAndGroupsResults: [SessionThreadViewModel] = try SessionThreadViewModel
                        .contactsAndGroupsQuery(
                            userPublicKey: userPublicKey,
                            pattern: try SessionThreadViewModel.pattern(db, searchTerm: searchText),
                            searchTerm: searchText
                        )
                        .fetchAll(db)
                    let messageResults: [SessionThreadViewModel] = try SessionThreadViewModel
                        .messagesQuery(
                            userPublicKey: userPublicKey,
                            pattern: try SessionThreadViewModel.pattern(db, searchTerm: searchText)
                        )
                        .fetchAll(db)
                    
                    return .success([
                        ArraySection(model: .contactsAndGroups, elements: contactsAndGroupsResults),
                        ArraySection(model: .messages, elements: messageResults)
                    ])
                }
                catch {
                    return .failure(error)
                }
            }
            
            DispatchQueue.main.async {
                switch result {
                    case .success(let sections):
                        let hasResults: Bool = (
                            !searchText.isEmpty &&
                            (sections.map { $0.elements.count }.reduce(0, +) > 0)
                        )
                        
                        self?.termForCurrentSearchResultSet = searchText
                        self?.searchResultSet = [
                            (hasResults ? nil : [ArraySection(model: .noResults, elements: [SessionThreadViewModel(unreadCount: 0)])]),
                            (hasResults ? sections : nil)
                        ]
                        .compactMap { $0 }
                        .flatMap { $0 }
                        self?.isLoading = false
                        self?.reloadTableData()
                        self?.refreshTimer = nil
                        
                    default: break
                }
            }
        }
    }
    
    @objc func cancel() {
        self.navigationController?.popViewController(animated: true)
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
        
        let section: SectionModel = self.searchResultSet[indexPath.section]
        
        switch section.model {
            case .noResults: break
            case .contactsAndGroups, .messages:
                show(
                    threadId: section.elements[indexPath.row].threadId,
                    threadVariant: section.elements[indexPath.row].threadVariant,
                    focusedInteractionId: section.elements[indexPath.row].interactionId
                )
        }
    }

    private func show(threadId: String, threadVariant: SessionThread.Variant, focusedInteractionId: Int64? = nil, animated: Bool = true) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.show(threadId: threadId, threadVariant: threadVariant, focusedInteractionId: focusedInteractionId, animated: animated)
            }
            return
        }
        
        if let presentedVC = self.presentedViewController {
            presentedVC.dismiss(animated: false, completion: nil)
        }
        
        let viewControllers: [UIViewController] = (self.navigationController?
            .viewControllers)
            .defaulting(to: [])
            .appending(
                ConversationVC(threadId: threadId, threadVariant: threadVariant, focusedInteractionId: focusedInteractionId)
            )
        
        self.navigationController?.setViewControllers(viewControllers, animated: true)
    }

    // MARK: - UITableViewDataSource

    public func numberOfSections(in tableView: UITableView) -> Int {
        return self.searchResultSet.count
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.searchResultSet[section].elements.count
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
        titleLabel.font = .boldSystemFont(ofSize: Values.largeFontSize)
        titleLabel.text = title
        titleLabel.themeTextColor = .textPrimary

        let container = UIView()
        container.themeBackgroundColor = .backgroundPrimary
        container.addSubview(titleLabel)
        
        titleLabel.pin(.top, to: .top, of: container, withInset: Values.mediumSpacing)
        titleLabel.pin(.bottom, to: .bottom, of: container, withInset: -Values.mediumSpacing)
        titleLabel.pin(.left, to: .left, of: container, withInset: Values.largeSpacing)
        titleLabel.pin(.right, to: .right, of: container, withInset: -Values.largeSpacing)
        
        return container
    }

    public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let section: SectionModel = self.searchResultSet[section]
        
        switch section.model {
            case .noResults: return nil
            case .contactsAndGroups: return (section.elements.isEmpty ? nil : "SEARCH_SECTION_CONTACTS".localized())
            case .messages: return (section.elements.isEmpty ? nil : "SEARCH_SECTION_MESSAGES".localized())
        }
    }

    public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section: SectionModel = self.searchResultSet[indexPath.section]
        
        switch section.model {
            case .noResults:
                let cell: EmptySearchResultCell = tableView.dequeue(type: EmptySearchResultCell.self, for: indexPath)
                cell.configure(isLoading: isLoading)
                return cell
                
            case .contactsAndGroups:
                let cell: FullConversationCell = tableView.dequeue(type: FullConversationCell.self, for: indexPath)
                cell.updateForContactAndGroupSearchResult(with: section.elements[indexPath.row], searchText: self.termForCurrentSearchResultSet)
                return cell
                
            case .messages:
                let cell: FullConversationCell = tableView.dequeue(type: FullConversationCell.self, for: indexPath)
                cell.updateForMessageSearchResult(with: section.elements[indexPath.row], searchText: self.termForCurrentSearchResultSet)
                return cell
        }
    }
}
