//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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
}
