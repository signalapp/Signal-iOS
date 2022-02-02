//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation


public typealias MessageSortKey = UInt64
public struct ConversationSortKey: Comparable {
    let creationDate: Date
    let lastMessageReceivedAtDate: Date?

    // MARK: Comparable

    public static func < (lhs: ConversationSortKey, rhs: ConversationSortKey) -> Bool {
        let lhsDate = lhs.lastMessageReceivedAtDate ?? lhs.creationDate
        let rhsDate = rhs.lastMessageReceivedAtDate ?? rhs.creationDate
        return lhsDate < rhsDate
    }
}

public class ConversationSearchResult<SortKey>: Comparable where SortKey: Comparable {
    public let thread: ThreadViewModel

    public let messageId: String?
    public let messageDate: Date?

    public let snippet: String?

    private let sortKey: SortKey

    init(thread: ThreadViewModel, sortKey: SortKey, messageId: String? = nil, messageDate: Date? = nil, snippet: String? = nil) {
        self.thread = thread
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
        return lhs.thread.threadRecord.uniqueId == rhs.thread.threadRecord.uniqueId &&
            lhs.messageId == rhs.messageId
    }
}

public class HomeScreenSearchResultSet: NSObject {
    public let searchText: String
    public let conversations: [ConversationSearchResult<ConversationSortKey>]
    public let messages: [ConversationSearchResult<MessageSortKey>]

    public init(searchText: String, conversations: [ConversationSearchResult<ConversationSortKey>], messages: [ConversationSearchResult<MessageSortKey>]) {
        self.searchText = searchText
        self.conversations = conversations
        self.messages = messages
    }

    public class var empty: HomeScreenSearchResultSet {
        return HomeScreenSearchResultSet(searchText: "", conversations: [], messages: [])
    }
    
    public class var noteToSelfOnly: HomeScreenSearchResultSet {
        var conversations: [ConversationSearchResult<ConversationSortKey>] = []
        Storage.read { transaction in
            if let thread = TSContactThread.getWithContactSessionID(getUserHexEncodedPublicKey(), transaction: transaction) {
                let threadViewModel = ThreadViewModel(thread: thread, transaction: transaction)
                let sortKey = ConversationSortKey(creationDate: thread.creationDate,
                                                  lastMessageReceivedAtDate: thread.lastInteractionForInbox(transaction: transaction)?.receivedAtDate())
                let searchResult = ConversationSearchResult(thread: threadViewModel, sortKey: sortKey)
                conversations.append(searchResult)
            }
        }
        return HomeScreenSearchResultSet(searchText: "", conversations: conversations, messages: [])
    }

    public var isEmpty: Bool {
        return conversations.isEmpty && messages.isEmpty
    }
}

@objc
public class GroupSearchResult: NSObject, Comparable {
    public let thread: ThreadViewModel

    private let sortKey: ConversationSortKey

    init(thread: ThreadViewModel, sortKey: ConversationSortKey) {
        self.thread = thread
        self.sortKey = sortKey
    }

    // MARK: Comparable

    public static func < (lhs: GroupSearchResult, rhs: GroupSearchResult) -> Bool {
        return lhs.sortKey < rhs.sortKey
    }

    // MARK: Equatable

    public static func == (lhs: GroupSearchResult, rhs: GroupSearchResult) -> Bool {
        return lhs.thread.threadRecord.uniqueId == rhs.thread.threadRecord.uniqueId
    }
}

@objc
public class ComposeScreenSearchResultSet: NSObject {

    @objc
    public let searchText: String

    @objc
    public let groups: [GroupSearchResult]

    @objc
    public var groupThreads: [TSGroupThread] {
        return groups.compactMap { $0.thread.threadRecord as? TSGroupThread }
    }

    public init(searchText: String, groups: [GroupSearchResult]) {
        self.searchText = searchText
        self.groups = groups
    }

    @objc
    public static let empty = ComposeScreenSearchResultSet(searchText: "", groups: [])

    @objc
    public var isEmpty: Bool {
        return groups.isEmpty
    }
}

@objc
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

@objc
public class ConversationScreenSearchResultSet: NSObject {

    @objc
    public let searchText: String

    @objc
    public let messages: [MessageSearchResult]

    @objc
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

@objc
public class FullTextSearcher: NSObject {

    // MARK: - Dependencies

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    // MARK: - 

    private let finder: FullTextSearchFinder

    @objc
    public static let shared: FullTextSearcher = FullTextSearcher()
    override private init() {
        finder = FullTextSearchFinder()
        super.init()
    }

    @objc
    public func searchForComposeScreen(searchText: String,
                                       transaction: YapDatabaseReadTransaction) -> ComposeScreenSearchResultSet {

        var groups: [GroupSearchResult] = []

        self.finder.enumerateObjects(searchText: searchText, transaction: transaction) { (match: Any, snippet: String?) in

            switch match {
            case let groupThread as TSGroupThread:
                let sortKey = ConversationSortKey(creationDate: groupThread.creationDate,
                                                  lastMessageReceivedAtDate: groupThread.lastInteractionForInbox(transaction: transaction)?.receivedAtDate())
                let threadViewModel = ThreadViewModel(thread: groupThread, transaction: transaction)
                let searchResult = GroupSearchResult(thread: threadViewModel, sortKey: sortKey)
                groups.append(searchResult)
            case is TSContactThread:
                // not included in compose screen results
                break
            case is TSMessage:
                // not included in compose screen results
                break
            default:
                owsFailDebug("unhandled item: \(match)")
            }
        }

        // Order the conversation and message results in reverse chronological order.
        // The contact results are pre-sorted by display name.
        groups.sort(by: >)

        return ComposeScreenSearchResultSet(searchText: searchText, groups: groups)
    }

    public func searchForHomeScreen(searchText: String,
                                    maxSearchResults: Int? = nil,
                                    transaction: YapDatabaseReadTransaction) -> HomeScreenSearchResultSet {

        var conversations: [ConversationSearchResult<ConversationSortKey>] = []
        var messages: [ConversationSearchResult<MessageSortKey>] = []

        var existingConversationRecipientIds: Set<String> = Set()

        self.finder.enumerateObjects(searchText: searchText, maxSearchResults: maxSearchResults, transaction: transaction) { (match: Any, snippet: String?) in

            if let thread = match as? TSThread {
                let threadViewModel = ThreadViewModel(thread: thread, transaction: transaction)
                let sortKey = ConversationSortKey(creationDate: thread.creationDate,
                                                  lastMessageReceivedAtDate: thread.lastInteractionForInbox(transaction: transaction)?.receivedAtDate())
                let searchResult = ConversationSearchResult(thread: threadViewModel, sortKey: sortKey)

                if let contactThread = thread as? TSContactThread {
                    let recipientId = contactThread.contactSessionID()
                    existingConversationRecipientIds.insert(recipientId)
                }

                conversations.append(searchResult)
            } else if let message = match as? TSMessage {
                let thread = message.thread(with: transaction)

                let threadViewModel = ThreadViewModel(thread: thread, transaction: transaction)
                let sortKey = message.sortId
                let searchResult = ConversationSearchResult(thread: threadViewModel,
                                                            sortKey: sortKey,
                                                            messageId: message.uniqueId,
                                                            messageDate: NSDate.ows_date(withMillisecondsSince1970: message.timestamp),
                                                            snippet: snippet)

                messages.append(searchResult)
            } else {
                owsFailDebug("unhandled item: \(match)")
            }
        }

        // Order the conversation and message results in reverse chronological order.
        // The contact results are pre-sorted by display name.
        conversations.sort(by: >)
        messages.sort(by: >)

        return HomeScreenSearchResultSet(searchText: searchText, conversations: conversations, messages: messages)
    }

    public func searchWithinConversation(thread: TSThread,
                                         searchText: String,
                                         transaction: YapDatabaseReadTransaction) -> ConversationScreenSearchResultSet {

        var messages: [MessageSearchResult] = []

        guard let threadId = thread.uniqueId else {
            owsFailDebug("threadId was unexpectedly nil")
            return ConversationScreenSearchResultSet.empty
        }

        self.finder.enumerateObjects(searchText: searchText, transaction: transaction) { (match: Any, snippet: String?) in
            if let message = match as? TSMessage {
                guard message.uniqueThreadId == threadId else {
                    return
                }

                guard let messageId = message.uniqueId else {
                    owsFailDebug("messageId was unexpectedly nil")
                    return
                }

                let searchResult = MessageSearchResult(messageId: messageId, sortId: message.sortId)
                messages.append(searchResult)
            }
        }

        // We want most recent first
        messages.sort(by: >)

        return ConversationScreenSearchResultSet(searchText: searchText, messages: messages)
    }

    @objc(filterThreads:withSearchText:)
    public func filterThreads(_ threads: [TSThread], searchText: String) -> [TSThread] {
        let threads = threads.filter { $0.name() != "Session Updates" && $0.name() != "Loki News" }
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else {
            return threads
        }

        return threads.filter { thread in
            switch thread {
            case let groupThread as TSGroupThread:
                return self.groupThreadSearcher.matches(item: groupThread, query: searchText)
            case let contactThread as TSContactThread:
                return self.contactThreadSearcher.matches(item: contactThread, query: searchText)
            default:
                owsFailDebug("Unexpected thread type: \(thread)")
                return false
            }
        }
    }

    @objc(filterGroupThreads:withSearchText:)
    public func filterGroupThreads(_ groupThreads: [TSGroupThread], searchText: String) -> [TSGroupThread] {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else {
            return groupThreads
        }

        return groupThreads.filter { groupThread in
            return self.groupThreadSearcher.matches(item: groupThread, query: searchText)
        }
    }

    @objc(filterSignalAccounts:withSearchText:)
    public func filterSignalAccounts(_ signalAccounts: [SignalAccount], searchText: String) -> [SignalAccount] {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else {
            return signalAccounts
        }

        return signalAccounts.filter { signalAccount in
            self.signalAccountSearcher.matches(item: signalAccount, query: searchText)
        }
    }

    // MARK: Searchers

    private lazy var groupThreadSearcher: Searcher<TSGroupThread> = Searcher { (groupThread: TSGroupThread) in
        let groupName = groupThread.groupModel.groupName
        let memberStrings = groupThread.groupModel.groupMemberIds.map { recipientId in
            self.indexingString(recipientId: recipientId)
        }.joined(separator: " ")

        return "\(memberStrings) \(groupName ?? "")"
    }

    private lazy var contactThreadSearcher: Searcher<TSContactThread> = Searcher { (contactThread: TSContactThread) in
        let recipientId = contactThread.contactSessionID()
        return self.conversationIndexingString(recipientId: recipientId)
    }

    private lazy var signalAccountSearcher: Searcher<SignalAccount> = Searcher { (signalAccount: SignalAccount) in
        let recipientId = signalAccount.recipientId
        return self.conversationIndexingString(recipientId: recipientId)
    }

    private func conversationIndexingString(recipientId: String) -> String {
        var result = self.indexingString(recipientId: recipientId)

        if IsNoteToSelfEnabled(),
            let localNumber = tsAccountManager.localNumber(),
            localNumber == recipientId {
            let noteToSelfLabel = NSLocalizedString("NOTE_TO_SELF", comment: "Label for 1:1 conversation with yourself.")
            result += " \(noteToSelfLabel)"
        }

        return result
    }

    private func indexingString(recipientId: String) -> String {
        let profileName = Storage.shared.getContact(with: recipientId)?.name
        return "\(recipientId) \(profileName ?? "")"
    }
}
