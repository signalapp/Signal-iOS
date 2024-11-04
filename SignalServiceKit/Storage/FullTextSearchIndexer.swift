//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public enum FullTextSearchIndexer {
    public static let matchTag = "match"

    // MARK: - Normalization

    private static var charactersToRemove: CharacterSet = {
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
    public static func normalizeText(_ text: String) -> String {
        // 1. Filter out invalid characters.
        let filtered = text.removeCharacters(characterSet: charactersToRemove)

        // 2. Simplify whitespace.
        let simplified = filtered.replaceCharacters(
            characterSet: .whitespacesAndNewlines,
            replacement: " "
        )

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

    // MARK: - Querying

    // We want to match by prefix for "search as you type" functionality.
    // SQLite does not support suffix or contains matches.
    public static func buildQuery(for searchText: String) -> String {
        // 1. Normalize the search text.
        //
        // TODO: We could arguably convert to lowercase since the search
        // is case-insensitive.
        let normalizedSearchText = normalizeText(searchText)

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

// MARK: - Message Index

// See: http://groue.github.io/GRDB.swift/docs/4.1/index.html#full-text-search
// See: https://www.sqlite.org/fts5.html

extension FullTextSearchIndexer {
    public static let ftsTableName = "indexable_text_fts"

    static let contentTableName = "indexable_text"
    static let uniqueIdColumn = "uniqueId"
    static let collectionColumn = "collection"
    static let ftsContentColumn = "ftsIndexableContent"

    private static let legacyCollectionName = "TSInteraction"

    private static func indexableContent(for message: TSMessage, tx: SDSAnyReadTransaction) -> String? {
        guard !message.isViewOnceMessage else {
            // Don't index "view-once messages".
            return nil
        }
        guard !message.isGroupStoryReply else {
            return nil
        }
        guard message.editState != .pastRevision else {
            return nil
        }
        guard let bodyText = message.rawBody(transaction: tx) else {
            return nil
        }
        return normalizeText(bodyText)
    }

    public static func insert(_ message: TSMessage, tx: SDSAnyWriteTransaction) throws {
        guard let ftsContent = indexableContent(for: message, tx: tx) else {
            return
        }
        try executeUpdate(
            sql: """
            INSERT INTO \(contentTableName)
            (\(collectionColumn), \(uniqueIdColumn), \(ftsContentColumn))
            VALUES
            (?, ?, ?)
            """,
            arguments: [legacyCollectionName, message.uniqueId, ftsContent],
            tx: tx
        )
    }

    public static func update(_ message: TSMessage, tx: SDSAnyWriteTransaction) throws {
        try delete(message, tx: tx)
        try insert(message, tx: tx)
    }

    public static func delete(_ message: TSMessage, tx: SDSAnyWriteTransaction) throws {
        try executeUpdate(
            sql: """
            DELETE FROM \(contentTableName)
            WHERE \(uniqueIdColumn) == ?
            AND \(collectionColumn) == ?
            """,
            arguments: [message.uniqueId, legacyCollectionName],
            tx: tx
        )
    }

    private static func executeUpdate(
        sql: String,
        arguments: StatementArguments,
        tx: SDSAnyWriteTransaction
    ) throws {
        let database = tx.unwrapGrdbWrite.database
        do {
            let statement = try database.cachedStatement(sql: sql)
            try statement.setArguments(arguments)
            try statement.execute()
        } catch {
            DatabaseCorruptionState.flagDatabaseCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            throw error
        }
    }

    // MARK: - Querying

    public static func search(
        for searchText: String,
        maxResults: Int,
        tx: SDSAnyReadTransaction,
        block: (_ message: TSMessage, _ snippet: String, _ stop: inout Bool) -> Void
    ) {
        let query = buildQuery(for: searchText)

        if query.isEmpty {
            // FullTextSearchFinder.query filters some characters, so query
            // may now be empty.
            Logger.warn("Empty query.")
            return
        }

        // Search with the query interface or SQL
        do {
            // GRDB TODO: We could use bm25() instead of rank to order results.
            let indexOfContentColumnInFTSTable = 0
            // Determines the length of the snippet.
            let numTokens: UInt = 15
            let matchSnippet = "match_snippet"
            let sql: String = """
            SELECT
                \(contentTableName).\(collectionColumn),
                \(contentTableName).\(uniqueIdColumn),
                SNIPPET(\(ftsTableName), \(indexOfContentColumnInFTSTable), '<\(matchTag)>', '</\(matchTag)>', '…', \(numTokens)) AS \(matchSnippet)
            FROM \(ftsTableName)
            LEFT JOIN \(contentTableName) ON \(contentTableName).rowId = \(ftsTableName).rowId
            WHERE \(ftsTableName).\(ftsContentColumn) MATCH ?
            ORDER BY rank
            LIMIT \(maxResults)
            """

            let cursor = try Row.fetchCursor(tx.unwrapGrdbRead.database, sql: sql, arguments: [query])
            while let row = try cursor.next() {
                let collection: String = row[collectionColumn]
                guard collection == legacyCollectionName else {
                    owsFailDebug("Found something other than a message in the FTS table")
                    continue
                }
                guard let uniqueId = (row[uniqueIdColumn] as String).nilIfEmpty else {
                    owsFailDebug("Found a message with a uniqueId in the FTS table")
                    continue
                }
                let snippet: String = row[matchSnippet]
                guard let message = TSMessage.anyFetchMessage(uniqueId: uniqueId, transaction: tx) else {
                    owsFailDebug("Couldn't find message that exists in the FTS table")
                    continue
                }
                var stop = false
                block(message, snippet, &stop)
                if stop {
                    break
                }
            }
        } catch {
            owsFailDebug("Couldn't fetch results: \(error.grdbErrorForLogging)")
        }
    }
}
