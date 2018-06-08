//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

public class SearchResult {
    public let thread: ThreadViewModel
    public let snippet: String?

    init(thread: ThreadViewModel, snippet: String?) {
        self.thread = thread
        self.snippet = snippet
    }
}

public class SearchResultSet {
    public let conversations: [SearchResult]
    public let contacts: [SearchResult]
    public let messages: [SearchResult]

    public init(conversations: [SearchResult], contacts: [SearchResult], messages: [SearchResult]) {
        self.conversations = conversations
        self.contacts = contacts
        self.messages = messages
    }

    public class var empty: SearchResultSet {
        return SearchResultSet(conversations: [], contacts: [], messages: [])
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

        // TODO limit results, prioritize conversations, then contacts, then messages.
        var conversations: [SearchResult] = []
        var contacts: [SearchResult] = []
        var messages: [SearchResult] = []

        self.finder.enumerateObjects(searchText: searchText, transaction: transaction) { (match: Any, snippet: String?) in
            if let thread = match as? TSThread {
                let threadViewModel = ThreadViewModel(thread: thread, transaction: transaction)
                let snippet: String? = thread.lastMessageText(transaction: transaction)
                let searchResult = SearchResult(thread: threadViewModel, snippet: snippet)

                conversations.append(searchResult)
            } else if let message = match as? TSMessage {
                let thread = message.thread(with: transaction)

                let threadViewModel = ThreadViewModel(thread: thread, transaction: transaction)
                let searchResult = SearchResult(thread: threadViewModel, snippet: snippet)

                messages.append(searchResult)
            } else {
                Logger.debug("\(self.logTag) in \(#function) unhandled item: \(match)")
            }
        }

        return SearchResultSet(conversations: conversations, contacts: contacts, messages: messages)
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

//public class ConversationFullTextSearchFinder {
//
//    public func enumerateObjects(searchText: String, transaction: YapDatabaseReadTransaction, block: @escaping (Any) -> Void) {
//        guard let ext = ext(transaction: transaction) else {
//            owsFail("ext was unexpectedly nil")
//            return
//        }
//
//        ext.enumerateKeysAndObjects(matching: searchText) { (_, _, object, _) in
//            block(object)
//        }
//    }
//
//    private func ext(transaction: YapDatabaseReadTransaction) -> YapDatabaseFullTextSearchTransaction? {
//        return transaction.ext(ConversationFullTextSearchFinder.dbExtensionName) as? YapDatabaseFullTextSearchTransaction
//    }
//
//    // MARK: - Extension Registration
//
//    static let dbExtensionName: String = "ConversationFullTextSearchFinderExtension1"
//
//    public class func asyncRegisterDatabaseExtension(storage: OWSStorage) {
//        storage.asyncRegister(dbExtensionConfig, withName: dbExtensionName)
//    }
//
//    // Only for testing.
//    public class func syncRegisterDatabaseExtension(storage: OWSStorage) {
//        storage.register(dbExtensionConfig, withName: dbExtensionName)
//    }
//
//    private class var dbExtensionConfig: YapDatabaseFullTextSearch {
//        let contentColumnName = "content"
//        let handler = YapDatabaseFullTextSearchHandler.withObjectBlock { (dict: NSMutableDictionary, _: String, _: String, object: Any) in
//            if let groupThread = object as? TSGroupThread {
//                dict[contentColumnName] = groupThread.groupModel.groupName
//            }
//        }
//
//        // update search index on contact name changes?
//        // update search index on message insertion?
//
//        // TODO is it worth doing faceted search, i.e. Author / Name / Content?
//        // seems unlikely that mobile users would use the "author: Alice" search syntax.
//        return YapDatabaseFullTextSearch(columnNames: ["content"], handler: handler)
//    }
//}
