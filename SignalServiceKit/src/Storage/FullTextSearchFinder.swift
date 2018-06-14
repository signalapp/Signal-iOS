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
        return FullTextSearchFinder.normalize(text: indexingText)
    }
}

@objc
public class FullTextSearchFinder: NSObject {

    // Mark: Querying

    // We want to match by prefix for "search as you type" functionality.
    // SQLite does not support suffix or contains matches.
    public class func query(searchText: String) -> String {
        // 1. Normalize the search text.
        let normalizedSearchText = FullTextSearchFinder.normalize(text: searchText)

        // 2. Split into query terms (or tokens).
        var queryTerms = normalizedSearchText.split(separator: " ")

        // 3. Add an additional numeric-only query term.
        let digitsOnlyScalars = normalizedSearchText.unicodeScalars.lazy.filter {
            CharacterSet.decimalDigits.contains($0)
        }
        let digitsOnly: Substring = Substring(String(String.UnicodeScalarView(digitsOnlyScalars)))
        queryTerms.append(digitsOnly)

        // 4. De-duplicate and sort query terms.
        queryTerms = Array(Set(queryTerms)).sorted()

        // 5. Filter the query terms.
        let filteredQueryTerms = queryTerms.filter {
            // Ignore empty terms.
            $0.count > 0
        }.map {
            // Allow partial match of each term.
            $0 + "*"
        }

        // 6. Join terms into query string.
        let query = filteredQueryTerms.joined(separator: " ")
        return query
    }

    public func enumerateObjects(searchText: String, transaction: YapDatabaseReadTransaction, block: @escaping (Any, String) -> Void) {
        guard let ext: YapDatabaseFullTextSearchTransaction = ext(transaction: transaction) else {
            owsFail("\(logTag) ext was unexpectedly nil")
            return
        }

        let query = FullTextSearchFinder.query(searchText: searchText)

        Logger.verbose("\(logTag) query: \(query)")

        let maxSearchResults = 500
        var searchResultCount = 0
        let snippetOptions = YapDatabaseFullTextSearchSnippetOptions()
        snippetOptions.startMatchText = ""
        snippetOptions.endMatchText = ""
        ext.enumerateKeysAndObjects(matching: query, with: snippetOptions) { (snippet: String, _: String, _: String, object: Any, stop: UnsafeMutablePointer<ObjCBool>) in
            guard searchResultCount < maxSearchResults else {
                stop.pointee = true
                return
            }
            searchResultCount = searchResultCount + 1

            block(object, snippet)
        }
    }

    // Mark: Normalization

    fileprivate class func charactersToRemove() -> CharacterSet {
        var charactersToFilter = CharacterSet.punctuationCharacters
        charactersToFilter.formUnion(CharacterSet.illegalCharacters)
        charactersToFilter.formUnion(CharacterSet.controlCharacters)
        // Note that we strip the Unicode "subtitute" character (26).
        charactersToFilter.formUnion(CharacterSet(charactersIn: "+~$^=|<>`_\u{26}"))
        return charactersToFilter
    }

    fileprivate class func separatorCharacters() -> CharacterSet {
        let separatorCharacters = CharacterSet.whitespacesAndNewlines
        return separatorCharacters
    }

    public class func normalize(text: String) -> String {
        // 1. Filter out invalid characters.
        let filtered = text.unicodeScalars.lazy.filter({
            !charactersToRemove().contains($0)
        })

        // 2. Simplify whitespace.
        let simplifyingFunction: (UnicodeScalar) -> UnicodeScalar = {
            if separatorCharacters().contains($0) {
                return UnicodeScalar(" ")
            } else {
                return $0
            }
        }
        let simplified = filtered.map(simplifyingFunction)

        // 3. Combine adjacent whitespace.
        var result = String(String.UnicodeScalarView(simplified))
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }

        // 4. Strip leading & trailing whitespace last, since we may replace
        // filtered characters with whitespace.
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
                owsFail("\(logTag) unexpected unparseable recipientId: \(recipientId)")
                return ""
            }

            guard let digitScalars = phoneNumber.nationalNumber?.unicodeScalars.filter({ CharacterSet.decimalDigits.contains($0) }) else {
                owsFail("\(logTag) unexpected unparseable recipientId: \(recipientId)")
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

        return YapDatabaseFullTextSearch(columnNames: ["content"],
                                         options: nil,
                                         handler: handler,
                                         ftsVersion: YapDatabaseFullTextSearchFTS5Version,
                                         versionTag: "1")
    }
}
