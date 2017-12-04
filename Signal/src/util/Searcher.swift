//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

@objc
class ConversationSearcher: NSObject {

    @objc
    public static let shared: ConversationSearcher = ConversationSearcher()
    override private init() {
        super.init()
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
        return Environment.getCurrent().contactsManager
    }

    private func indexingString(recipientId: String) -> String {
        let contactName = contactsManager.displayName(forPhoneIdentifier: recipientId)
        let profileName = contactsManager.profileName(forRecipientId: recipientId)

        return "\(recipientId) \(contactName) \(profileName ?? "")"
    }
}

// ObjC compatible searcher
@objc class AnySearcher: NSObject {
    private let searcher: Searcher<AnyObject>

    public init(indexer: @escaping (AnyObject) -> String ) {
        searcher = Searcher(indexer: indexer)
        super.init()
    }

    @objc(item:doesMatchQuery:)
    public func matches(item: AnyObject, query: String) -> Bool {
        return searcher.matches(item: item, query: query)
    }
}

// A generic searching class, configurable with an indexing block
class Searcher<T> {

    private let indexer: (T) -> String

    public init(indexer: @escaping (T) -> String) {
        self.indexer = indexer
    }

    public func matches(item: T, query: String) -> Bool {
        let itemString = normalize(string: indexer(item))

        return stem(string: query).map { queryStem in
            return itemString.contains(queryStem)
        }.reduce(true) { $0 && $1 }
    }

    private func stem(string: String) -> [String] {
        var normalized = normalize(string: string)

        // Remove any phone number formatting from the search terms
        let nonformattingScalars = normalized.unicodeScalars.lazy.filter {
            !CharacterSet.punctuationCharacters.contains($0)
        }

        normalized = String(String.UnicodeScalarView(nonformattingScalars))

        return normalized.components(separatedBy: .whitespacesAndNewlines)
    }

    private func normalize(string: String) -> String {
        return string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
