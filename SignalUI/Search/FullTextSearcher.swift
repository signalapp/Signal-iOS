//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import Foundation
import LibSignalClient
public import SignalServiceKit

public typealias MessageSortKey = UInt64

public struct ConversationSortKey: Comparable {
    let isContactThread: Bool
    let creationDate: Date?
    let lastInteractionRowId: UInt64

    // MARK: Comparable

    public static func < (lhs: ConversationSortKey, rhs: ConversationSortKey) -> Bool {
        // always show matching contact results first
        if lhs.isContactThread != rhs.isContactThread {
            return lhs.isContactThread
        }

        if lhs.lastInteractionRowId != rhs.lastInteractionRowId {
            return lhs.lastInteractionRowId < rhs.lastInteractionRowId
        }

        let lhsDate = lhs.creationDate ?? .distantPast
        let rhsDate = rhs.creationDate ?? .distantPast
        return lhsDate < rhsDate
    }
}

// MARK: -

public class ConversationSearchResult<SortKey>: Comparable where SortKey: Comparable {
    public let threadViewModel: ThreadViewModel

    public let messageId: String?
    public let messageDate: Date?

    public let snippet: CVTextValue?

    private let sortKey: SortKey

    init(threadViewModel: ThreadViewModel, sortKey: SortKey, messageId: String? = nil, messageDate: Date? = nil, snippet: CVTextValue? = nil) {
        self.threadViewModel = threadViewModel
        self.sortKey = sortKey
        self.messageId = messageId
        self.messageDate = messageDate
        self.snippet = snippet
    }

    // MARK: Comparable

    public static func < (lhs: ConversationSearchResult, rhs: ConversationSearchResult) -> Bool {
        return lhs.sortKey < rhs.sortKey
    }

    // MARK: Equatable

    public static func == (lhs: ConversationSearchResult, rhs: ConversationSearchResult) -> Bool {
        return (
            lhs.threadViewModel.threadRecord.uniqueId == rhs.threadViewModel.threadRecord.uniqueId
            && lhs.messageId == rhs.messageId
        )
    }
}

// MARK: -

public class ContactSearchResult: Comparable {

    public let recipientAddress: SignalServiceAddress
    private let comparableName: ComparableDisplayName
    private let lastInteractionRowID: UInt64?

    init(recipientAddress: SignalServiceAddress, transaction: SDSAnyReadTransaction) {
        self.recipientAddress = recipientAddress
        self.comparableName = ComparableDisplayName(
            address: recipientAddress,
            displayName: SSKEnvironment.shared.contactManagerRef.displayName(for: recipientAddress, tx: transaction),
            config: .current()
        )
        let thread = ContactThreadFinder().contactThread(for: recipientAddress, tx: transaction)
        lastInteractionRowID = thread?.lastInteractionRowId
    }

    // MARK: Comparable

    public static func < (lhs: ContactSearchResult, rhs: ContactSearchResult) -> Bool {
        // Sort contacts by most recent chat, falling back to alphabetical
        switch (lhs.lastInteractionRowID, rhs.lastInteractionRowID) {
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case let (.some(lhsRowID), .some(rhsRowID)):
            return lhsRowID > rhsRowID
        case (.none, .none):
            return lhs.comparableName < rhs.comparableName
        }
    }

    // MARK: Equatable

    public static func == (lhs: ContactSearchResult, rhs: ContactSearchResult) -> Bool {
        return lhs.recipientAddress == rhs.recipientAddress
    }
}

// MARK: -

/// Can represent either a group thread with stories, or a private story thread.
public class StorySearchResult: Comparable {

    public let thread: TSThread

    private let sortKey: ConversationSortKey

    init(thread: TSThread, sortKey: ConversationSortKey) {
        self.thread = thread
        self.sortKey = sortKey
    }

    // MARK: Comparable

    public static func < (lhs: StorySearchResult, rhs: StorySearchResult) -> Bool {
        return lhs.sortKey < rhs.sortKey
    }

    // MARK: Equatable

    public static func == (lhs: StorySearchResult, rhs: StorySearchResult) -> Bool {
        return lhs.thread.uniqueId == rhs.thread.uniqueId
    }
}

// MARK: -

public class HomeScreenSearchResultSet: NSObject {
    public let searchText: String
    public let contactThreadResults: [ConversationSearchResult<ConversationSortKey>]
    public let groupThreadResults: [GroupSearchResult]
    public let contactResults: [ContactSearchResult]
    public let messageResults: [ConversationSearchResult<MessageSortKey>]

    public init(
        searchText: String,
        contactThreadResults: [ConversationSearchResult<ConversationSortKey>],
        groupThreadResults: [GroupSearchResult],
        contactResults: [ContactSearchResult],
        messageResults: [ConversationSearchResult<MessageSortKey>]
    ) {
        self.searchText = searchText
        self.contactThreadResults = contactThreadResults
        self.groupThreadResults = groupThreadResults
        self.contactResults = contactResults
        self.messageResults = messageResults
    }

    public class var empty: HomeScreenSearchResultSet {
        return HomeScreenSearchResultSet(searchText: "", contactThreadResults: [], groupThreadResults: [], contactResults: [], messageResults: [])
    }

    public var isEmpty: Bool {
        return contactThreadResults.isEmpty && groupThreadResults.isEmpty && contactResults.isEmpty && messageResults.isEmpty
    }
}

// MARK: -

public class GroupSearchResult: Comparable {

    public let threadViewModel: ThreadViewModel
    public let matchedMembersSnippet: String?

    private let sortKey: ConversationSortKey

    class func withMatchedMembersSnippet(
        groupThread: TSGroupThread,
        threadViewModel: ThreadViewModel,
        sortKey: ConversationSortKey,
        searchText: String,
        nameResolver: NameResolver,
        transaction: SDSAnyReadTransaction
    ) -> GroupSearchResult {
        owsAssertDebug(threadViewModel.threadRecord === groupThread)
        let matchedMembers = groupThread.sortedMemberNames(
            searchText: searchText,
            includingBlocked: true,
            nameResolver: nameResolver,
            transaction: transaction
        )
        let matchedMembersSnippet = matchedMembers.joined(separator: ", ")
        return GroupSearchResult(threadViewModel: threadViewModel, sortKey: sortKey, matchedMembersSnippet: matchedMembersSnippet)
    }

    init(threadViewModel: ThreadViewModel, sortKey: ConversationSortKey, matchedMembersSnippet: String? = nil) {
        self.threadViewModel = threadViewModel
        self.sortKey = sortKey
        self.matchedMembersSnippet = matchedMembersSnippet
    }

    // MARK: Comparable

    public static func < (lhs: GroupSearchResult, rhs: GroupSearchResult) -> Bool {
        return lhs.sortKey < rhs.sortKey
    }

    // MARK: Equatable

    public static func == (lhs: GroupSearchResult, rhs: GroupSearchResult) -> Bool {
        return lhs.threadViewModel.threadRecord.uniqueId == rhs.threadViewModel.threadRecord.uniqueId
    }
}

// MARK: -

public struct RecipientSearchResultSet {
    public let searchText: String
    public let contactResults: [ContactSearchResult]
    public let groupResults: [GroupSearchResult]
    public let storyResults: [StorySearchResult]

    public var groupThreads: [TSGroupThread] {
        return groupResults.compactMap { $0.threadViewModel.threadRecord as? TSGroupThread }
    }

    public var storyThreads: [TSThread] { storyResults.map(\.thread) }
}

// MARK: -

public class MessageSearchResult: NSObject, Comparable {

    public let messageId: String
    public let sortId: UInt64

    init(messageId: String, sortId: UInt64) {
        self.messageId = messageId
        self.sortId = sortId
    }

    // MARK: - Comparable

    public static func < (lhs: MessageSearchResult, rhs: MessageSearchResult) -> Bool {
        return lhs.sortId < rhs.sortId
    }
}

// MARK: -

public class ConversationScreenSearchResultSet: NSObject {

    public let searchText: String

    public let messages: [MessageSearchResult]

    public lazy var messageSortIds: [UInt64] = {
        return messages.map { $0.sortId }
    }()

    // MARK: Static members

    public static let empty: ConversationScreenSearchResultSet = ConversationScreenSearchResultSet(searchText: "", messages: [])

    // MARK: Init

    public init(searchText: String, messages: [MessageSearchResult]) {
        self.searchText = searchText
        self.messages = messages
    }

    // MARK: - CustomDebugStringConvertible

    override public var debugDescription: String {
        return "ConversationScreenSearchResultSet(searchText: \(searchText), messages: [\(messages.count) matches])"
    }
}

// MARK: -

public class FullTextSearcher: NSObject {

    public static let kDefaultMaxResults: Int = 500

    public static let shared: FullTextSearcher = FullTextSearcher()

    public func searchForRecipients(
        searchText: String,
        includeLocalUser: Bool,
        includeStories: Bool,
        maxResults: Int = kDefaultMaxResults,
        tx: SDSAnyReadTransaction
    ) -> RecipientSearchResultSet {
        var groupResults = [GroupSearchResult]()
        var storyResults = [StorySearchResult]()

        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
            owsFail("Can't search if you've never been registered.")
        }

        var addresses = SearchableNameFinder(
            contactManager: SSKEnvironment.shared.contactManagerRef,
            searchableNameIndexer: DependenciesBridge.shared.searchableNameIndexer,
            phoneNumberVisibilityFetcher: DependenciesBridge.shared.phoneNumberVisibilityFetcher,
            recipientDatabaseTable: DependenciesBridge.shared.recipientDatabaseTable
        ).searchNames(
            for: searchText,
            maxResults: maxResults,
            localIdentifiers: localIdentifiers,
            tx: tx.asV2Read,
            checkCancellation: {},
            addGroupThread: { groupThread in
                let sortKey = ConversationSortKey(
                    isContactThread: false,
                    creationDate: groupThread.creationDate,
                    lastInteractionRowId: groupThread.lastInteractionRowId
                )
                let threadViewModel = ThreadViewModel(
                    thread: groupThread,
                    forChatList: true,
                    transaction: tx
                )
                let searchResult = GroupSearchResult(threadViewModel: threadViewModel, sortKey: sortKey)
                groupResults.append(searchResult)

                if includeStories, groupThread.isStorySendEnabled(transaction: tx) {
                    let searchResult = StorySearchResult(thread: groupThread, sortKey: sortKey)
                    storyResults.append(searchResult)
                }
            },
            addStoryThread: { storyThread in
                // Don't show disabled private story threads; these are queued up
                // to be deleted.
                if includeStories, storyThread.storyViewMode != .disabled {
                    let sortKey = ConversationSortKey(
                        isContactThread: false,
                        creationDate: storyThread.creationDate,
                        lastInteractionRowId: storyThread.lastInteractionRowId
                    )
                    let searchResult = StorySearchResult(thread: storyThread, sortKey: sortKey)
                    storyResults.append(searchResult)
                }
            }
        )

        var contactResults: [ContactSearchResult] = []

        addresses.removeAll(where: { $0 == localIdentifiers.aciAddress })
        if includeLocalUser, noteToSelfMatch(searchText: searchText, localIdentifiers: localIdentifiers, tx: tx) != .none {
            contactResults.append(ContactSearchResult(recipientAddress: localIdentifiers.aciAddress, transaction: tx))
        }

        for address in addresses {
            if SSKEnvironment.shared.profileManagerRef.isUser(inProfileWhitelist: address, transaction: tx) {
                contactResults.append(ContactSearchResult(recipientAddress: address, transaction: tx))
            }
        }

        return RecipientSearchResultSet(
            searchText: searchText,
            contactResults: contactResults.sorted(),
            groupResults: groupResults.sorted(by: >),
            storyResults: storyResults.sorted(by: >)
        )
    }

    private enum NoteToSelfMatch {
        case nameOrNumber
        case noteToSelf
        case none
    }

    private func noteToSelfMatch(searchText: String, localIdentifiers: LocalIdentifiers, tx: SDSAnyReadTransaction) -> NoteToSelfMatch {
        let searchTerms = searchText.split(separator: " ")
        if searchTerms.contains(where: { localIdentifiers.phoneNumber.contains($0) }) {
            return .nameOrNumber
        }
        let displayName = SSKEnvironment.shared.contactManagerRef.displayName(for: localIdentifiers.aciAddress, tx: tx).resolvedValue()
        if searchTerms.contains(where: { displayName.contains($0) }) {
            return .nameOrNumber
        }
        if searchTerms.contains(where: { MessageStrings.noteToSelf.contains($0) }) {
            return .noteToSelf
        }
        return .none
    }

    public func searchForHomeScreen(
        searchText: String,
        maxResults: Int = kDefaultMaxResults,
        isCanceled: () -> Bool,
        transaction: SDSAnyReadTransaction
    ) -> HomeScreenSearchResultSet? {
        do {
            return try _searchForHomeScreen(
                searchText: searchText,
                maxResults: maxResults,
                isCanceled: isCanceled,
                transaction: transaction
            )
        } catch is CancellationError {
            return nil
        } catch {
            owsFailDebug("Couldn't search: \(error)")
            return nil
        }
    }

    private func _searchForHomeScreen(
        searchText: String,
        maxResults: Int,
        isCanceled: () -> Bool,
        transaction: SDSAnyReadTransaction
    ) throws -> HomeScreenSearchResultSet? {
        var contactResults = [ContactSearchResult]()
        var contactThreadResults = [ConversationSearchResult<ConversationSortKey>]()
        var groupResults: [GroupSearchResult] = []
        var groupThreadIds = Set<String>()
        var messages: [UInt64: ConversationSearchResult<MessageSortKey>] = [:]

        let nameResolver = NameResolverImpl(contactsManager: SSKEnvironment.shared.contactManagerRef)

        var threadCache = [String: TSThread?]()
        func fetchThread<T: TSThread>(threadUniqueId: String) -> T? {
            if let thread = threadCache[threadUniqueId] {
                return thread as? T
            }
            let thread = TSThread.anyFetch(uniqueId: threadUniqueId, transaction: transaction)
            threadCache[threadUniqueId] = thread
            return thread as? T
        }

        var threadViewModelCache = [String: ThreadViewModel]()
        func fetchThreadViewModel(for thread: TSThread) -> ThreadViewModel {
            if let threadViewModel = threadViewModelCache[thread.uniqueId] {
                return threadViewModel
            }
            let threadViewModel = ThreadViewModel(
                thread: thread,
                forChatList: true,
                transaction: transaction
            )
            threadViewModelCache[thread.uniqueId] = threadViewModel
            return threadViewModel
        }

        func fetchGroupThreadIds(for address: SignalServiceAddress) -> [String] {
            return TSGroupThread.groupThreadIds(with: address, transaction: transaction)
        }

        func fetchMentionedMessages(for address: SignalServiceAddress) -> [TSMessage] {
            guard let aci = address.serviceId as? Aci else { return [] }
            return MentionFinder.messagesMentioning(aci: aci, tx: transaction)
        }

        func shouldIncludeResult(for thread: TSThread) -> Bool {
            return thread.shouldThreadBeVisible
        }

        func appendGroup(threadUniqueId: String, groupThread: @autoclosure () -> TSGroupThread?) {
            // Don't add threads multiple times.
            guard groupThreadIds.insert(threadUniqueId).inserted else {
                return
            }
            // Don't fetch the thread unless necessary.
            guard let groupThread = groupThread() else {
                owsFailDebug("Unexpectedly missing group thread.")
                return
            }
            guard shouldIncludeResult(for: groupThread) else {
                return
            }

            let threadViewModel = fetchThreadViewModel(for: groupThread)
            let sortKey = ConversationSortKey(
                isContactThread: false,
                creationDate: groupThread.creationDate,
                lastInteractionRowId: groupThread.lastInteractionRowId
            )

            let searchResult = GroupSearchResult.withMatchedMembersSnippet(
                groupThread: groupThread,
                threadViewModel: threadViewModel,
                sortKey: sortKey,
                searchText: searchText,
                nameResolver: nameResolver,
                transaction: transaction
            )
            groupResults.append(searchResult)
        }

        func appendMessage(_ message: TSMessage, snippet: CVTextValue?) {
            guard let thread: TSThread = fetchThread(threadUniqueId: message.uniqueThreadId) else {
                owsFailDebug("Missing thread: \(type(of: message))")
                return
            }

            let threadViewModel = fetchThreadViewModel(for: thread)
            let sortKey = message.sortId
            let searchResult = ConversationSearchResult(
                threadViewModel: threadViewModel,
                sortKey: sortKey,
                messageId: message.uniqueId,
                messageDate: Date(millisecondsSince1970: message.timestamp),
                snippet: snippet
            )
            guard messages[sortKey] == nil else { return }
            messages[sortKey] = searchResult
        }

        func appendAddress(
            _ address: SignalServiceAddress,
            isInWhitelist: @autoclosure () -> Bool,
            fetchGroups: Bool,
            fetchMentions: Bool
        ) {
            if
                let contactThread = TSContactThread.getWithContactAddress(address, transaction: transaction),
                shouldIncludeResult(for: contactThread)
            {
                contactThreadResults.append(ConversationSearchResult(
                    threadViewModel: fetchThreadViewModel(for: contactThread),
                    sortKey: ConversationSortKey(
                        isContactThread: true,
                        creationDate: contactThread.creationDate,
                        lastInteractionRowId: contactThread.lastInteractionRowId
                    )
                ))
            } else if isInWhitelist() {
                contactResults.append(ContactSearchResult(recipientAddress: address, transaction: transaction))
            }

            if fetchGroups {
                fetchGroupThreadIds(for: address).forEach { groupThreadId in
                    appendGroup(
                        threadUniqueId: groupThreadId,
                        groupThread: fetchThread(threadUniqueId: groupThreadId)
                    )
                }
            }

            if fetchMentions {
                fetchMentionedMessages(for: address).forEach { message in
                    appendMessage(message, snippet: .messageBody(message.conversationListPreviewText(transaction)))
                }
            }
        }

        func remainingResultCount() -> Int {
            return max(0, maxResults - (groupResults.count + contactResults.count + contactThreadResults.count + messages.count))
        }

        // We search for each type of result independently. The order here matters
        // – we want to give priority to chat and contact results above message
        // results. This makes sure if I search for a string like "Matthew" the
        // first results will be the chat with my contact named "Matthew", rather
        // than messages where his name was mentioned.

        // Check if we've been canceled before running the first query. If we have
        // to wait a while for the database to be available, this search may have
        // already been canceled.
        guard !isCanceled() else {
            return nil
        }

        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: transaction.asV2Read) else {
            owsFail("Can't search if you've never been registered.")
        }

        var addresses = try SearchableNameFinder(
            contactManager: SSKEnvironment.shared.contactManagerRef,
            searchableNameIndexer: DependenciesBridge.shared.searchableNameIndexer,
            phoneNumberVisibilityFetcher: DependenciesBridge.shared.phoneNumberVisibilityFetcher,
            recipientDatabaseTable: DependenciesBridge.shared.recipientDatabaseTable
        ).searchNames(
            for: searchText,
            maxResults: remainingResultCount(),
            localIdentifiers: localIdentifiers,
            tx: transaction.asV2Read,
            checkCancellation: { if isCanceled() { throw CancellationError() } },
            addGroupThread: { groupThread in
                appendGroup(threadUniqueId: groupThread.uniqueId, groupThread: groupThread)
            },
            addStoryThread: { _ in
            }
        )

        guard !isCanceled() else {
            return nil
        }

        addresses.removeAll(where: { $0 == localIdentifiers.aciAddress })
        switch noteToSelfMatch(searchText: searchText, localIdentifiers: localIdentifiers, tx: transaction) {
        case .nameOrNumber:
            appendAddress(localIdentifiers.aciAddress, isInWhitelist: true, fetchGroups: true, fetchMentions: false)
        case .noteToSelf:
            appendAddress(localIdentifiers.aciAddress, isInWhitelist: true, fetchGroups: false, fetchMentions: false)
        case .none:
            break
        }

        guard !isCanceled() else {
            return nil
        }

        for address in addresses {
            appendAddress(
                address,
                isInWhitelist: SSKEnvironment.shared.profileManagerRef.isUser(inProfileWhitelist: address, transaction: transaction),
                fetchGroups: true,
                fetchMentions: true
            )
        }

        guard !isCanceled() else {
            return nil
        }

        FullTextSearchIndexer.search(
            for: searchText,
            maxResults: remainingResultCount(),
            tx: transaction
        ) { (message: TSMessage, snippet: String?, stop) in
            if isCanceled() || remainingResultCount() == 0 {
                stop = true
                return
            }
            let styledSnippet: CVTextValue? = { () -> CVTextValue? in
                guard let snippet else {
                    return nil
                }
                let attributeKey = NSAttributedString.Key("OWSSearchMatch")
                let matchStyle = BonMot.StringStyle(
                    .xmlRules([
                        .style(FullTextSearchIndexer.matchTag, StringStyle(.extraAttributes([attributeKey: 0])))
                    ])
                )
                let matchStyleApplied = snippet.styled(with: matchStyle)
                var styles = [NSRangedValue<MessageBodyRanges.Style>]()
                matchStyleApplied.enumerateAttributes(in: matchStyleApplied.entireRange, using: { attrs, range, _ in
                    guard attrs[attributeKey] != nil else {
                        return
                    }
                    styles.append(NSRangedValue(.bold, range: range))
                })
                let mergedMessageBody: MessageBody
                if let messageBody = message.conversationListSearchResultsBody(transaction) {
                    mergedMessageBody = messageBody.mergeIntoFirstMatchOfStyledSubstring(matchStyleApplied.string, styles: styles)
                } else {
                    let singleStyles = styles.flatMap { style in
                        return style.value.contents.map {
                            return NSRangedValue($0, range: style.range)
                        }
                    }
                    mergedMessageBody = MessageBody(text: matchStyleApplied.string, ranges: .init(mentions: [:], styles: singleStyles))
                }
                return .messageBody(mergedMessageBody
                    .hydrating(mentionHydrator: ContactsMentionHydrator.mentionHydrator(transaction: transaction.asV2Read)))
            }()
            appendMessage(message, snippet: styledSnippet)
        }

        guard !isCanceled() else {
            return nil
        }

        // Order the conversation and message results in reverse chronological order.
        // Order "Other Contacts" by name.

        return HomeScreenSearchResultSet(
            searchText: searchText,
            contactThreadResults: contactThreadResults.sorted(by: >),
            groupThreadResults: groupResults.sorted(by: >),
            contactResults: contactResults.sorted(by: <),
            messageResults: messages.values.sorted(by: >)
        )
    }

    public func searchWithinConversation(
        thread: TSThread,
        searchText: String,
        maxResults: Int = kDefaultMaxResults,
        transaction: SDSAnyReadTransaction
    ) -> ConversationScreenSearchResultSet {
        var messages: [UInt64: MessageSearchResult] = [:]

        func appendMessage(_ message: TSMessage) {
            let messageId = message.uniqueId
            let searchResult = MessageSearchResult(messageId: messageId, sortId: message.sortId)
            messages[message.sortId] = searchResult
        }

        FullTextSearchIndexer.search(
            for: searchText,
            maxResults: maxResults,
            tx: transaction
        ) { message, _, stop in
            guard messages.count < maxResults else {
                stop = true
                return
            }
            if message.uniqueThreadId == thread.uniqueId {
                appendMessage(message)
            }
        }

        let canSearchForMentions: Bool = thread is TSGroupThread
        if canSearchForMentions {
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: transaction.asV2Read) else {
                owsFail("Can't search if you've never been registered.")
            }
            let addresses = SearchableNameFinder(
                contactManager: SSKEnvironment.shared.contactManagerRef,
                searchableNameIndexer: DependenciesBridge.shared.searchableNameIndexer,
                phoneNumberVisibilityFetcher: DependenciesBridge.shared.phoneNumberVisibilityFetcher,
                recipientDatabaseTable: DependenciesBridge.shared.recipientDatabaseTable
            ).searchNames(
                for: searchText,
                maxResults: maxResults - messages.count,
                localIdentifiers: localIdentifiers,
                tx: transaction.asV2Read,
                checkCancellation: {},
                addGroupThread: { _ in },
                addStoryThread: { _ in }
            )
            for address in addresses {
                guard let aci = address.serviceId as? Aci else {
                    continue
                }
                let messagesMentioningAccount = MentionFinder.messagesMentioning(aci: aci, in: thread, tx: transaction)
                messagesMentioningAccount.forEach { appendMessage($0) }
            }
        }

        // We want most recent first
        let sortedMessages = messages.values.sorted(by: >)

        return ConversationScreenSearchResultSet(searchText: searchText, messages: sortedMessages)
    }
}
