//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher

@objc
public class FullTextSearchFinder: NSObject {
    public func enumerateObjects(searchText: String, transaction: SDSAnyReadTransaction, block: @escaping (Any, String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .yapRead(let yapRead):
            YDBFullTextSearchFinder().enumerateObjects(searchText: searchText, transaction: yapRead, block: block)
        case .grdbRead(let grdbRead):
            GRDBFullTextSearchFinder.enumerateObjects(searchText: searchText, transaction: grdbRead, block: block)
        }
    }

    public func modelWasInserted(model: SDSModel, transaction: SDSAnyWriteTransaction) {
        assert(type(of: model).shouldBeIndexedForFTS)

        switch transaction.writeTransaction {
        case .yapWrite:
            // Do nothing.
            break
        case .grdbWrite(let grdbWrite):
            GRDBFullTextSearchFinder.modelWasInserted(model: model, transaction: grdbWrite)
        }
    }

    public func modelWasUpdated(model: SDSModel, transaction: SDSAnyWriteTransaction) {
        assert(type(of: model).shouldBeIndexedForFTS)

        switch transaction.writeTransaction {
        case .yapWrite:
            // Do nothing.
            break
        case .grdbWrite(let grdbWrite):
            GRDBFullTextSearchFinder.modelWasUpdated(model: model, transaction: grdbWrite)
        }
    }

    public func modelWasRemoved(model: SDSModel, transaction: SDSAnyWriteTransaction) {
        assert(type(of: model).shouldBeIndexedForFTS)

        switch transaction.writeTransaction {
        case .yapWrite:
            // Do nothing.
            break
        case .grdbWrite(let grdbWrite):
            GRDBFullTextSearchFinder.modelWasRemoved(model: model, transaction: grdbWrite)
        }
    }

    public class func allModelsWereRemoved(collection: String, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .yapWrite:
            // Do nothing.
            break
        case .grdbWrite(let grdbWrite):
            GRDBFullTextSearchFinder.allModelsWereRemoved(collection: collection, transaction: grdbWrite)
        }
    }
}

// MARK: - Normalization

extension FullTextSearchFinder {

    fileprivate static var charactersToRemove: CharacterSet = {
        // * We want to strip punctuation - and our definition of "punctuation"
        //   is broader than `CharacterSet.punctuationCharacters`.
        // * FTS should be robust to (i.e. ignore) illegal and control characters,
        //   but it's safer if we filter them ourselves as well.
        var charactersToFilter = CharacterSet.punctuationCharacters
        charactersToFilter.formUnion(CharacterSet.illegalCharacters)
        charactersToFilter.formUnion(CharacterSet.controlCharacters)

        // We want to strip all ASCII characters except:
        // * Letters a-z, A-Z
        // * Numerals 0-9
        // * Whitespace
        var asciiToFilter = CharacterSet(charactersIn: UnicodeScalar(0x0)!..<UnicodeScalar(0x80)!)
        assert(!asciiToFilter.contains(UnicodeScalar(0x80)!))
        asciiToFilter.subtract(CharacterSet.alphanumerics)
        asciiToFilter.subtract(CharacterSet.whitespacesAndNewlines)
        charactersToFilter.formUnion(asciiToFilter)

        return charactersToFilter
    }()

    // This is a hot method, especially while running large migrations.
    // Changes to it should go through a profiler to make sure large migrations
    // aren't adversely affected.
    @objc
    public class func normalize(text: String) -> String {
        // 1. Filter out invalid characters.
        let filtered = text.removeCharacters(characterSet: charactersToRemove)

        // 2. Simplify whitespace.
        let simplified = filtered.replaceCharacters(characterSet: .whitespacesAndNewlines,
                                                    replacement: " ")

        // 3. Strip leading & trailing whitespace last, since we may replace
        // filtered characters with whitespace.
        let trimmed = simplified.trimmingCharacters(in: .whitespacesAndNewlines)

        // 4. Use canonical mapping.
        //
        // From the GRDB docs:
        //
        // Generally speaking, matches may fail when content and query don’t use
        // the same unicode normalization. SQLite actually exhibits inconsistent
        // behavior in this regard.
        //
        // For example, for aimé to match aimé, they better have the same
        // normalization: the NFC aim\u{00E9} form may not match its NFD aime\u{0301}
        // equivalent. Most strings that you get from Swift, UIKit and Cocoa use NFC,
        // so be careful with NFD inputs (such as strings from the HFS+ file system,
        // or strings that you can’t trust like network inputs). Use
        // String.precomposedStringWithCanonicalMapping to turn a string into NFC.
        //
        // Besides, if you want fi to match the ligature ﬁ (U+FB01), then you need
        // to normalize your indexed contents and inputs to NFKC or NFKD. Use
        // String.precomposedStringWithCompatibilityMapping to turn a string into NFKC.
        let canonical = trimmed.precomposedStringWithCanonicalMapping

        return canonical
    }
}

// MARK: - Querying

// We use SQLite's FTS5 for both YDB and GRDB, we can use the
// same query for both cases.
extension FullTextSearchFinder {

    // We want to match by prefix for "search as you type" functionality.
    // SQLite does not support suffix or contains matches.
    public class func query(searchText: String) -> String {
        // 1. Normalize the search text.
        //
        // TODO: We could arguably convert to lowercase since the search
        // is case-insensitive.
        let normalizedSearchText = FullTextSearchFinder.normalize(text: searchText)

        // 2. Split the non-numeric text into query terms (or tokens).
        let nonNumericText = String(String.UnicodeScalarView(normalizedSearchText.unicodeScalars.lazy.map {
            if CharacterSet.decimalDigits.contains($0) {
                return " "
            } else {
                return $0
            }
        }))
        var queryTerms = nonNumericText.split(separator: " ")

        // 3. Add an additional numeric-only query term.
        let digitsOnlyScalars = normalizedSearchText.unicodeScalars.lazy.filter {
            CharacterSet.decimalDigits.contains($0)
        }
        let digitsOnly: Substring = Substring(String(String.UnicodeScalarView(digitsOnlyScalars)))
        queryTerms.append(digitsOnly)

        // 4. De-duplicate and sort query terms.
        //    Duplicate terms are redundant.
        //    Sorting terms makes the output of this method deterministic and easier to test,
        //        and the order won't affect the search results.
        queryTerms = Array(Set(queryTerms)).sorted()

        // 5. Filter the query terms.
        let filteredQueryTerms = queryTerms.filter {
            // Ignore empty terms.
            $0.count > 0
            }.map {
                // Allow partial match of each term.
                //
                // Note that we use double-quotes to enclose each search term.
                // Quoted search terms can include a few more characters than
                // "bareword" (non-quoted) search terms.  This shouldn't matter,
                // since we're filtering all of the affected characters, but
                // quoting protects us from any bugs in that logic.
                "\"\($0)\"*"
        }

        // 6. Join terms into query string.
        let query = filteredQueryTerms.joined(separator: " ")
        return query
    }
}

// MARK: -

@objc
public class YDBFullTextSearchFinder: NSObject {

    public func enumerateObjects(searchText: String, transaction: YapDatabaseReadTransaction, block: @escaping (Any, String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        guard let ext: YapDatabaseFullTextSearchTransaction = ext(transaction: transaction) else {
            owsFailDebug("ext was unexpectedly nil")
            return
        }

        let query = FullTextSearchFinder.query(searchText: searchText)

        guard query.count > 0 else {
            owsFailDebug("Empty query.")
            return
        }

        Logger.verbose("query: \(query)")

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
            searchResultCount += 1

            block(object, snippet, stop)
        }
    }

    // MARK: - Extension Registration

    private static let dbExtensionName: String = "FullTextSearchFinderExtension"

    private func ext(transaction: YapDatabaseReadTransaction) -> YapDatabaseFullTextSearchTransaction? {
        return transaction.safeFullTextSearchTransaction(YDBFullTextSearchFinder.dbExtensionName)
    }

    @objc
    public class func asyncRegisterDatabaseExtension(storage: OWSStorage) {
        storage.asyncRegister(dbExtensionConfig, withName: dbExtensionName)
    }

    // Only for testing.
    public class func ensureDatabaseExtensionRegistered(storage: OWSStorage) {
        guard storage.registeredExtension(dbExtensionName) == nil else {
            return
        }

        storage.register(dbExtensionConfig, withName: dbExtensionName)
    }

    private class var dbExtensionConfig: YapDatabaseFullTextSearch {
        AssertIsOnMainThread()

        let contentColumnName = "content"

        let handler = YapDatabaseFullTextSearchHandler.withObjectBlock { (transaction: YapDatabaseReadTransaction, dict: NSMutableDictionary, _: String, _: String, object: Any) in
            dict[contentColumnName] = AnySearchIndexer.indexContent(object: object, transaction: transaction.asAnyRead)
        }

        // update search index on contact name changes?

        return YapDatabaseFullTextSearch(columnNames: ["content"],
                                         options: nil,
                                         handler: handler,
                                         ftsVersion: YapDatabaseFullTextSearchFTS5Version,
                                         versionTag: "1")
    }
}

// MARK: -

// See: http://groue.github.io/GRDB.swift/docs/4.1/index.html#full-text-search
// See: https://www.sqlite.org/fts5.html
@objc
class GRDBFullTextSearchFinder: NSObject {

    static let databaseTableName: String = "signal_grdb_fts"
    static let uniqueIdColumn: String = "uniqueId"
    static let collectionColumn: String = "collection"
    static let ftsContentColumn: String = "ftsContent"

    class func createTables(database: Database) throws {
        try database.create(virtualTable: databaseTableName, using: FTS5()) { table in
            // We could use FTS5TokenizerDescriptor.porter(wrapping: FTS5TokenizerDescriptor.unicode61())
            //
            // Porter does stemming (e.g. "hunting" will match "hunter").
            // unicode61 will remove diacritics (e.g. "senor" will match "señor").
            //
            // GRDB TODO: Should we do stemming?
            let tokenizer = FTS5TokenizerDescriptor.unicode61()
            table.tokenizer = tokenizer

            table.column("\(collectionColumn)").notIndexed()
            table.column("\(uniqueIdColumn)").notIndexed()
            table.column("\(ftsContentColumn)")
        }
    }

    private class func collection(forModel model: SDSModel) -> String {
        // Note that allModelsWereRemoved(collection: ) makes the same
        // assumption that the FTS collection matches the
        // TSYapDatabaseObject.collection.
        return type(of: model).collection()
    }

    public class func modelWasInserted(model: SDSModel, transaction: GRDBWriteTransaction) {
        let uniqueId = model.uniqueId
        let collection = self.collection(forModel: model)
        let ftsContent = AnySearchIndexer.indexContent(object: model, transaction: transaction.asAnyRead) ?? ""

        executeUpdate(
            sql: """
            INSERT INTO \(databaseTableName)
            (\(collectionColumn), \(uniqueIdColumn), \(ftsContentColumn))
            VALUES
            (?, ?, ?)
            """,
            arguments: [collection, uniqueId, ftsContent],
            transaction: transaction)
    }

    public class func modelWasUpdated(model: SDSModel, transaction: GRDBWriteTransaction) {
        let uniqueId = model.uniqueId
        let collection = self.collection(forModel: model)
        let ftsContent = AnySearchIndexer.indexContent(object: model, transaction: transaction.asAnyRead) ?? ""

        executeUpdate(
            sql: """
            UPDATE \(databaseTableName)
            SET \(ftsContentColumn) = ?
            WHERE \(collectionColumn) == ?
            AND \(uniqueIdColumn) == ?
            """,
            arguments: [ftsContent, collection, uniqueId],
            transaction: transaction)
    }

    public class func modelWasRemoved(model: SDSModel, transaction: GRDBWriteTransaction) {
        let uniqueId = model.uniqueId
        let collection = self.collection(forModel: model)

        executeUpdate(
            sql: """
            DELETE FROM \(databaseTableName)
            WHERE \(uniqueIdColumn) == ?
            AND \(collectionColumn) == ?
            """,
            arguments: [uniqueId, collection],
            transaction: transaction)
    }

    public class func allModelsWereRemoved(collection: String, transaction: GRDBWriteTransaction) {
        //            try transaction.database.execute(
        executeUpdate(
            sql: """
            DELETE FROM \(databaseTableName)
            WHERE \(collectionColumn) == ?
            """,
            arguments: [collection],
            transaction: transaction)
    }

    private static let disableFTS = true

    private class func executeUpdate(sql: String,
                                     arguments: StatementArguments,
                                     transaction: GRDBWriteTransaction) {
        guard !disableFTS else {
            return
        }

        transaction.executeWithCachedStatement(sql: sql,
                                               arguments: arguments)
    }

    private class func modelForFTSMatch(collection: String,
                                        uniqueId: String,
                                        transaction: GRDBReadTransaction) -> SDSModel? {
        switch collection {
        case SignalAccount.collection():
            guard let model = SignalAccount.anyFetch(uniqueId: uniqueId,
                                                     transaction: transaction.asAnyRead) else {
                                                        owsFailDebug("Couldn't load record: \(collection)")
                                                        return nil
            }
            return model
        case TSThread.collection():
            guard let model = TSThread.anyFetch(uniqueId: uniqueId,
                                                transaction: transaction.asAnyRead) else {
                                                    owsFailDebug("Couldn't load record: \(collection)")
                                                    return nil
            }
            return model
        case TSInteraction.collection():
            guard let model = TSInteraction.anyFetch(uniqueId: uniqueId,
                                                     transaction: transaction.asAnyRead) else {
                                                        owsFailDebug("Couldn't load record: \(collection)")
                                                        return nil
            }
            return model
        default:
            owsFailDebug("Unexpected record type: \(collection)")
            return nil
        }
    }

    // MARK: - Querying

    public class func enumerateObjects(searchText: String, transaction: GRDBReadTransaction, block: @escaping (Any, String, UnsafeMutablePointer<ObjCBool>) -> Void) {

        let query = FullTextSearchFinder.query(searchText: searchText)

        guard query.count > 0 else {
            owsFailDebug("Empty query.")
            return
        }

        // Search with the query interface or SQL
        do {
            var stop: ObjCBool = false

            // GRDB TODO: We could use bm25() instead of rank to order results.
            let columnIndex = 2
            // Determines the length of the snippet.
            let numTokens: UInt = 15
            let matchSnippet = "match_snippet"
            let sql: String = """
                SELECT
                \(collectionColumn), \(uniqueIdColumn), \(ftsContentColumn),
                snippet(\(databaseTableName), \(columnIndex), '', '', '…', \(numTokens) ) as \(matchSnippet)
                FROM \(databaseTableName)
                WHERE \(databaseTableName)
                MATCH '"\(ftsContentColumn)" : \(query)'
                ORDER BY rank
            """
            let cursor = try Row.fetchCursor(transaction.database, sql: sql)
            while let row = try cursor.next() {
                let collection: String = row[collectionColumn]
                let uniqueId: String = row[uniqueIdColumn]
                let snippet: String = row[matchSnippet]
                guard collection.count > 0,
                    uniqueId.count > 0 else {
                        owsFailDebug("Invalid match: collection: \(collection), uniqueId: \(uniqueId).")
                        continue
                }
                guard let model = modelForFTSMatch(collection: collection,
                                                   uniqueId: uniqueId,
                                                   transaction: transaction) else {
                                                    owsFailDebug("Missing model for search result.")
                                                    continue
                }

                block(model, snippet, &stop)
                guard !stop.boolValue else {
                    break
                }
            }
        } catch {
            owsFailDebug("Couldn't fetch results: \(error)")
        }
    }

}

// MARK: -

// Create a searchable index for objects of type T
class SearchIndexer<T> {

    private let indexBlock: (T, SDSAnyReadTransaction) -> String

    public init(indexBlock: @escaping (T, SDSAnyReadTransaction) -> String) {
        self.indexBlock = indexBlock
    }

    public func index(_ item: T, transaction: SDSAnyReadTransaction) -> String {
        return normalize(indexingText: indexBlock(item, transaction))
    }

    private func normalize(indexingText: String) -> String {
        return FullTextSearchFinder.normalize(text: indexingText)
    }
}

// MARK: -

class AnySearchIndexer {

    // MARK: - Dependencies

    private static var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private class var contactsManager: ContactsManagerProtocol {
        return SSKEnvironment.shared.contactsManager
    }

    // MARK: - Index Building

    private static let groupThreadIndexer: SearchIndexer<TSGroupThread> = SearchIndexer { (groupThread: TSGroupThread, transaction: SDSAnyReadTransaction) in
        let groupName = groupThread.groupModel.groupName ?? ""

        let memberStrings = groupThread.groupModel.groupMembers.map { address in
            recipientIndexer.index(address, transaction: transaction)
            }.joined(separator: " ")

        return "\(groupName) \(memberStrings)"
    }

    private static let contactThreadIndexer: SearchIndexer<TSContactThread> = SearchIndexer { (contactThread: TSContactThread, transaction: SDSAnyReadTransaction) in
        let recipientAddress = contactThread.contactAddress
        var result = recipientIndexer.index(recipientAddress, transaction: transaction)

        if contactThread.isNoteToSelf {
            let noteToSelfLabel = NSLocalizedString("NOTE_TO_SELF", comment: "Label for 1:1 conversation with yourself.")
            result += " \(noteToSelfLabel)"
        }

        return result
    }

    private static let recipientIndexer: SearchIndexer<SignalServiceAddress> = SearchIndexer { recipientAddress, transaction in
        let displayName = contactsManager.displayName(for: recipientAddress, transaction: transaction)

        let nationalNumber: String? = { (recipientId: String?) -> String? in
            guard let recipientId = recipientId else { return nil }

            guard let phoneNumber = PhoneNumber(fromE164: recipientId) else {
                owsFailDebug("unexpected unparseable recipientId: \(recipientId)")
                return ""
            }

            guard let digitScalars = phoneNumber.nationalNumber?.unicodeScalars.filter({ CharacterSet.decimalDigits.contains($0) }) else {
                owsFailDebug("unexpected unparseable recipientId: \(recipientId)")
                return ""
            }

            return String(String.UnicodeScalarView(digitScalars))
        }(recipientAddress.phoneNumber)

        return "\(recipientAddress.phoneNumber ?? "") \(nationalNumber ?? "") \(displayName)"
    }

    private static let messageIndexer: SearchIndexer<TSMessage> = SearchIndexer { (message: TSMessage, transaction: SDSAnyReadTransaction) in
        if let bodyText = message.bodyText(with: transaction) {
            return bodyText
        }
        return ""
    }

    class func indexContent(object: Any, transaction: SDSAnyReadTransaction) -> String? {
        if let groupThread = object as? TSGroupThread {
            return self.groupThreadIndexer.index(groupThread, transaction: transaction)
        } else if let contactThread = object as? TSContactThread {
            guard contactThread.shouldThreadBeVisible else {
                // If we've never sent/received a message in a TSContactThread,
                // then we want it to appear in the "Other Contacts" section rather
                // than in the "Conversations" section.
                return nil
            }
            return self.contactThreadIndexer.index(contactThread, transaction: transaction)
        } else if let message = object as? TSMessage {
            guard !message.isViewOnceMessage else {
                // Don't index "view-once messages".
                return nil
            }
            return self.messageIndexer.index(message, transaction: transaction)
        } else if let signalAccount = object as? SignalAccount {
            return self.recipientIndexer.index(signalAccount.recipientAddress, transaction: transaction)
        } else {
            return nil
        }
    }
}
