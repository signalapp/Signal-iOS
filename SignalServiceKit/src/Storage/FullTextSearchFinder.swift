//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

// Create a searchable index for objects of type T
public class SearchIndexer<T> {

    private let indexBlock: (T, YapDatabaseReadTransaction) -> String

    public init(indexBlock: @escaping (T, YapDatabaseReadTransaction) -> String) {
        self.indexBlock = indexBlock
    }

    public func index(_ item: T, transaction: YapDatabaseReadTransaction) -> String {
        return normalize(indexingText: indexBlock(item, transaction))
    }

    private func normalize(indexingText: String) -> String {
        return FullTextSearchFinder.normalize(text: indexingText)
    }
}

@objc
public class FullTextSearchFinder: NSObject {

    // MARK: - Dependencies

    private static var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    // MARK: - Querying

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

    public func enumerateObjects(searchText: String, transaction: YapDatabaseReadTransaction, block: @escaping (Any, String) -> Void) {
        guard let ext: YapDatabaseFullTextSearchTransaction = ext(transaction: transaction) else {
            owsFailDebug("ext was unexpectedly nil")
            return
        }

        let query = FullTextSearchFinder.query(searchText: searchText)

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

            block(object, snippet)
        }
    }

    // MARK: - Normalization

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
        return simplified.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Index Building

    private class var contactsManager: ContactsManagerProtocol {
        return SSKEnvironment.shared.contactsManager
    }

    private static let groupThreadIndexer: SearchIndexer<TSGroupThread> = SearchIndexer { (groupThread: TSGroupThread, transaction: YapDatabaseReadTransaction) in
        let groupName = groupThread.groupModel.groupName ?? ""

        let memberStrings = groupThread.groupModel.groupMembers.map { address in
            recipientIndexer.index(address, transaction: transaction)
        }.joined(separator: " ")

        return "\(groupName) \(memberStrings)"
    }

    private static let contactThreadIndexer: SearchIndexer<TSContactThread> = SearchIndexer { (contactThread: TSContactThread, transaction: YapDatabaseReadTransaction) in
        let recipientAddress = contactThread.contactAddress
        var result = recipientIndexer.index(recipientAddress, transaction: transaction)

        if let localAddress = tsAccountManager.storedOrCachedLocalAddress(transaction.asAnyRead), IsNoteToSelfEnabled(), localAddress.matchesAddress(recipientAddress) {
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

        return "\(recipientAddress.stringForDisplay ?? "") \(nationalNumber ?? "") \(displayName)"
    }

    private static let messageIndexer: SearchIndexer<TSMessage> = SearchIndexer { (message: TSMessage, transaction: YapDatabaseReadTransaction) in
        if let bodyText = message.bodyText(with: transaction.asAnyRead) {
            return bodyText
        }
        return ""
    }

    private class func indexContent(object: Any, transaction: YapDatabaseReadTransaction) -> String? {
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
            guard !message.hasPerMessageExpiration else {
                // Don't index "one-off disappearing messages".
                return nil
            }
            return self.messageIndexer.index(message, transaction: transaction)
        } else if let signalAccount = object as? SignalAccount {
            return self.recipientIndexer.index(signalAccount.recipientAddress, transaction: transaction)
        } else {
            return nil
        }
    }

    // MARK: - Extension Registration

    private static let dbExtensionName: String = "FullTextSearchFinderExtension"

    private func ext(transaction: YapDatabaseReadTransaction) -> YapDatabaseFullTextSearchTransaction? {
        return transaction.safeFullTextSearchTransaction(FullTextSearchFinder.dbExtensionName)
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
            dict[contentColumnName] = indexContent(object: object, transaction: transaction)
        }

        // update search index on contact name changes?

        return YapDatabaseFullTextSearch(columnNames: ["content"],
                                         options: nil,
                                         handler: handler,
                                         ftsVersion: YapDatabaseFullTextSearchFTS5Version,
                                         versionTag: "1")
    }
}
