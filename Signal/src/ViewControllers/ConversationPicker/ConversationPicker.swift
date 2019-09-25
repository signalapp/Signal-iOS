//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

protocol ConversationPickerDelegate: AnyObject {
    var selectedConversationsForConversationPicker: [ConversationItem] { get }

    func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
                            didSelectConversation conversation: ConversationItem)

    func conversationPicker(_ conversationPickerViewController: ConversationPickerViewController,
                            didDeselectConversation conversation: ConversationItem)

    func conversationPickerDidCompleteSelection(_ conversationPickerViewController: ConversationPickerViewController)
}

@objc
class ConversationPickerViewController: OWSViewController {

    // MARK: - Dependencies

    var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    // MARK: -

    weak var delegate: ConversationPickerDelegate?

    enum Section: Int, CaseIterable {
        case recents, signalContacts, groups
    }

    let kMaxPickerSelection = 32

    private let tableView = UITableView()
    private let footerView = ConversationPickerFooterView()
    private var footerOffsetConstraint: NSLayoutConstraint!
    private lazy var searchBar: OWSSearchBar = {
        let searchBar = OWSSearchBar()
        searchBar.placeholder = CommonStrings.searchPlaceholder
        searchBar.delegate = self

        return searchBar
    }()

    // MARK: - UIViewController

    override var canBecomeFirstResponder: Bool {
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

    override var inputAccessoryView: UIView? {
        return currentInputAcccessoryView
    }

    override func loadView() {
        self.view = UIView()
        view.backgroundColor = Theme.backgroundColor
        view.addSubview(tableView)
        tableView.separatorColor = Theme.cellSeparatorColor
        tableView.backgroundColor = Theme.backgroundColor
        tableView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        self.autoPinView(toBottomOfViewControllerOrKeyboard: tableView, avoidNotch: true)

        searchBar.sizeToFit()
        tableView.tableHeaderView = searchBar
    }

    override func viewDidLoad() {
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
        updateFooterForCurrentSelection(animated: false)
    }

    let blockListCache = BlockListCache()
    var fullTextSearcher: FullTextSearcher {
        return FullTextSearcher.shared
    }

    func buildSearchResults(searchText: String) -> Promise<ComposeScreenSearchResultSet?> {
        guard searchText.count > 1 else {
            return Promise.value(nil)
        }

        return DispatchQueue.global().async(.promise) {
            return self.databaseStorage.readReturningResult { transaction in
                return self.fullTextSearcher.searchForComposeScreen(searchText: searchText,
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
        return self.databaseStorage.uiReadReturningResult { transaction in
            var recentItems: [RecentConversationItem] = []
            var contactItems: [ContactConversationItem] = []
            var groupItems: [GroupConversationItem] = []
            var seenAddresses: Set<SignalServiceAddress> = Set()
            let maxRecentCount = 25

            let addThread = { (thread: TSThread) -> Void in
                switch thread {
                case let contactThread as TSContactThread:
                    let item = self.buildContactItem(contactThread.contactAddress, transaction: transaction)
                    seenAddresses.insert(contactThread.contactAddress)
                    if recentItems.count < maxRecentCount {
                        let recentItem = RecentConversationItem(backingItem: .contact(item))
                        recentItems.append(recentItem)
                    } else {
                        contactItems.append(item)
                    }
                case let groupThread as TSGroupThread:
                    let item = self.buildGroupItem(groupThread, transaction: transaction)
                    if recentItems.count < maxRecentCount {
                        let recentItem = RecentConversationItem(backingItem: .group(item))
                        recentItems.append(recentItem)
                    } else {
                        groupItems.append(item)
                    }
                default:
                    owsFailDebug("unexpected thread: \(thread)")
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

            return ConversationCollection(contactConversations: contactItems,
                                          recentConversations: recentItems,
                                          groupConversations: groupItems)
        }
    }

    func buildConversationCollection(searchResults: ComposeScreenSearchResultSet?) -> Promise<ConversationCollection> {
        guard let searchResults = searchResults else {
            return Promise.value(buildConversationCollection())
        }

        return DispatchQueue.global().async(.promise) {
            return self.databaseStorage.readReturningResult { transaction in
                let groupItems = searchResults.groupThreads.map { self.buildGroupItem($0, transaction: transaction) }
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
}

extension ConversationPickerViewController: BlockListCacheDelegate {
    func blockListCacheDidUpdate(_ blocklistCache: BlockListCache) {
        Logger.debug("")
        self.conversationCollection = buildConversationCollection()
    }
}

extension ConversationPickerViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
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

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else {
            owsFailDebug("section was unexpectedly nil")
            return 0
        }

        return conversationCollection.conversations(section: section).count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
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

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
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

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        guard titleForHeader(inSection: section) != nil else {
            // empty sections will have no title - don't show a header.
            return 0
        }

        return DarkThemeHeaderView.desiredHeight
    }
}

extension ConversationPickerViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
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
            let contactsManager = Environment.shared.contactsManager!
            let blockingManager = OWSBlockingManager.shared()
            switch item.messageRecipient {
            case .contact(let address):
                BlockListUIUtils.showUnblockAddressActionSheet(address,
                                                               from: self,
                                                               blockingManager: blockingManager,
                                                               contactsManager: contactsManager) { isStillBlocked in
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
                                                              from: self,
                                                              blockingManager: blockingManager,
                                                              contactsManager: contactsManager) { isStillBlocked in
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

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let conversation = conversation(for: indexPath) else {
            owsFailDebug("conversation was unexpectedly nil")
            return
        }
        delegate?.conversationPicker(self, didSelectConversation: conversation)
        updateFooterForCurrentSelection(animated: true)
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard let conversation = conversation(for: indexPath) else {
            owsFailDebug("conversation was unexpectedly nil")
            return
        }
        delegate?.conversationPicker(self, didDeselectConversation: conversation)
        updateFooterForCurrentSelection(animated: true)
    }

    private func updateFooterForCurrentSelection(animated: Bool) {
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

extension ConversationPickerViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        buildSearchResults(searchText: searchText).then { [weak self] searchResults -> Promise<ConversationCollection> in
            guard let self = self else {
                throw PMKError.cancelled
            }

            return self.buildConversationCollection(searchResults: searchResults)
            }.done { [weak self] conversationCollection in
                guard let self = self else { return }

                self.conversationCollection = conversationCollection
                self.tableView.reloadData()
                self.restoreSelection(tableView: self.tableView)
            }.retainUntilComplete()
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(true, animated: true)
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        searchBar.setShowsCancelButton(false, animated: true)
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchBar.text = nil
        searchBar.resignFirstResponder()
    }
}

extension ConversationPickerViewController: ConversationPickerFooterDelegate {
    fileprivate func conversationPickerFooterDelegateDidRequestProceed(_ conversationPickerFooterView: ConversationPickerFooterView) {
        delegate?.conversationPickerDidCompleteSelection(self)
    }
}

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
            super.configure(withRecipientAddress: address)
        case .group(let groupThread):
            super.configure(with: groupThread, transaction: transaction)
        }

        selectionStyle = .none
    }

    // MARK: - Subviews

    static let selectedBadgeImage = #imageLiteral(resourceName: "image_editor_checkmark_full").withRenderingMode(.alwaysTemplate)

    let selectionBadgeSize = CGSize(width: 20, height: 20)
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
        timerView.autoSetDimensions(to: CGSize(width: 44, height: 44))
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
        imageView.tintColor = .ows_signalBlue
        return imageView
    }()
}

// MARK: - ConversationPickerFooterView

private protocol ConversationPickerFooterDelegate: AnyObject {
    func conversationPickerFooterDelegateDidRequestProceed(_ conversationPickerFooterView: ConversationPickerFooterView)
}

private class ConversationPickerFooterView: UIView {
    weak var delegate: ConversationPickerFooterDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)

        autoresizingMask = .flexibleHeight
        translatesAutoresizingMaskIntoConstraints = false

        backgroundColor = Theme.keyboardBackgroundColor
        layoutMargins = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)

        let topStrokeView = UIView()
        topStrokeView.backgroundColor = Theme.hairlineColor
        addSubview(topStrokeView)
        topStrokeView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        topStrokeView.autoSetDimension(.height, toSize: CGHairlineWidth())

        let stackView = UIStackView(arrangedSubviews: [labelScrollView, proceedButton])
        stackView.spacing = 12
        stackView.alignment = .center
        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        return CGSize.zero
    }

    // MARK: public

    var namesText: String? {
        get {
            return namesLabel.text
        }
    }

    func setNamesText(_ newValue: String?, animated: Bool) {
        let changes = {
            self.namesLabel.text = newValue

            self.layoutIfNeeded()

            let offset = max(0, self.labelScrollView.contentSize.width - self.labelScrollView.bounds.width)
            let trailingEdge = CGPoint(x: offset, y: 0)

            self.labelScrollView.setContentOffset(trailingEdge, animated: false)
        }

        if animated {
            UIView.animate(withDuration: 0.1, animations: changes)
        } else {
            changes()
        }
    }

    // MARK: private subviews

    lazy var labelScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false

        scrollView.addSubview(namesLabel)
        namesLabel.autoPinEdgesToSuperviewEdges()
        namesLabel.autoMatch(.height, to: .height, of: scrollView)

        return scrollView
    }()

    lazy var namesLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.ows_dynamicTypeBody
        label.textColor = Theme.secondaryColor

        label.setContentHuggingLow()

        return label
    }()

    lazy var proceedButton: UIButton = {
        let button = OWSButton.sendButton(imageName: "send-solid-24") { [weak self] in
            guard let self = self else { return }
            self.delegate?.conversationPickerFooterDelegateDidRequestProceed(self)
        }

        return button
    }()
}
