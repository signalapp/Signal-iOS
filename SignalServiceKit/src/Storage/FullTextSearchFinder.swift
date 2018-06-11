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
        return indexBlock(item)
    }
}

@objc
public class FullTextSearchFinder: NSObject {

    public func enumerateObjects(searchText: String, transaction: YapDatabaseReadTransaction, block: @escaping (Any, String) -> Void) {
        guard let ext: YapDatabaseFullTextSearchTransaction = ext(transaction: transaction) else {
            assertionFailure("ext was unexpectedly nil")
            return
        }

        let normalized = FullTextSearchFinder.normalize(text: searchText)

        // We want a forgiving query for phone numbers
        // TODO a stricter "whole word" query for body text?
        let prefixQuery = "*\(normalized)*"

        // (snippet: String, collection: String, key: String, object: Any, stop: UnsafeMutablePointer<ObjCBool>)
        ext.enumerateKeysAndObjects(matching: prefixQuery, with: nil) { (snippet: String, _: String, _: String, object: Any, _: UnsafeMutablePointer<ObjCBool>) in
            block(object, snippet)
        }
    }

    private func ext(transaction: YapDatabaseReadTransaction) -> YapDatabaseFullTextSearchTransaction? {
        return transaction.ext(FullTextSearchFinder.dbExtensionName) as? YapDatabaseFullTextSearchTransaction
    }

    // Mark: Index Building

    private class var contactsManager: ContactsManagerProtocol {
        return TextSecureKitEnv.shared().contactsManager
    }

    private class func normalize(text: String) -> String {
        var normalized: String = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove any phone number formatting from the search terms
        let nonformattingScalars = normalized.unicodeScalars.lazy.filter {
            !CharacterSet.punctuationCharacters.contains($0)
        }

        normalized = String(String.UnicodeScalarView(nonformattingScalars))

        return normalized
    }

    private static let groupThreadIndexer: SearchIndexer<TSGroupThread> = SearchIndexer { (groupThread: TSGroupThread) in
        let groupName = groupThread.groupModel.groupName ?? ""

        let memberStrings = groupThread.groupModel.groupMemberIds.map { recipientId in
            recipientIndexer.index(recipientId)
        }.joined(separator: " ")

        let searchableContent = "\(groupName) \(memberStrings)"

        return normalize(text: searchableContent)
    }

    private static let contactThreadIndexer: SearchIndexer<TSContactThread> = SearchIndexer { (contactThread: TSContactThread) in
        let recipientId =  contactThread.contactIdentifier()
        let searchableContent = recipientIndexer.index(recipientId)

        return normalize(text: searchableContent)
    }

    private static let recipientIndexer: SearchIndexer<String> = SearchIndexer { (recipientId: String) in
        let displayName = contactsManager.displayName(forPhoneIdentifier: recipientId)
        let searchableContent =  "\(recipientId) \(displayName)"

        return normalize(text: searchableContent)
    }

    private static let messageIndexer: SearchIndexer<TSMessage> = SearchIndexer { (message: TSMessage) in
        let searchableContent =  message.body ?? ""

        return normalize(text: searchableContent)
    }

    private class func indexContent(object: Any) -> String? {
        if let groupThread = object as? TSGroupThread {
            return self.groupThreadIndexer.index(groupThread)
        } else if let contactThread = object as? TSContactThread {
            return self.contactThreadIndexer.index(contactThread)
        } else if let message = object as? TSMessage {
            return self.messageIndexer.index(message)
        } else {
            return nil
        }
    }

    // MARK: - Extension Registration

    // MJK - FIXME - while developing it's helpful to rebuild the index every launch. But we need to remove this before releasing.
    private static let dbExtensionName: String = "FullTextSearchFinderExtension\(Date())"

    @objc
    public class func asyncRegisterDatabaseExtension(storage: OWSStorage) {
        storage.asyncRegister(dbExtensionConfig, withName: dbExtensionName)
    }

    // Only for testing.
    public class func syncRegisterDatabaseExtension(storage: OWSStorage) {
        storage.register(dbExtensionConfig, withName: dbExtensionName)
    }

    private class var dbExtensionConfig: YapDatabaseFullTextSearch {
        // TODO is it worth doing faceted search, i.e. Author / Name / Content?
        // seems unlikely that mobile users would use the "author: Alice" search syntax.
        // so for now, everything searchable is jammed into a single column
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
