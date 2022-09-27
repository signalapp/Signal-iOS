//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMessaging
import UIKit

public protocol ConversationPickerDelegate: AnyObject {
    func conversationPickerSelectionDidChange(_ conversationPickerViewController: ConversationPickerViewController)

    func conversationPickerDidCompleteSelection(_ conversationPickerViewController: ConversationPickerViewController)

    func conversationPickerCanCancel(_ conversationPickerViewController: ConversationPickerViewController) -> Bool

    func conversationPickerDidCancel(_ conversationPickerViewController: ConversationPickerViewController)

    func approvalMode(_ conversationPickerViewController: ConversationPickerViewController) -> ApprovalMode

    func conversationPickerDidBeginEditingText()

    func conversationPickerSearchBarActiveDidChange(_ conversationPickerViewController: ConversationPickerViewController)
}

// MARK: -

@objc
open class ConversationPickerViewController: OWSTableViewController2 {

    public weak var pickerDelegate: ConversationPickerDelegate?

    private let kMaxPickerSelection = 5
    private let maxVideoAttachmentDuration: TimeInterval?

    public let selection: ConversationPickerSelection

    private let footerView = ApprovalFooterView()

    fileprivate lazy var searchBar: OWSSearchBar = {
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

    public var approvalTextMode: ApprovalFooterView.ApprovalTextMode {
        get { footerView.approvalTextMode }
        set { footerView.approvalTextMode = newValue }
    }

    /// If selecting a destination to send a video attachment, set `maxVideoAttachmentDuration` to the longest video duration,
    /// in order to warn the user if the video is too long and will be automatically segmented.
    public init(
        selection: ConversationPickerSelection,
        maxVideoAttachmentDuration: TimeInterval? = nil
    ) {
        self.selection = selection
        self.maxVideoAttachmentDuration = maxVideoAttachmentDuration

        super.init()

        self.selectionBehavior = .toggleSelectionWithAction
        self.shouldAvoidKeyboard = true
        searchBarWrapper.addArrangedSubview(searchBar)
        self.topHeader = searchBarWrapper
        self.bottomFooter = footerView
        selection.delegate = self
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

    public struct SectionOptions: OptionSet {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let stories  = SectionOptions(rawValue: 1 << 0)
        public static let recents  = SectionOptions(rawValue: 1 << 1)
        public static let contacts = SectionOptions(rawValue: 1 << 2)
        public static let groups   = SectionOptions(rawValue: 1 << 3)

        public static let all: SectionOptions = [.stories, .recents, .contacts, .groups]
    }

    public var sectionOptions: SectionOptions = [.recents, .contacts, .groups] {
        didSet {
            if isViewLoaded { updateTableContents() }
        }
    }

    public var threadFilter: (_ isIncluded: TSThread) -> Bool = { _ in true }

    public var maxStoryConversationsToRender = 2
    public var isStorySectionExpanded = false

    /// When `true`, each time the user selects an item for sending to we will fetch the identity keys for those recipients
    /// and determine if there have been any safety number changes. When you continue from this screen, we will notify of
    /// any safety number changes that have been identified during the batch updates. We don't do this all the time, as we
    /// don't necessarily want to inject safety number changes into every flow where you select conversations (such as
    /// picking members for a group).
    public var shouldBatchUpdateIdentityKeys = false

    public var shouldHideRecentConversationsTitle: Bool = false {
        didSet {
            if isViewLoaded {
                updateTableContents()
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

    var presentationTime: Date?
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        presentationTime = presentationTime ?? Date()
    }

    open override func applyTheme() {
        super.applyTheme()

        searchBar.searchFieldBackgroundColorOverride = Theme.searchFieldElevatedBackgroundColor
    }

    open override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        searchBar.layoutMargins = cellOuterInsets
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
        let isBlocked = self.blockingManager.isThreadBlocked(groupThread, transaction: transaction)
        let dmConfig = groupThread.disappearingMessagesConfiguration(with: transaction)
        return GroupConversationItem(groupThreadId: groupThread.uniqueId,
                                     isBlocked: isBlocked,
                                     disappearingMessagesConfig: dmConfig)
    }

    func buildContactItem(_ address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> ContactConversationItem {
        let isBlocked = self.blockingManager.isAddressBlocked(address, transaction: transaction)
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
                guard self.threadFilter(thread) else { return }

                guard thread.canSendChatMessagesToThread(ignoreAnnouncementOnly: true) else {
                    return
                }

                switch thread {
                case let contactThread as TSContactThread:
                    let item = self.buildContactItem(contactThread.contactAddress, transaction: transaction)
                    seenAddresses.insert(contactThread.contactAddress)
                    if self.sectionOptions.contains(.recents) && pinnedThreadIds.contains(thread.uniqueId) {
                        let recentItem = RecentConversationItem(backingItem: .contact(item))
                        pinnedItemsByThreadId[thread.uniqueId] = recentItem
                    } else if self.sectionOptions.contains(.recents) && recentItems.count < maxRecentCount {
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
                    if self.sectionOptions.contains(.recents) && pinnedThreadIds.contains(thread.uniqueId) {
                        let recentItem = RecentConversationItem(backingItem: .group(item))
                        pinnedItemsByThreadId[thread.uniqueId] = recentItem
                    } else if self.sectionOptions.contains(.recents) && recentItems.count < maxRecentCount {
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

            let storyItems = StoryConversationItem.allItems(
                includeImplicitGroupThreads: true,
                transaction: transaction
            )

            return ConversationCollection(contactConversations: contactItems,
                                          recentConversations: pinnedItems + recentItems,
                                          groupConversations: groupItems,
                                          storyConversations: storyItems,
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
                    guard self.threadFilter(groupThread) else { return nil }
                    guard groupThread.canSendChatMessagesToThread(ignoreAnnouncementOnly: true) else {
                        return nil
                    }
                    return self.buildGroupItem(groupThread, transaction: transaction)
                }
                let contactItems = searchResults.signalAccounts.map { self.buildContactItem($0.recipientAddress, transaction: transaction) }

                return ConversationCollection(contactConversations: contactItems,
                                              recentConversations: [],
                                              groupConversations: groupItems,
                                              storyConversations: [],
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

    @objc
    func onTouchCancelButton() {
        pickerDelegate?.conversationPickerDidCancel(self)
    }

    @objc
    private func blockListDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        self.conversationCollection = buildConversationCollection()
    }

    private func updateTableContents(shouldReload: Bool = true) {
        AssertIsOnMainThread()

        self.defaultSeparatorInsetLeading = (OWSTableViewController2.cellHInnerMargin +
                                                CGFloat(ContactCellView.avatarSizeClass.diameter) +
                                                ContactCellView.avatarTextHSpacing)

        let conversationCollection = self.conversationCollection

        let contents = OWSTableContents()

        var hasContents = false

        // Stories Section
        do {
            let section = OWSTableSection()
            if StoryManager.areStoriesEnabled && sectionOptions.contains(.stories) && !conversationCollection.storyConversations.isEmpty {
                section.customHeaderView = NewStoryHeaderView(title: Strings.storiesSection, delegate: self)

                addExpandableConversations(
                    to: section,
                    sectionIndex: .stories,
                    conversations: conversationCollection.storyConversations,
                    maxConversationsToRender: maxStoryConversationsToRender,
                    isExpanded: isStorySectionExpanded,
                    markAsExpanded: { [weak self] in self?.isStorySectionExpanded = true }
                )
                hasContents = true
            }
            contents.addSection(section)
        }

        // Recents Section
        do {
            let section = OWSTableSection()
            if sectionOptions.contains(.recents) && !conversationCollection.recentConversations.isEmpty {
                if !shouldHideRecentConversationsTitle || sectionOptions == .recents {
                    section.headerTitle = Strings.recentsSection
                }
                addConversations(to: section, conversations: conversationCollection.recentConversations)
                hasContents = true
            }
            contents.addSection(section)
        }

        // Contacts Section
        do {
            let section = OWSTableSection()
            if sectionOptions.contains(.contacts) && !conversationCollection.contactConversations.isEmpty {
                if sectionOptions != .contacts {
                    section.headerTitle = Strings.signalContactsSection
                }
                addConversations(to: section, conversations: conversationCollection.contactConversations)
                hasContents = true
            }
            contents.addSection(section)
        }

        // Groups Section
        do {
            let section = OWSTableSection()
            if sectionOptions.contains(.groups) && !conversationCollection.groupConversations.isEmpty {
                if sectionOptions != .groups {
                    section.headerTitle = Strings.groupsSection
                }
                addConversations(to: section, conversations: conversationCollection.groupConversations)
                hasContents = true
            }
            contents.addSection(section)
        }

        // "No matches" Section
        if conversationCollection.isSearchResults,
           !hasContents {
            let section = OWSTableSection()
            section.add(.label(withText: OWSLocalizedString("CONVERSATION_SEARCH_NO_RESULTS",
                                                           comment: "keyboard toolbar label when no messages match the search string")))
            contents.addSection(section)
        }

        setContents(contents, shouldReload: shouldReload)
        restoreSelection()
    }

    private func addConversations(to section: OWSTableSection, conversations: [ConversationItem]) {
        for conversation in conversations {
            addConversationPickerCell(to: section, for: conversation)
        }
    }

    private func addConversationPickerCell(to section: OWSTableSection, for item: ConversationItem) {
        section.add(OWSTableItem(dequeueCellBlock: { tableView in
            guard let cell = tableView.dequeueReusableCell(withIdentifier: ConversationPickerCell.reuseIdentifier) as? ConversationPickerCell else {
                owsFailDebug("Missing cell.")
                return UITableViewCell()
            }
            Self.databaseStorage.read { transaction in
                cell.configure(conversationItem: item, transaction: transaction)
            }
            return cell
        },
        actionBlock: { [weak self] in
            self?.didToggleSection(conversation: item)
        }))
    }

    private func addExpandableConversations(
        to section: OWSTableSection,
        sectionIndex: ConversationPickerSection,
        conversations: [ConversationItem],
        maxConversationsToRender: Int,
        isExpanded: Bool,
        markAsExpanded: @escaping () -> Void
    ) {
        var conversationsToRender = conversations
        let hasMoreConversations = !isExpanded && conversationsToRender.count > maxConversationsToRender
        if hasMoreConversations {
            conversationsToRender = Array(conversationsToRender.prefix(maxConversationsToRender))
        }

        for conversation in conversationsToRender {
            addConversationPickerCell(to: section, for: conversation)
        }

        if hasMoreConversations {
            let expandedConversationIndices = (conversationsToRender.count..<conversations.count).map {
                IndexPath(row: $0, section: sectionIndex.rawValue)
            }

            section.add(OWSTableItem(
                customCellBlock: {
                    let cell = OWSTableItem.newCell()
                    cell.preservesSuperviewLayoutMargins = true
                    cell.contentView.preservesSuperviewLayoutMargins = true

                    let iconView = OWSTableItem.buildIconInCircleView(icon: .settingsShowAllMembers,
                                                                      iconSize: AvatarBuilder.smallAvatarSizePoints,
                                                                      innerIconSize: 24,
                                                                      iconTintColor: Theme.primaryTextColor)

                    let rowLabel = UILabel()
                    rowLabel.text = CommonStrings.seeAllButton
                    rowLabel.textColor = Theme.primaryTextColor
                    rowLabel.font = OWSTableItem.primaryLabelFont
                    rowLabel.lineBreakMode = .byTruncatingTail

                    let contentRow = UIStackView(arrangedSubviews: [ iconView, rowLabel ])
                    contentRow.spacing = ContactCellView.avatarTextHSpacing

                    cell.contentView.addSubview(contentRow)
                    contentRow.autoPinWidthToSuperviewMargins()
                    contentRow.autoPinHeightToSuperview(withMargin: 7)

                    return cell
                },
                actionBlock: { [weak self] in
                    guard let self = self else { return }

                    markAsExpanded()

                    if !expandedConversationIndices.isEmpty, let firstIndex = expandedConversationIndices.first {
                        self.tableView.beginUpdates()

                        // Delete the "See All" row.
                        self.tableView.deleteRows(at: [IndexPath(row: firstIndex.row, section: firstIndex.section)], with: .top)

                        // Insert the new rows.
                        self.tableView.insertRows(at: expandedConversationIndices, with: .top)

                        self.updateTableContents(shouldReload: false)
                        self.tableView.endUpdates()
                    } else {
                        self.updateTableContents()
                    }
                }
            ))
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

        if
            let maxVideoAttachmentDuration = maxVideoAttachmentDuration,
            let durationLimit = conversation.videoAttachmentDurationLimit,
            durationLimit < maxVideoAttachmentDuration
        {
            // Show a tooltip the first time this happens, but still let the
            // user select.
            showVideoSegmentingTooltip(on: indexPath)
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
        case .privateStory:
            owsFailDebug("Unexpectedly attempted to show unblock UI for story thread")
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

        let isBlocked: Bool = databaseStorage.read { transaction in
            guard let thread = conversation.getExistingThread(transaction: transaction) else {
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

        if
            let storyConversationItem = conversation as? StoryConversationItem,
            storyConversationItem.isMyStory,
            Self.databaseStorage.read(block: { !StoryManager.hasSetMyStoriesPrivacy(transaction: $0) }) {
            // Show first time story privacy settings if selecting my story and settings have'nt been
            // changed before.

            // Reload the row when we show the sheet, and when it goes away, so we reflect changes.
            let reloadRowBlock = { [weak self] in
                self?.tableView.reloadData()
                self?.tableView.selectRow(at: IndexPath(row: 0, section: 0), animated: false, scrollPosition: .none)
            }
            let sheetController = MyStorySettingsSheetViewController(willDisappear: reloadRowBlock)
            self.present(sheetController, animated: true, completion: reloadRowBlock)
        }
    }

    private func showBlockedByAnnouncementOnlyToast() {
        Logger.info("")

        let toastFormat = OWSLocalizedString("CONVERSATION_PICKER_BLOCKED_BY_ANNOUNCEMENT_ONLY",
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
        let labelText = conversations.map { $0.titleWithSneakyTransaction }.joined(separator: ", ")
        footerView.setNamesText(labelText, animated: animated)
        footerView.proceedButton.isEnabled = !conversations.isEmpty
    }

    private func showTooManySelectedToast() {
        Logger.info("Showing toast for too many chats selected")

        let toastFormat = OWSLocalizedString("CONVERSATION_PICKER_CAN_SELECT_NO_MORE_CONVERSATIONS_%d", tableName: "PluralAware",
                                            comment: "Momentarily shown to the user when attempting to select more conversations than is allowed. Embeds {{max number of conversations}} that can be selected.")

        let toastText = String.localizedStringWithFormat(toastFormat, kMaxPickerSelection)
        showToast(message: toastText)
    }

    private func showToast(message: String) {
        Logger.info("")

        let toastController = ToastController(text: message)

        let bottomInset = (view.bounds.height - tableView.frame.maxY)
        let kToastInset: CGFloat = bottomInset + 10
        toastController.presentToastView(from: .bottom, of: view, inset: kToastInset)
    }

    private var shownTooltipTypes = Set<ObjectIdentifier>()
    private var currentTooltip: VideoSegmentingTooltipView? {
        didSet {
            oldValue?.removeFromSuperview()
        }
    }

    private func showVideoSegmentingTooltip(on indexPath: IndexPath) {
        guard
            let conversation = self.conversation(for: indexPath),
            let cell = tableView.cellForRow(at: indexPath) as? ConversationPickerCell
        else {
            owsFailDebug("Showing a video trimming tooltop for an invalid index path")
            return
        }

        guard let text = conversation.videoAttachmentStoryLengthTooltipString else {
            return
        }

        let typeIdentifier = ObjectIdentifier(conversation.outgoingMessageClass)
        guard !shownTooltipTypes.contains(typeIdentifier) else {
            // We've already shown the tooltip for this type.
            return
        }
        shownTooltipTypes.insert(typeIdentifier)

        self.currentTooltip = VideoSegmentingTooltipView(
            fromView: tableView,
            widthReferenceView: cell,
            tailReferenceView: cell.tooltipTailReferenceView,
            text: text
        )
    }

    public override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // dismiss the tooltip when scrolling.
        currentTooltip = nil
    }
}

private class VideoSegmentingTooltipView: TooltipView {

    let text: String

    init(
        fromView: UIView,
        widthReferenceView: UIView,
        tailReferenceView: UIView,
        text: String
    ) {
        self.text = text
        super.init(
            fromView: fromView,
            widthReferenceView: widthReferenceView,
            tailReferenceView: tailReferenceView,
            wasTappedBlock: nil
        )
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func bubbleContentView() -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .ows_dynamicTypeFootnoteClamped
        label.textColor = .ows_white
        label.numberOfLines = 0

        let containerView = UIView()

        containerView.addSubview(label)
        label.autoPinEdgesToSuperviewEdges(with: .init(hMargin: 12, vMargin: 8))

        return containerView
    }

    public override var bubbleColor: UIColor { .ows_accentBlue }
    public override var bubbleHSpacing: CGFloat { 28 }
    public override var bubbleInsets: UIEdgeInsets { .zero }
    public override var stretchesBubbleHorizontally: Bool { true }

    public override var tailDirection: TooltipView.TailDirection { .up }
    public override var dismissOnTap: Bool { true }
}

// MARK: -

extension ConversationPickerViewController: NewStoryHeaderDelegate {
    public func newStoryHeaderView(_ newStoryHeaderView: NewStoryHeaderView, didCreateNewStoryItems items: [StoryConversationItem]) {
        isStorySectionExpanded = true
        conversationCollection = buildConversationCollection()
        items.forEach { selection.add($0) }
        restoreSelection()
    }
}

// MARK: -

extension ConversationPickerViewController: UISearchBarDelegate {
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        firstly {
            buildSearchResults(searchText: searchText)
        }.then { [weak self] searchResults -> Promise<ConversationCollection> in
            guard let self = self else {
                throw PromiseError.cancelled
            }

            // Make sure the search text hasn't changed since we started searching, otherwise bail.
            guard searchBar.text == searchText else { throw PromiseError.cancelled }

            return self.buildConversationCollection(searchResults: searchResults)
        }.done(on: .main) { [weak self] conversationCollection in
            guard let self = self else { return }

            self.conversationCollection = conversationCollection
        }.catch { error in
            if let error = error as? PromiseError, error == .cancelled { return }
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

    public func resetSearchBarText() {
        guard nil != searchBar.text?.nilIfEmpty else {
            return
        }
        searchBar.text = nil
        conversationCollection = buildConversationCollection()
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

        if shouldBatchUpdateIdentityKeys {
            guard let presentationTime = presentationTime else {
                owsFailDebug("Unexpectedly missing presentation time")
                return
            }

            let selectedRecipients = databaseStorage.read { transaction in
                conversations.flatMap { conversation in
                    conversation.getExistingThread(transaction: transaction)?.recipientAddresses(with: transaction) ?? []
                }
            }

            // Before continuing, prompt for any safety number changes that
            // we have learned about since the view was presented.
            let didHaveSafetyNumberChanges = SafetyNumberConfirmationSheet.presentIfNecessary(
                addresses: selectedRecipients,
                confirmationText: SafetyNumberStrings.confirmSendButton,
                untrustedThreshold: abs(presentationTime.timeIntervalSinceNow) + OWSIdentityManager.minimumUntrustedThreshold
            ) { didConfirmSafetyNumberChange in
                guard didConfirmSafetyNumberChange else { return }
                pickerDelegate.conversationPickerDidCompleteSelection(self)
            }

            guard !didHaveSafetyNumberChanges else { return }
        }

        pickerDelegate.conversationPickerDidCompleteSelection(self)
    }

    public func approvalMode(_ approvalFooterView: ApprovalFooterView) -> ApprovalMode {
        return approvalMode
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
        static let title = OWSLocalizedString("CONVERSATION_PICKER_TITLE", comment: "navbar header")
        static let recentsSection = OWSLocalizedString("CONVERSATION_PICKER_SECTION_RECENTS", comment: "table section header for section containing recent conversations")
        static let signalContactsSection = OWSLocalizedString("CONVERSATION_PICKER_SECTION_SIGNAL_CONTACTS", comment: "table section header for section containing contacts")
        static let groupsSection = OWSLocalizedString("CONVERSATION_PICKER_SECTION_GROUPS", comment: "table section header for section containing groups")
        static let storiesSection = OWSLocalizedString("CONVERSATION_PICKER_SECTION_STORIES", comment: "table section header for section containing stories")
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
        let configuration: ContactCellConfiguration
        switch conversationItem.messageRecipient {
        case .contact(let address):
            configuration = ContactCellConfiguration(address: address, localUserDisplayMode: .noteToSelf)
        case .group(let groupThreadId):
            guard let groupThread = TSGroupThread.anyFetchGroupThread(
                uniqueId: groupThreadId,
                transaction: transaction
            ) else {
                owsFailDebug("Failed to find group thread")
                return
            }
            configuration = ContactCellConfiguration(groupThread: groupThread, localUserDisplayMode: .noteToSelf)
        case .privateStory(_, let isMyStory):
            if isMyStory {
                guard let localAddress = tsAccountManager.localAddress else {
                    owsFailDebug("Unexpectedly missing local address")
                    return
                }
                configuration = ContactCellConfiguration(address: localAddress, localUserDisplayMode: .asUser)
                configuration.customName = conversationItem.title(transaction: transaction)
            } else {
                guard let image = conversationItem.image else {
                    owsFailDebug("Unexpectedly missing image for private story")
                    return
                }
                configuration = ContactCellConfiguration(name: conversationItem.title(transaction: transaction), avatar: image)
            }
        }
        if conversationItem.isBlocked {
            configuration.accessoryMessage = MessageStrings.conversationIsBlocked
        } else {
            configuration.accessoryView = buildAccessoryView(disappearingMessagesConfig: conversationItem.disappearingMessagesConfig)
        }

        if let storyItem = conversationItem as? StoryConversationItem {
            configuration.attributedSubtitle = storyItem.subtitle(transaction: transaction)?.asAttributedString
        }

        super.configure(configuration: configuration, transaction: transaction)

        // Apply theme.
        unselectedBadgeView.layer.borderColor = Theme.primaryIconColor.cgColor

        selectionStyle = .none
        applySelection()
    }

    // MARK: - Subviews

    let selectionBadgeSize = CGSize(square: 24)

    lazy var selectionView: UIView = {
        let container = UIView()

        container.addSubview(unselectedBadgeView)
        unselectedBadgeView.autoPinEdgesToSuperviewEdges()

        container.addSubview(selectedBadgeView)
        selectedBadgeView.autoPinEdgesToSuperviewEdges()

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
        let imageView = UIImageView(image: #imageLiteral(resourceName: "empty-circle-outline-24").withRenderingMode(.alwaysTemplate))
        imageView.tintColor = .ows_gray25
        return imageView
    }()

    lazy var selectedBadgeView: UIView = {
        let imageView = UIImageView(image: #imageLiteral(resourceName: "check-circle-solid-24").withRenderingMode(.alwaysTemplate))
        imageView.tintColor = Theme.accentBlueColor
        return imageView
    }()
}

// MARK: -

extension ConversationPickerViewController: ConversationPickerSelectionDelegate {
    func conversationPickerSelectionDidAdd() {
        AssertIsOnMainThread()

        pickerDelegate?.conversationPickerSelectionDidChange(self)

        // Clear the search text, if any.
        resetSearchBarText()
    }

    func conversationPickerSelectionDidRemove() {
        AssertIsOnMainThread()

        pickerDelegate?.conversationPickerSelectionDidChange(self)
    }
}

// MARK: -

protocol ConversationPickerSelectionDelegate: AnyObject {
    func conversationPickerSelectionDidAdd()
    func conversationPickerSelectionDidRemove()

    var shouldBatchUpdateIdentityKeys: Bool { get }
}

// MARK: -

public class ConversationPickerSelection: Dependencies {
    fileprivate weak var delegate: ConversationPickerSelectionDelegate?

    public private(set) var conversations: [ConversationItem] = []

    public required init() {}

    public func add(_ conversation: ConversationItem) {
        conversations.append(conversation)
        delegate?.conversationPickerSelectionDidAdd()

        guard delegate?.shouldBatchUpdateIdentityKeys == true else { return }

        let recipients: [SignalServiceAddress] = databaseStorage.read { transaction in
            guard let thread = conversation.getExistingThread(transaction: transaction) else { return [] }
            return thread.recipientAddresses(with: transaction)
        }

        Logger.info("Batch updating identity keys for \(recipients.count) selected recipients.")
        identityManager.batchUpdateIdentityKeys(addresses: recipients).done {
            Logger.info("Successfully batch updated identity keys.")
        }.catch { error in
            owsFailDebug("Failed to batch update identity keys: \(error)")
        }
    }

    public func remove(_ conversation: ConversationItem) {
        conversations.removeAll {
            ($0 is StoryConversationItem) == (conversation is StoryConversationItem) && $0.messageRecipient == conversation.messageRecipient
        }
        delegate?.conversationPickerSelectionDidRemove()
    }

    public func isSelected(conversation: ConversationItem) -> Bool {
        conversations.contains {
            ($0 is StoryConversationItem) == (conversation is StoryConversationItem) && $0.messageRecipient == conversation.messageRecipient
        }
    }
}

// MARK: -

private enum ConversationPickerSection: Int, CaseIterable {
    case stories, recents, signalContacts, groups
}

// MARK: -

private struct ConversationCollection {
    static let empty: ConversationCollection = ConversationCollection(contactConversations: [],
                                                                      recentConversations: [],
                                                                      groupConversations: [],
                                                                      storyConversations: [],
                                                                      isSearchResults: false)

    let contactConversations: [ConversationItem]
    let recentConversations: [ConversationItem]
    let groupConversations: [ConversationItem]
    let storyConversations: [ConversationItem]
    let isSearchResults: Bool

    var allConversations: [ConversationItem] {
        recentConversations + contactConversations + groupConversations + storyConversations
    }

    private func conversations(section: ConversationPickerSection) -> [ConversationItem] {
        switch section {
        case .recents:
            return recentConversations
        case .signalContacts:
            return contactConversations
        case .groups:
            return groupConversations
        case .stories:
            return storyConversations
        }
    }

    fileprivate func indexPath(conversation: ConversationItem) -> IndexPath? {
        switch conversation.messageRecipient {
        case .contact:
            if let row = (recentConversations.map { $0.messageRecipient }).firstIndex(of: conversation.messageRecipient) {
                return IndexPath(row: row, section: ConversationPickerSection.recents.rawValue)
            } else if let row = (contactConversations.map { $0.messageRecipient }).firstIndex(of: conversation.messageRecipient) {
                return IndexPath(row: row, section: ConversationPickerSection.signalContacts.rawValue)
            } else {
                return nil
            }
        case .group:
            if conversation is StoryConversationItem {
                if let row = (storyConversations.map { $0.messageRecipient }).firstIndex(of: conversation.messageRecipient) {
                    return IndexPath(row: row, section: ConversationPickerSection.stories.rawValue)
                } else {
                    return nil
                }
            } else if let row = (recentConversations.map { $0.messageRecipient }).firstIndex(of: conversation.messageRecipient) {
                return IndexPath(row: row, section: ConversationPickerSection.recents.rawValue)
            } else if let row = (groupConversations.map { $0.messageRecipient }).firstIndex(of: conversation.messageRecipient) {
                return IndexPath(row: row, section: ConversationPickerSection.groups.rawValue)
            } else {
                return nil
            }
        case .privateStory:
            if let row = (storyConversations.map { $0.messageRecipient }).firstIndex(of: conversation.messageRecipient) {
                return IndexPath(row: row, section: ConversationPickerSection.stories.rawValue)
            } else {
                return nil
            }
        }
    }

    fileprivate func conversation(for indexPath: IndexPath) -> ConversationItem? {
        guard let section = ConversationPickerSection(rawValue: indexPath.section) else {
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
