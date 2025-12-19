//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB

extension Database {
    /// Execute some SQL using/creating a cached statement.
    ///
    /// Caching statements has significant performance benefits for queries that
    /// are performed repeatedly.
    ///
    /// - Important Crashes on database errors.
    /// - SeeAlso ``executeWithCachedStatementThrows(sql:arguments:)``
    public func executeWithCachedStatement(
        sql: String,
        arguments: StatementArguments,
    ) {
        failIfThrows {
            try executeWithCachedStatementThrows(
                sql: sql,
                arguments: arguments,
            )
        }
    }

    /// Like ``executeWithCachedStatement(sql:arguments:)``, but throws instead
    /// of crashes on database errors.
    public func executeWithCachedStatementThrows(
        sql: String,
        arguments: StatementArguments,
    ) throws(GRDB.DatabaseError) {
        do {
            let statement = try cachedStatement(sql: sql)
            try statement.execute(arguments: arguments)
        } catch {
            throw error.forceCastToDatabaseError()
        }
    }
}
