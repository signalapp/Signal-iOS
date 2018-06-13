//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// Create a searchable index for objects of type T
public class SearchIndexer<T> {

    private let indexBlock: (T) -> String

    public init(indexBlock: @escaping (T) -> String) {
        self.indexBlock = indexBlock
    }

    public func index(_ item: T) -> String {
        return normalize(indexingText: indexBlock(item))
    }

    private func normalize(indexingText: String) -> String {
        var normalized: String = indexingText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove any punctuation from the search index
        let nonformattingScalars = normalized.unicodeScalars.lazy.filter {
            !CharacterSet.punctuationCharacters.contains($0)
        }

        normalized = String(String.UnicodeScalarView(nonformattingScalars))

        return normalized
    }
}

@objc
public class FullTextSearchFinder: NSObject {

    // Mark: Querying

    public func enumerateObjects(searchText: String, transaction: YapDatabaseReadTransaction, block: @escaping (Any, String) -> Void) {
        guard let ext: YapDatabaseFullTextSearchTransaction = ext(transaction: transaction) else {
            assertionFailure("ext was unexpectedly nil")
            return
        }

        let normalized = normalize(queryText: searchText)

        // We want to match by prefix for "search as you type" functionality.
        // SQLite does not support suffix or contains matches.
        let prefixQuery = "\(normalized)*"

        let maxSearchResults = 500
        var searchResultCount = 0
        let snippetOptions = YapDatabaseFullTextSearchSnippetOptions()
        snippetOptions.startMatchText = ""
        snippetOptions.endMatchText = ""
        ext.enumerateKeysAndObjects(matching: prefixQuery, with: snippetOptions) { (snippet: String, _: String, _: String, object: Any, stop: UnsafeMutablePointer<ObjCBool>) in
            guard searchResultCount < maxSearchResults else {
                stop.pointee = true
                return
            }
            searchResultCount = searchResultCount + 1

            block(object, snippet)
        }
    }

    private func normalize(queryText: String) -> String {
        var normalized: String = queryText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove any punctuation from the search terms
        let nonformattingScalars = normalized.unicodeScalars.lazy.filter {
            !CharacterSet.punctuationCharacters.contains($0)
        }
        let normalizedChars = String(String.UnicodeScalarView(nonformattingScalars))

        let digitsOnlyScalars = normalized.unicodeScalars.lazy.filter {
            CharacterSet.decimalDigits.contains($0)
        }
        let normalizedDigits = String(String.UnicodeScalarView(digitsOnlyScalars))

        if normalizedDigits.count > 0 {
            return "\(normalizedChars) OR \(normalizedDigits)"
        } else {
            return "\(normalizedChars)"
        }
    }

    // Mark: Index Building

    private class var contactsManager: ContactsManagerProtocol {
        return TextSecureKitEnv.shared().contactsManager
    }

    private static let groupThreadIndexer: SearchIndexer<TSGroupThread> = SearchIndexer { (groupThread: TSGroupThread) in
        let groupName = groupThread.groupModel.groupName ?? ""

        let memberStrings = groupThread.groupModel.groupMemberIds.map { recipientId in
            recipientIndexer.index(recipientId)
        }.joined(separator: " ")

        return "\(groupName) \(memberStrings)"
    }

    private static let contactThreadIndexer: SearchIndexer<TSContactThread> = SearchIndexer { (contactThread: TSContactThread) in
        let recipientId =  contactThread.contactIdentifier()
        return recipientIndexer.index(recipientId)
    }

    private static let recipientIndexer: SearchIndexer<String> = SearchIndexer { (recipientId: String) in
        let displayName = contactsManager.displayName(forPhoneIdentifier: recipientId)

        let nationalNumber: String = { (recipientId: String) -> String in

            guard let phoneNumber = PhoneNumber(fromE164: recipientId) else {
                assertionFailure("unexpected unparseable recipientId: \(recipientId)")
                return ""
            }

            guard let digitScalars = phoneNumber.nationalNumber?.unicodeScalars.filter({ CharacterSet.decimalDigits.contains($0) }) else {
                assertionFailure("unexpected unparseable recipientId: \(recipientId)")
                return ""
            }

            return String(String.UnicodeScalarView(digitScalars))
        }(recipientId)

        return "\(recipientId) \(nationalNumber) \(displayName)"
    }

    private static let messageIndexer: SearchIndexer<TSMessage> = SearchIndexer { (message: TSMessage) in
        return message.body ?? ""
    }

    private class func indexContent(object: Any) -> String? {
        if let groupThread = object as? TSGroupThread {
            return self.groupThreadIndexer.index(groupThread)
        } else if let contactThread = object as? TSContactThread {
            guard contactThread.hasEverHadMessage else {
                // If we've never sent/received a message in a TSContactThread,
                // then we want it to appear in the "Other Contacts" section rather
                // than in the "Conversations" section.
                return nil
            }
            return self.contactThreadIndexer.index(contactThread)
        } else if let message = object as? TSMessage {
            return self.messageIndexer.index(message)
        } else if let signalAccount = object as? SignalAccount {
            return self.recipientIndexer.index(signalAccount.recipientId)
        } else {
            return nil
        }
    }

    // MARK: - Extension Registration

    private static let dbExtensionName: String = "FullTextSearchFinderExtension)"

    private func ext(transaction: YapDatabaseReadTransaction) -> YapDatabaseFullTextSearchTransaction? {
        return transaction.ext(FullTextSearchFinder.dbExtensionName) as? YapDatabaseFullTextSearchTransaction
    }

    @objc
    public class func asyncRegisterDatabaseExtension(storage: OWSStorage) {
        storage.asyncRegister(dbExtensionConfig, withName: dbExtensionName)
    }

    // Only for testing.
    public class func syncRegisterDatabaseExtension(storage: OWSStorage) {
        storage.register(dbExtensionConfig, withName: dbExtensionName)
    }

    private class var dbExtensionConfig: YapDatabaseFullTextSearch {
        let contentColumnName = "content"

        let handler = YapDatabaseFullTextSearchHandler.withObjectBlock { (dict: NSMutableDictionary, _: String, _: String, object: Any) in
            if let content: String = indexContent(object: object) {
                dict[contentColumnName] = content
            }
        }

        // update search index on contact name changes?
        // update search index on message insertion?

        return YapDatabaseFullTextSearch(columnNames: ["content"], handler: handler)
    }
}
