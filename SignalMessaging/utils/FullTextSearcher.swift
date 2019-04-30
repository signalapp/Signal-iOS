//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

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

@objc
public class ContactSearchResult: NSObject, Comparable {
    public let signalAccount: SignalAccount
    public let contactsManager: ContactsManagerProtocol

    public var recipientId: String {
        return signalAccount.recipientId
    }

    init(signalAccount: SignalAccount, contactsManager: ContactsManagerProtocol) {
        self.signalAccount = signalAccount
        self.contactsManager = contactsManager
    }

    // MARK: Comparable

    public static func < (lhs: ContactSearchResult, rhs: ContactSearchResult) -> Bool {
        return lhs.contactsManager.compare(signalAccount: lhs.signalAccount, with: rhs.signalAccount) == .orderedAscending
    }

    // MARK: Equatable

    public static func == (lhs: ContactSearchResult, rhs: ContactSearchResult) -> Bool {
        return lhs.recipientId == rhs.recipientId
    }
}

public class HomeScreenSearchResultSet: NSObject {
    public let searchText: String
    public let conversations: [ConversationSearchResult<ConversationSortKey>]
    public let contacts: [ContactSearchResult]
    public let messages: [ConversationSearchResult<MessageSortKey>]

    public init(searchText: String, conversations: [ConversationSearchResult<ConversationSortKey>], contacts: [ContactSearchResult], messages: [ConversationSearchResult<MessageSortKey>]) {
        self.searchText = searchText
        self.conversations = conversations
        self.contacts = contacts
        self.messages = messages
    }

    public class var empty: HomeScreenSearchResultSet {
        return HomeScreenSearchResultSet(searchText: "", conversations: [], contacts: [], messages: [])
    }

    public var isEmpty: Bool {
        return conversations.isEmpty && contacts.isEmpty && messages.isEmpty
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

    @objc
    public let signalContacts: [ContactSearchResult]

    @objc
    public var signalAccounts: [SignalAccount] {
        return signalContacts.map { $0.signalAccount }
    }

    public init(searchText: String, groups: [GroupSearchResult], signalContacts: [ContactSearchResult]) {
        self.searchText = searchText
        self.groups = groups
        self.signalContacts = signalContacts
    }

    @objc
    public static let empty = ComposeScreenSearchResultSet(searchText: "", groups: [], signalContacts: [])

    @objc
    public var isEmpty: Bool {
        return groups.isEmpty && signalContacts.isEmpty
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
                                       transaction: YapDatabaseReadTransaction,
                                       contactsManager: ContactsManagerProtocol) -> ComposeScreenSearchResultSet {

        var signalContacts: [ContactSearchResult] = []
        var groups: [GroupSearchResult] = []

        self.finder.enumerateObjects(searchText: searchText, transaction: transaction) { (match: Any, _: String?) in

            switch match {
            case let signalAccount as SignalAccount:
                let searchResult = ContactSearchResult(signalAccount: signalAccount, contactsManager: contactsManager)
                signalContacts.append(searchResult)
            case let groupThread as TSGroupThread:
                let sortKey = ConversationSortKey(creationDate: groupThread.creationDate,
                                                  lastMessageReceivedAtDate: groupThread.lastInteractionForInbox(transaction: transaction.asAnyRead)?.receivedAtDate())
                let threadViewModel = ThreadViewModel(thread: groupThread, transaction: transaction.asAnyRead)
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

        // Order contact results by display name.
        signalContacts.sort()

        // Order the conversation and message results in reverse chronological order.
        // The contact results are pre-sorted by display name.
        groups.sort(by: >)

        return ComposeScreenSearchResultSet(searchText: searchText, groups: groups, signalContacts: signalContacts)
    }

    public func searchForHomeScreen(searchText: String,
                                    transaction: YapDatabaseReadTransaction,
                                    contactsManager: ContactsManagerProtocol) -> HomeScreenSearchResultSet {

        var conversations: [ConversationSearchResult<ConversationSortKey>] = []
        var contacts: [ContactSearchResult] = []
        var messages: [ConversationSearchResult<MessageSortKey>] = []

        var existingConversationRecipientIds: Set<String> = Set()

        self.finder.enumerateObjects(searchText: searchText, transaction: transaction) { (match: Any, snippet: String?) in

            if let thread = match as? TSThread {
                let threadViewModel = ThreadViewModel(thread: thread, transaction: transaction.asAnyRead)
                let sortKey = ConversationSortKey(creationDate: thread.creationDate,
                                                  lastMessageReceivedAtDate: thread.lastInteractionForInbox(transaction: transaction.asAnyRead)?.receivedAtDate())
                let searchResult = ConversationSearchResult(thread: threadViewModel, sortKey: sortKey)

                if let contactThread = thread as? TSContactThread {
                    let recipientId = contactThread.contactIdentifier()
                    existingConversationRecipientIds.insert(recipientId)
                }

                conversations.append(searchResult)
            } else if let message = match as? TSMessage {
                let thread = message.thread(with: transaction)

                let threadViewModel = ThreadViewModel(thread: thread, transaction: transaction.asAnyRead)
                let sortKey = message.sortId
                let searchResult = ConversationSearchResult(thread: threadViewModel,
                                                            sortKey: sortKey,
                                                            messageId: message.uniqueId,
                                                            messageDate: NSDate.ows_date(withMillisecondsSince1970: message.timestamp),
                                                            snippet: snippet)

                messages.append(searchResult)
            } else if let signalAccount = match as? SignalAccount {
                let searchResult = ContactSearchResult(signalAccount: signalAccount, contactsManager: contactsManager)
                contacts.append(searchResult)
            } else {
                owsFailDebug("unhandled item: \(match)")
            }
        }

        // Only show contacts which were not included in an existing 1:1 conversation.
        var otherContacts: [ContactSearchResult] = contacts.filter { !existingConversationRecipientIds.contains($0.recipientId) }

        // Order the conversation and message results in reverse chronological order.
        // The contact results are pre-sorted by display name.
        conversations.sort(by: >)
        messages.sort(by: >)
        // Order "other" contact results by display name.
        otherContacts.sort()

        return HomeScreenSearchResultSet(searchText: searchText, conversations: conversations, contacts: otherContacts, messages: messages)
    }

    public func searchWithinConversation(thread: TSThread,
                                         searchText: String,
                                         transaction: YapDatabaseReadTransaction) -> ConversationScreenSearchResultSet {

        var messages: [MessageSearchResult] = []

        guard let threadId = thread.uniqueId else {
            owsFailDebug("threadId was unexpectedly nil")
            return ConversationScreenSearchResultSet.empty
        }

        self.finder.enumerateObjects(searchText: searchText, transaction: transaction) { (match: Any, _: String?) in
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
        let recipientId = contactThread.contactIdentifier()
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

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    private func indexingString(recipientId: String) -> String {
        let contactName = contactsManager.displayName(forPhoneIdentifier: recipientId)
        let profileName = contactsManager.profileName(forRecipientId: recipientId)

        return "\(recipientId) \(contactName) \(profileName ?? "")"
    }
}
