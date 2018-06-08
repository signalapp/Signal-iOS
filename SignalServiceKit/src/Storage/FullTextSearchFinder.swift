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

    public func enumerateObjects(searchText: String, transaction: YapDatabaseReadTransaction, block: @escaping (Any) -> Void) {
        guard let ext = ext(transaction: transaction) else {
            assertionFailure("ext was unexpectedly nil")
            return
        }

        let normalized = FullTextSearchFinder.normalize(text: searchText)

        // We want a forgiving query for phone numbers
        // TODO a stricter "whole word" query for body text?
        let prefixQuery = "*\(normalized)*"

        ext.enumerateKeysAndObjects(matching: prefixQuery) { (_, _, object, _) in
            block(object)
        }
    }

    private func ext(transaction: YapDatabaseReadTransaction) -> YapDatabaseFullTextSearchTransaction? {
        return transaction.ext(FullTextSearchFinder.dbExtensionName) as? YapDatabaseFullTextSearchTransaction
    }

    // Mark: Index Building

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
        let searchableContent = groupThread.groupModel.groupName ?? ""

        // TODO member names, member numbers

        return normalize(text: searchableContent)
    }

    private static let contactThreadIndexer: SearchIndexer<TSContactThread> = SearchIndexer { (contactThread: TSContactThread) in
        let searchableContent =  contactThread.contactIdentifier()

        // TODO contact name

        return normalize(text: searchableContent)
    }

    private static let contactIndexer: SearchIndexer<String> = SearchIndexer { (recipientId: String) in

        let searchableContent =  "\(recipientId)"

        // TODO contact name

        return normalize(text: searchableContent)
    }

    private class func indexContent(object: Any) -> String? {
        if let groupThread = object as? TSGroupThread {
            return self.groupThreadIndexer.index(groupThread)
        } else if let contactThread = object as? TSContactThread {
            return self.contactThreadIndexer.index(contactThread)
        } else {
            return nil
        }
    }

    // MARK: - Extension Registration

    // MJK - FIXME, remove dynamic name when done developing.
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
