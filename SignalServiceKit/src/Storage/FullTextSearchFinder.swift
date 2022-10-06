//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

@objc
public class FullTextSearchFinder: NSObject {
    public static let matchTag = "match"

    public func enumerateObjects(searchText: String, collections: [String], maxResults: UInt, transaction: SDSAnyReadTransaction, block: @escaping (Any, String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            GRDBFullTextSearchFinder.enumerateObjects(searchText: searchText, collections: collections, maxResults: maxResults, transaction: grdbRead, block: block)
        }
    }

    public func enumerateObjects<T: SDSIndexableModel>(searchText: String, maxResults: UInt, transaction: SDSAnyReadTransaction, block: @escaping (T, String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            GRDBFullTextSearchFinder.enumerateObjects(searchText: searchText, maxResults: maxResults, transaction: grdbRead, block: block)
        }
    }

    public func modelWasInserted(model: SDSIndexableModel, transaction: SDSAnyWriteTransaction) {
        assert(type(of: model).ftsIndexMode != .never)

        switch transaction.writeTransaction {
        case .grdbWrite(let grdbWrite):
            GRDBFullTextSearchFinder.modelWasInserted(model: model, transaction: grdbWrite)
        }
    }

    @objc
    public func modelWasUpdatedObjc(model: AnyObject, transaction: SDSAnyWriteTransaction) {
        guard let model = model as? SDSIndexableModel else {
            owsFailDebug("Invalid model.")
            return
        }
        modelWasUpdated(model: model, transaction: transaction)
    }

    public func modelWasUpdated(model: SDSIndexableModel, transaction: SDSAnyWriteTransaction) {
        assert(type(of: model).ftsIndexMode != .never)

        switch transaction.writeTransaction {
        case .grdbWrite(let grdbWrite):
            GRDBFullTextSearchFinder.modelWasUpdated(model: model, transaction: grdbWrite)
        }
    }

    public func modelWasInsertedOrUpdated(model: SDSIndexableModel, transaction: SDSAnyWriteTransaction) {
        assert(type(of: model).ftsIndexMode != .never)

        switch transaction.writeTransaction {
        case .grdbWrite(let grdbWrite):
            GRDBFullTextSearchFinder.modelWasInsertedOrUpdated(model: model, transaction: grdbWrite)
        }
    }

    public func modelWasRemoved(model: SDSIndexableModel, transaction: SDSAnyWriteTransaction) {
        assert(type(of: model).ftsIndexMode != .never)

        switch transaction.writeTransaction {
        case .grdbWrite(let grdbWrite):
            GRDBFullTextSearchFinder.modelWasRemoved(model: model, transaction: grdbWrite)
        }
    }

    public class func allModelsWereRemoved(collection: String, transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
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

// We use SQLite's FTS5 for GRDB.
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

// See: http://groue.github.io/GRDB.swift/docs/4.1/index.html#full-text-search
// See: https://www.sqlite.org/fts5.html
@objc
class GRDBFullTextSearchFinder: NSObject {

    static let contentTableName = "indexable_text"
    static let ftsTableName = "indexable_text_fts"
    static let uniqueIdColumn = "uniqueId"
    static let collectionColumn = "collection"
    static let ftsContentColumn = "ftsIndexableContent"
    static var matchTag: String { FullTextSearchFinder.matchTag }

    public static let indexableModelTypes: [SDSIndexableModel.Type] = [
        TSThread.self,
        TSInteraction.self,
        TSGroupMember.self,
        SignalAccount.self,
        SignalRecipient.self
    ]

    private class func collection(forModel model: SDSIndexableModel) -> String {
        // Note that allModelsWereRemoved(collection: ) makes the same
        // assumption that the FTS collection matches the
        // TSYapDatabaseObject.collection.
        return type(of: model).collection()
    }

    private static let serialQueue = DispatchQueue(label: "org.signal.fts")
    // This should only be accessed on serialQueue.
    private static let ftsCache = LRUCache<String, String>(maxSize: 128, nseMaxSize: 16)

    private class func cacheKey(collection: String, uniqueId: String) -> String {
        return "\(collection).\(uniqueId)"
    }

    #if TESTABLE_BUILD
    private class func `is`(_ value: Any, ofType type: Any.Type) -> Bool {
        var currentMirror: Mirror? = Mirror(reflecting: value)
        while let mirror = currentMirror {
            if mirror.subjectType == type { return true }
            currentMirror = mirror.superclassMirror
        }
        return false
    }
    #endif

    fileprivate class func shouldIndexModel(_ model: SDSIndexableModel) -> Bool {
        #if TESTABLE_BUILD
        let isIndexable = indexableModelTypes.contains { Self.is(model, ofType: $0) }
        owsAssert(isIndexable)
        #endif

        if let userProfile = model as? OWSUserProfile,
           OWSUserProfile.isLocalProfileAddress(userProfile.address) {
            // We don't need to index the user profile for the local user.
            return false
        }
        if let signalAccount = model as? SignalAccount,
           OWSUserProfile.isLocalProfileAddress(signalAccount.recipientAddress) {
            // We don't need to index the signal account for the local user.
            return false
        }
        if let signalRecipient = model as? SignalRecipient,
           OWSUserProfile.isLocalProfileAddress(signalRecipient.address) {
            // We don't need to index the signal recipient for the local user.
            return false
        }
        if let contactThread = model as? TSContactThread,
           contactThread.contactPhoneNumber == kLocalProfileInvariantPhoneNumber {
            // We don't need to index the contact thread for the "local invariant phone number".
            // We do want to index the contact thread for the local user; that will have a
            // different address.
            return false
        }
        return true
    }

    public class func modelWasInserted(model: SDSIndexableModel, transaction: GRDBWriteTransaction) {
        guard shouldIndexModel(model) else {
            Logger.verbose("Not indexing model: \(type(of: (model)))")
            removeModelFromIndex(model, transaction: transaction)
            return
        }
        let uniqueId = model.uniqueId
        let collection = self.collection(forModel: model)
        let ftsContent = AnySearchIndexer.indexContent(object: model, transaction: transaction.asAnyRead) ?? ""

        serialQueue.sync {
            let cacheKey = self.cacheKey(collection: collection, uniqueId: uniqueId)
            ftsCache.setObject(ftsContent, forKey: cacheKey)
        }

        executeUpdate(
            sql: """
            INSERT INTO \(contentTableName)
            (\(collectionColumn), \(uniqueIdColumn), \(ftsContentColumn))
            VALUES
            (?, ?, ?)
            """,
            arguments: [collection, uniqueId, ftsContent],
            transaction: transaction)
    }

    public class func modelWasUpdated(model: SDSIndexableModel, transaction: GRDBWriteTransaction) {
        guard shouldIndexModel(model) else {
            Logger.verbose("Not indexing model: \(type(of: (model)))")
            removeModelFromIndex(model, transaction: transaction)
            return
        }
        let uniqueId = model.uniqueId
        let collection = self.collection(forModel: model)
        let ftsContent = AnySearchIndexer.indexContent(object: model, transaction: transaction.asAnyRead) ?? ""

        let shouldSkipUpdate: Bool = serialQueue.sync {
            guard !CurrentAppContext().isRunningTests else {
                return false
            }
            let cacheKey = self.cacheKey(collection: collection, uniqueId: uniqueId)
            if let cachedValue = ftsCache.object(forKey: cacheKey),
                (cachedValue as String) == ftsContent {
                return true
            }
            ftsCache.setObject(ftsContent, forKey: cacheKey)
            return false
        }
        guard !shouldSkipUpdate else {
            if !DebugFlags.reduceLogChatter {
                Logger.verbose("Skipping FTS update")
            }
            return
        }

        executeUpdate(
            sql: """
            UPDATE \(contentTableName)
            SET \(ftsContentColumn) = ?
            WHERE \(collectionColumn) == ?
            AND \(uniqueIdColumn) == ?
            """,
            arguments: [ftsContent, collection, uniqueId],
            transaction: transaction)
    }

    public class func modelWasInsertedOrUpdated(model: SDSIndexableModel, transaction: GRDBWriteTransaction) {
        guard shouldIndexModel(model) else {
            Logger.verbose("Not indexing model: \(type(of: (model)))")
            removeModelFromIndex(model, transaction: transaction)
            return
        }
        let uniqueId = model.uniqueId
        let collection = self.collection(forModel: model)
        let ftsContent = AnySearchIndexer.indexContent(object: model, transaction: transaction.asAnyRead) ?? ""

        let shouldSkipUpdate: Bool = serialQueue.sync {
            guard !CurrentAppContext().isRunningTests else {
                return false
            }
            let cacheKey = self.cacheKey(collection: collection, uniqueId: uniqueId)
            if let cachedValue = ftsCache.object(forKey: cacheKey),
                (cachedValue as String) == ftsContent {
                return true
            }
            ftsCache.setObject(ftsContent, forKey: cacheKey)
            return false
        }
        guard !shouldSkipUpdate else {
            if !DebugFlags.reduceLogChatter {
                Logger.verbose("Skipping FTS update")
            }
            return
        }

        executeUpdate(
            // See: https://www.sqlite.org/lang_UPSERT.html
            sql: """
                INSERT INTO \(contentTableName) (
                    \(collectionColumn),
                    \(uniqueIdColumn),
                    \(ftsContentColumn)
                ) VALUES (?, ?, ?)
                ON CONFLICT (
                    \(collectionColumn),
                    \(uniqueIdColumn)
                ) DO UPDATE
                SET \(ftsContentColumn) = ?
            """,
            arguments: [collection, uniqueId, ftsContent, ftsContent],
            transaction: transaction)
    }

    public class func modelWasRemoved(model: SDSIndexableModel, transaction: GRDBWriteTransaction) {
        removeModelFromIndex(model, transaction: transaction)
    }

    private class func removeModelFromIndex(_ model: SDSIndexableModel, transaction: GRDBWriteTransaction) {
        let uniqueId = model.uniqueId
        let collection = self.collection(forModel: model)

        serialQueue.sync {
            let cacheKey = self.cacheKey(collection: collection, uniqueId: uniqueId)
            ftsCache.removeObject(forKey: cacheKey)
        }

        executeUpdate(
            sql: """
            DELETE FROM \(contentTableName)
            WHERE \(uniqueIdColumn) == ?
            AND \(collectionColumn) == ?
            """,
            arguments: [uniqueId, collection],
            transaction: transaction)
    }

    public class func allModelsWereRemoved(collection: String, transaction: GRDBWriteTransaction) {

        serialQueue.sync {
            ftsCache.removeAllObjects()
        }

        executeUpdate(
            sql: """
            DELETE FROM \(contentTableName)
            WHERE \(collectionColumn) == ?
            """,
            arguments: [collection],
            transaction: transaction)
    }

    private static let disableFTS = false

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
                                        transaction: GRDBReadTransaction) -> SDSIndexableModel? {
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
        case SignalRecipient.collection():
            guard let model = SignalRecipient.anyFetch(uniqueId: uniqueId,
                                                     transaction: transaction.asAnyRead) else {
                                                        owsFailDebug("Couldn't load record: \(collection)")
                                                        return nil
            }
            return model
        case TSGroupMember.collection():
            guard let model = TSGroupMember.anyFetch(uniqueId: uniqueId, transaction: transaction.asAnyRead) else {
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

    public class func enumerateObjects<T: SDSIndexableModel>(searchText: String, maxResults: UInt, transaction: GRDBReadTransaction, block: @escaping (T, String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        enumerateObjects(
            searchText: searchText,
            collections: [T.collection()],
            maxResults: maxResults,
            transaction: transaction
        ) { object, snippet, stop in
            guard nil == object as? OWSGroupCallMessage else {
                return
            }
            guard let object = object as? T else {
                return owsFailDebug("Unexpected object type")
            }
            block(object, snippet, stop)
        }
    }

    public class func enumerateObjects(searchText: String, collections: [String], maxResults: UInt, transaction: GRDBReadTransaction, block: @escaping (Any, String, UnsafeMutablePointer<ObjCBool>) -> Void) {

        let query = FullTextSearchFinder.query(searchText: searchText)

        guard query.count > 0 else {
            // FullTextSearchFinder.query filters some characters, so query
            // may now be empty.
            Logger.warn("Empty query.")
            return
        }

        // Search with the query interface or SQL
        do {
            var stop: ObjCBool = false

            // GRDB TODO: We could use bm25() instead of rank to order results.
            let indexOfContentColumnInFTSTable = 0
            // Determines the length of the snippet.
            let numTokens: UInt = 15
            let matchSnippet = "match_snippet"
            let sql: String = """
                SELECT
                    \(contentTableName).\(collectionColumn),
                    \(contentTableName).\(uniqueIdColumn),
                    snippet(\(ftsTableName), \(indexOfContentColumnInFTSTable), '<\(matchTag)>', '</\(matchTag)>', '…', \(numTokens) ) as \(matchSnippet)
                FROM \(ftsTableName)
                LEFT JOIN \(contentTableName) ON \(contentTableName).rowId = \(ftsTableName).rowId
                WHERE \(ftsTableName).\(ftsContentColumn) MATCH ?
                AND \(collectionColumn) IN (\(collections.map { "'\($0)'" }.joined(separator: ",")))
                ORDER BY rank
                LIMIT \(maxResults)
            """

            let cursor = try Row.fetchCursor(transaction.database, sql: sql, arguments: [query])
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

class AnySearchIndexer: Dependencies {

    // MARK: - Index Building

    private static let groupThreadIndexer: SearchIndexer<TSGroupThread> = SearchIndexer { (groupThread: TSGroupThread, _: SDSAnyReadTransaction) in
        return groupThread.groupModel.groupNameOrDefault
    }

    private static let groupMemberIndexer: SearchIndexer<TSGroupMember> = SearchIndexer { (groupMember: TSGroupMember, transaction: SDSAnyReadTransaction) in
        return recipientIndexer.index(groupMember.address, transaction: transaction)
    }

    private static let contactThreadIndexer: SearchIndexer<TSContactThread> = SearchIndexer { (contactThread: TSContactThread, transaction: SDSAnyReadTransaction) in
        let recipientAddress = contactThread.contactAddress
        var result = recipientIndexer.index(recipientAddress, transaction: transaction)

        if contactThread.isNoteToSelf {
            let noteToSelfLabel = OWSLocalizedString("NOTE_TO_SELF", comment: "Label for 1:1 conversation with yourself.")
            result += " \(noteToSelfLabel)"
        }

        return result
    }

    private static let recipientIndexer: SearchIndexer<SignalServiceAddress> = SearchIndexer { recipientAddress, transaction in
        // A contact should always be searchable by their display name, as well
        // as by name components from system contacts if available. Note that
        // not all name components are available, as we only store
        // given/family/nicknames (excludes middle/prefix/suffix/phonetic).
        //
        // We may likely end up with duplicate text in the index since the
        // display name will likely include some or all of the name components,
        // but that's fine.
        var nameStrings: Set<String> = [contactsManager.displayName(for: recipientAddress, transaction: transaction)]
        if let nameComponents = contactsManager.nameComponents(for: recipientAddress, transaction: transaction) {
            let insert: (String?) -> Void = { if let s = $0 { nameStrings.insert(s) } }
            insert(nameComponents.givenName)
            insert(nameComponents.familyName)
            insert(nameComponents.nickname)
        }

        let nationalNumber: String? = { (recipientId: String?) -> String? in
            guard let recipientId = recipientId else { return nil }

            guard recipientId != kLocalProfileInvariantPhoneNumber else {
                return ""
            }

            guard let phoneNumber = PhoneNumber(fromE164: recipientId) else {
                owsFailDebug("unexpected unparsable recipientId: \(recipientId)")
                return ""
            }

            guard let digitScalars = phoneNumber.nationalNumber?.unicodeScalars.filter({ CharacterSet.decimalDigits.contains($0) }) else {
                owsFailDebug("unexpected unparsable recipientId: \(recipientId)")
                return ""
            }

            return String(String.UnicodeScalarView(digitScalars))
        }(recipientAddress.phoneNumber)

        return "\(recipientAddress.phoneNumber ?? "") \(nationalNumber ?? "") \(nameStrings.joined(separator: " "))"
    }

    private static let messageIndexer: SearchIndexer<TSMessage> = SearchIndexer { (message: TSMessage, transaction: SDSAnyReadTransaction) in
        if let bodyText = message.rawBody(with: transaction.unwrapGrdbRead) {
            return bodyText
        }
        return ""
    }

    class func indexContent(object: SDSIndexableModel, transaction: SDSAnyReadTransaction) -> String? {
        owsAssertDebug(GRDBFullTextSearchFinder.shouldIndexModel(object))

        if let groupThread = object as? TSGroupThread {
            return self.groupThreadIndexer.index(groupThread, transaction: transaction)
        } else if let groupMember = object as? TSGroupMember {
            return self.groupMemberIndexer.index(groupMember, transaction: transaction)
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
        } else if let signalRecipient = object as? SignalRecipient {
            return self.recipientIndexer.index(signalRecipient.address, transaction: transaction)
        } else {
            // This should be impossible (see assertion above), but we have it here just in case.
            return nil
        }
    }
}

public protocol SDSIndexableModel {
    var uniqueId: String { get }
    static var ftsIndexMode: TSFTSIndexMode { get }
    static func collection() -> String

    static func anyEnumerateIndexable(
        transaction: SDSAnyReadTransaction,
        block: @escaping (SDSIndexableModel) -> Void
    )
}
