//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

public class ConversationSearchResult {
    public let thread: ThreadViewModel
    public let snippet: String?

    init(thread: ThreadViewModel, snippet: String?) {
        self.thread = thread
        self.snippet = snippet
    }
}

public class ContactSearchResult {
    public let signalAccount: SignalAccount
    public var recipientId: String {
        return signalAccount.recipientId
    }

    init(signalAccount: SignalAccount) {
        self.signalAccount = signalAccount
    }
}

public class SearchResultSet {
    public let searchText: String
    public let conversations: [ConversationSearchResult]
    public let contacts: [ContactSearchResult]
    public let messages: [ConversationSearchResult]

    public init(searchText: String, conversations: [ConversationSearchResult], contacts: [ContactSearchResult], messages: [ConversationSearchResult]) {
        self.searchText = searchText
        self.conversations = conversations
        self.contacts = contacts
        self.messages = messages
    }

    public class var empty: SearchResultSet {
        return SearchResultSet(searchText: "", conversations: [], contacts: [], messages: [])
    }

    public var isEmpty: Bool {
        return conversations.isEmpty && contacts.isEmpty && messages.isEmpty
    }
}

@objc
public class ConversationSearcher: NSObject {

    private let finder: FullTextSearchFinder

    @objc
    public static let shared: ConversationSearcher = ConversationSearcher()
    override private init() {
        finder = FullTextSearchFinder()
        super.init()
    }

    public func results(searchText: String, transaction: YapDatabaseReadTransaction) -> SearchResultSet {
        var conversations: [ConversationSearchResult] = []
        var contacts: [ContactSearchResult] = []
        var messages: [ConversationSearchResult] = []

        var existingConversationRecipientIds: Set<String> = Set()

        self.finder.enumerateObjects(searchText: searchText, transaction: transaction) { (match: Any, snippet: String?) in
            if let thread = match as? TSThread {
                let threadViewModel = ThreadViewModel(thread: thread, transaction: transaction)
                let snippet: String? = thread.lastMessageText(transaction: transaction)
                let searchResult = ConversationSearchResult(thread: threadViewModel, snippet: snippet)

                if let contactThread = thread as? TSContactThread {
                    let recipientId = contactThread.contactIdentifier()
                    existingConversationRecipientIds.insert(recipientId)
                }
                conversations.append(searchResult)
            } else if let message = match as? TSMessage {
                let thread = message.thread(with: transaction)

                let threadViewModel = ThreadViewModel(thread: thread, transaction: transaction)
                let searchResult = ConversationSearchResult(thread: threadViewModel, snippet: snippet)

                messages.append(searchResult)
            } else if let signalAccount = match as? SignalAccount {
                let searchResult = ContactSearchResult(signalAccount: signalAccount)
                contacts.append(searchResult)
            } else {
                Logger.debug("\(self.logTag) in \(#function) unhandled item: \(match)")
            }
        }

        // Only show contacts which were not included in an existing 1:1 conversation.
        let otherContacts: [ContactSearchResult] = contacts.filter { !existingConversationRecipientIds.contains($0.recipientId) }

        return SearchResultSet(searchText: searchText, conversations: conversations, contacts: otherContacts, messages: messages)
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
                owsFail("Unexpected thread type: \(thread)")
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

    // MARK: - Helpers

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
        return self.indexingString(recipientId: recipientId)
    }

    private lazy var signalAccountSearcher: Searcher<SignalAccount> = Searcher { (signalAccount: SignalAccount) in
        let recipientId = signalAccount.recipientId
        return self.indexingString(recipientId: recipientId)
    }

    private var contactsManager: OWSContactsManager {
        return Environment.current().contactsManager
    }

    private func indexingString(recipientId: String) -> String {
        let contactName = contactsManager.displayName(forPhoneIdentifier: recipientId)
        let profileName = contactsManager.profileName(forRecipientId: recipientId)

        return "\(recipientId) \(contactName) \(profileName ?? "")"
    }
}
