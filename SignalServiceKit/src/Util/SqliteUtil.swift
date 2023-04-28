//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// A bucket for SQLite utilities.
public enum SqliteUtil {
    /// Determine whether a table, column, or view name *could* lead to SQL injection.
    ///
    /// In some cases, you'd like to write something like this:
    ///
    ///     // This causes an error:
    ///     let sql = "SELECT * FROM ?"
    ///     try Row.fetchAll(db, sql: sql, arguments: [myTableName])
    ///
    /// Unfortunately, GRDB (perhaps because of SQLite) doesn't allow this kind of thing. That means
    /// we have to use string interpolation, which can be dangerous due to SQL injection. This helps
    /// keep that safe.
    ///
    /// Instead, you'd write something like this:
    ///
    ///     owsAssert(SqliteUtil.isSafe(myTableName))
    ///     let sql = "SELECT * FROM \(myTableName)"
    ///     try Row.fetchAll(db, sql: sql)
    ///
    /// This is unlikely to happen for our app, and should always return `true`.
    ///
    /// This check may return false negatives. For example, SQLite supports empty table names which
    /// this function would mark unsafe.
    ///
    /// - Parameter sqlName: The table, column, or view name to be checked.
    /// - Returns: Whether the name is safe to use in SQL string interpolation.
    public static func isSafe(sqlName: String) -> Bool {
        !sqlName.isEmpty &&
        sqlName.utf8.count < 1000 &&
        !sqlName.lowercased().starts(with: "sqlite") &&
        sqlName.range(of: "^[a-zA-Z][a-zA-Z0-9_]*$", options: .regularExpression) != nil
    }

    public enum IntegrityCheckResult {
        case ok
        case notOk

        public static func && (
            lhs: IntegrityCheckResult,
            rhs: IntegrityCheckResult
        ) -> IntegrityCheckResult {
            switch (lhs, rhs) {
            case (.ok, .ok): return .ok
            default: return .notOk
            }
        }
    }

    /// Get the result of [`PRAGMA cipher_provider`][0].
    ///
    /// [0]: https://www.zetetic.net/sqlcipher/sqlcipher-api/#cipher_provider
    public static func cipherProvider(db: Database) -> String {
        return (try? String.fetchOne(db, sql: "PRAGMA cipher_provider")) ?? ""
    }

    /// Run [`PRAGMA cipher_integrity_check`][0], log the results, and report whether the check
    /// succeeded.
    ///
    /// [0]: https://www.zetetic.net/sqlcipher/sqlcipher-api/#cipher_integrity_check
    public static func cipherIntegrityCheck(db: Database) -> IntegrityCheckResult {
        var hasAnyOutput = false
        do {
            let cursor = try String.fetchCursor(db, sql: "PRAGMA cipher_integrity_check")
            while let line = try cursor.next() {
                let strippedLine = line.stripped
                Logger.info(strippedLine)
                hasAnyOutput = hasAnyOutput || !strippedLine.isEmpty
            }
        } catch {
            Logger.error("PRAGMA cipher_integrity_check failed to run")
            return .notOk
        }

        if hasAnyOutput {
            Logger.error("PRAGMA cipher_integrity_check failed")
            return .notOk
        } else {
            return .ok
        }
    }

    /// Run [`PRAGMA quick_check`][0] and report whether the check succeeded.
    ///
    /// We don't log much because that *could* log sensitive user data with really bad corruption.
    ///
    /// [0]: https://www.sqlite.org/pragma.html#pragma_quick_check
    public static func quickCheck(db: Database) -> IntegrityCheckResult {
        let firstQuickCheckLine: String?
        do {
            firstQuickCheckLine = try String.fetchOne(db, sql: "PRAGMA quick_check")
        } catch {
            Logger.error("PRAGMA quick_check failed to run")
            return .notOk
        }

        if firstQuickCheckLine?.starts(with: "ok") == true {
            Logger.info("PRAGMA quick_check: ok")
            return .ok
        } else {
            Logger.error("PRAGMA quick_check failed (failure redacted)")
            return .notOk
        }
    }

    /// Run [`REINDEX`][0].
    ///
    /// [0]: https://sqlite.org/lang_reindex.html
    public static func reindex(db: Database) throws {
        try db.execute(sql: "REINDEX")
    }

    /// A bucket for FTS5 utilities.
    public enum Fts5 {
        public enum IntegrityCheckResult {
            case ok
            case corrupted
        }

        /// Run an [integrity-check command] on an FTS5 table.
        ///
        /// - Parameter db: A database connection.
        /// - Parameter ftsTableName: The virtual FTS5 table to use. This table name must be "safe"
        ///   according to ``Sqlite.isSafe``. If it's not, a fatal error will be thrown.
        /// - Parameter rank: The `rank` parameter to use. See the SQLite docs for more information.
        /// - Returns: An integrity check result.
        ///
        /// [integrity-check command]: https://www.sqlite.org/fts5.html#the_integrity_check_command
        public static func integrityCheck(
            db: Database,
            ftsTableName: String,
            compareToExternalContentTable: Bool
        ) throws -> IntegrityCheckResult {
            owsAssert(SqliteUtil.isSafe(sqlName: ftsTableName))

            let sql: String
            if compareToExternalContentTable {
                sql = "INSERT INTO \(ftsTableName) (\(ftsTableName), rank) VALUES ('integrity-check', 1)"
            } else {
                sql = "INSERT INTO \(ftsTableName) (\(ftsTableName)) VALUES ('integrity-check')"
            }

            do {
                try db.execute(sql: sql)
            } catch {
                if
                    let dbError = error as? DatabaseError,
                    dbError.extendedResultCode == .SQLITE_CORRUPT_VTAB
                {
                    return .corrupted
                } else {
                    throw error
                }
            }

            return .ok
        }

        /// Run a [rebuild command] on an FTS5 table.
        ///
        /// - Parameter db: A database connection.
        /// - Parameter ftsTableName: The virtual FTS5 table to use. This table name must be "safe"
        ///   according to ``Sqlite.isSafe``. If it's not, a fatal error will be thrown.
        ///
        /// [rebuild command]: https://www.sqlite.org/fts5.html#the_rebuild_command
        public static func rebuild(db: Database, ftsTableName: String) throws {
            owsAssert(SqliteUtil.isSafe(sqlName: ftsTableName))

            try db.execute(
                sql: "INSERT INTO \(ftsTableName) (\(ftsTableName)) VALUES ('rebuild')"
            )
        }
    }
}
