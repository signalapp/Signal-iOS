//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
protocol ConversationSearchViewDelegate: class {
    func conversationSearchViewWillBeginDragging()
}

@objc
class ConversationSearchViewController: UITableViewController, BlockListCacheDelegate {

    @objc
    public weak var delegate: ConversationSearchViewDelegate?

    @objc
    public var searchText = "" {
        didSet {
            AssertIsOnMainThread()

            // Use a slight delay to debounce updates.
            refreshSearchResults()
        }
    }

    var searchResultSet: SearchResultSet = SearchResultSet.empty

    var uiDatabaseConnection: YapDatabaseConnection {
        return OWSPrimaryStorage.shared().uiDatabaseConnection
    }

    var searcher: ConversationSearcher {
        return ConversationSearcher.shared
    }

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    enum SearchSection: Int {
        case noResults
        case conversations
        case contacts
        case messages
    }

    private var hasThemeChanged = false

    var blockListCache: BlockListCache!

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        blockListCache = BlockListCache()
        blockListCache.startObservingAndSyncState(delegate: self)

        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 60
        tableView.separatorColor = Theme.cellSeparatorColor

        tableView.register(EmptySearchResultCell.self, forCellReuseIdentifier: EmptySearchResultCell.reuseIdentifier)
        tableView.register(HomeViewCell.self, forCellReuseIdentifier: HomeViewCell.cellReuseIdentifier())
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier())

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(yapDatabaseModified),
                                               name: NSNotification.Name.YapDatabaseModified,
                                               object: OWSPrimaryStorage.shared().dbNotificationObject)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: NSNotification.Name.ThemeDidChange,
                                               object: nil)

        applyTheme()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard hasThemeChanged else {
            return
        }
        hasThemeChanged = false

        applyTheme()
        self.tableView.reloadData()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc internal func yapDatabaseModified(notification: NSNotification) {
        AssertIsOnMainThread()

        refreshSearchResults()
    }

    @objc internal func themeDidChange(notification: NSNotification) {
        AssertIsOnMainThread()

        applyTheme()
        self.tableView.reloadData()

        hasThemeChanged = true
    }

    private func applyTheme() {
        AssertIsOnMainThread()

        self.view.backgroundColor = Theme.backgroundColor
        self.tableView.backgroundColor = Theme.backgroundColor
    }

    // MARK: UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)

        guard let searchSection = SearchSection(rawValue: indexPath.section) else {
            owsFailDebug("unknown section selected.")
            return
        }

        switch searchSection {
        case .noResults:
            owsFailDebug("shouldn't be able to tap 'no results' section")
        case .conversations:
            let sectionResults = searchResultSet.conversations
            guard let searchResult = sectionResults[safe: indexPath.row] else {
                owsFailDebug("unknown row selected.")
                return
            }

            let thread = searchResult.thread
            SignalApp.shared().presentConversation(for: thread.threadRecord, action: .compose, animated: true)

        case .contacts:
            let sectionResults = searchResultSet.contacts
            guard let searchResult = sectionResults[safe: indexPath.row] else {
                owsFailDebug("unknown row selected.")
                return
            }

            SignalApp.shared().presentConversation(forRecipientId: searchResult.recipientId, action: .compose, animated: true)

        case .messages:
            let sectionResults = searchResultSet.messages
            guard let searchResult = sectionResults[safe: indexPath.row] else {
                owsFailDebug("unknown row selected.")
                return
            }

            let thread = searchResult.thread
            SignalApp.shared().presentConversation(for: thread.threadRecord,
                                                   action: .none,
                                                   focusMessageId: searchResult.messageId,
                                                   animated: true)
        }
    }

    // MARK: UITableViewDataSource

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let searchSection = SearchSection(rawValue: section) else {
            owsFailDebug("unknown section: \(section)")
            return 0
        }

        switch searchSection {
        case .noResults:
            return searchResultSet.isEmpty ? 1 : 0
        case .conversations:
            return searchResultSet.conversations.count
        case .contacts:
            return searchResultSet.contacts.count
        case .messages:
            return searchResultSet.messages.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

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
        case .conversations:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: HomeViewCell.cellReuseIdentifier()) as? HomeViewCell else {
                owsFailDebug("cell was unexpectedly nil")
                return UITableViewCell()
            }

            guard let searchResult = self.searchResultSet.conversations[safe: indexPath.row] else {
                owsFailDebug("searchResult was unexpectedly nil")
                return UITableViewCell()
            }
            cell.configure(withThread: searchResult.thread, contactsManager: contactsManager, isBlocked: isBlocked(thread: searchResult.thread))
            return cell
        case .contacts:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ContactTableViewCell.reuseIdentifier()) as? ContactTableViewCell else {
                owsFailDebug("cell was unexpectedly nil")
                return UITableViewCell()
            }

            guard let searchResult = self.searchResultSet.contacts[safe: indexPath.row] else {
                owsFailDebug("searchResult was unexpectedly nil")
                return UITableViewCell()
            }
            cell.configure(withRecipientId: searchResult.signalAccount.recipientId, contactsManager: contactsManager)
            return cell
        case .messages:
            guard let cell = tableView.dequeueReusableCell(withIdentifier: HomeViewCell.cellReuseIdentifier()) as? HomeViewCell else {
                owsFailDebug("cell was unexpectedly nil")
                return UITableViewCell()
            }

            guard let searchResult = self.searchResultSet.messages[safe: indexPath.row] else {
                owsFailDebug("searchResult was unexpectedly nil")
                return UITableViewCell()
            }

            var overrideSnippet = NSAttributedString()
            var overrideDate: Date?
            if searchResult.messageId != nil {
                if let messageDate = searchResult.messageDate {
                    overrideDate = messageDate
                } else {
                    owsFailDebug("message search result is missing message timestamp")
                }

                // Note that we only use the snippet for message results,
                // not conversation results.  HomeViewCell will generate
                // a snippet for conversations that reflects the latest
                // contents.
                if let messageSnippet = searchResult.snippet {
                    overrideSnippet = NSAttributedString(string: messageSnippet,
                                                         attributes: [
                                                            NSAttributedStringKey.foregroundColor: Theme.secondaryColor
                    ])
                } else {
                    owsFailDebug("message search result is missing message snippet")
                }
            }

            cell.configure(withThread: searchResult.thread,
                           contactsManager: contactsManager,
                           isBlocked: isBlocked(thread: searchResult.thread),
                           overrideSnippet: overrideSnippet,
                           overrideDate: overrideDate)

            return cell
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard nil != self.tableView(tableView, titleForHeaderInSection: section) else {
            return 0
        }
        return UITableViewAutomaticDimension
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let title = self.tableView(tableView, titleForHeaderInSection: section) else {
            return nil
        }

        let label = UILabel()
        label.textColor = Theme.secondaryColor
        label.text = title
        label.font = UIFont.ows_dynamicTypeBody.ows_mediumWeight()
        label.tag = section

        let hMargin: CGFloat = 15
        let vMargin: CGFloat = 4
        let wrapper = UIView()
        wrapper.backgroundColor = Theme.offBackgroundColor
        wrapper.addSubview(label)
        label.autoPinWidthToSuperview(withMargin: hMargin)
        label.autoPinHeightToSuperview(withMargin: vMargin)

        return wrapper
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let searchSection = SearchSection(rawValue: section) else {
            owsFailDebug("unknown section: \(section)")
            return nil
        }

        switch searchSection {
        case .noResults:
            return nil
        case .conversations:
            if searchResultSet.conversations.count > 0 {
                return NSLocalizedString("SEARCH_SECTION_CONVERSATIONS", comment: "section header for search results that match existing conversations (either group or contact conversations)")
            } else {
                return nil
            }
        case .contacts:
            if searchResultSet.contacts.count > 0 {
                return NSLocalizedString("SEARCH_SECTION_CONTACTS", comment: "section header for search results that match a contact who doesn't have an existing conversation")
            } else {
                return nil
            }
        case .messages:
            if searchResultSet.messages.count > 0 {
                return NSLocalizedString("SEARCH_SECTION_MESSAGES", comment: "section header for search results that match a message in a conversation")
            } else {
                return nil
            }
        }
    }

    // MARK: BlockListCacheDelegate

    func blockListCacheDidUpdate(_ blocklistCache: BlockListCache) {
        refreshSearchResults()
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

    private func updateSearchResults(searchText: String) {
        guard searchText.stripped.count > 0 else {
            self.searchResultSet = SearchResultSet.empty
            self.tableView.reloadData()
            return
        }

        var searchResults: SearchResultSet?
        self.uiDatabaseConnection.asyncRead({[weak self] transaction in
            guard let strongSelf = self else { return }
            searchResults = strongSelf.searcher.results(searchText: searchText, transaction: transaction, contactsManager: strongSelf.contactsManager)
        },
                                            completionBlock: { [weak self] in
                                                AssertIsOnMainThread()
                                                guard let strongSelf = self else { return }

                                                guard let results = searchResults else {
                                                    owsFailDebug("searchResults was unexpectedly nil")
                                                    return
                                                }

                                                strongSelf.searchResultSet = results
                                                strongSelf.tableView.reloadData()
        })
    }

    // MARK: - UIScrollViewDelegate

    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        delegate?.conversationSearchViewWillBeginDragging()
    }

    // MARK: -

    private func isBlocked(thread: ThreadViewModel) -> Bool {
        return self.blockListCache.isBlocked(thread: thread.threadRecord)
    }
}

class EmptySearchResultCell: UITableViewCell {
    static let reuseIdentifier = "EmptySearchResultCell"

    let messageLabel: UILabel
    override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
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
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    public func configure(searchText: String) {
        let format = NSLocalizedString("HOME_VIEW_SEARCH_NO_RESULTS_FORMAT", comment: "Format string when search returns no results. Embeds {{search term}}")
        let messageText: String = NSString(format: format as NSString, searchText) as String
        self.messageLabel.text = messageText

        messageLabel.textColor = Theme.primaryColor
        messageLabel.font = UIFont.ows_dynamicTypeBody
    }
}
