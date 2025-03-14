//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB

extension Database {
    /// Execute some SQL.
    public func executeHandlingErrors(sql: String, arguments: StatementArguments = .init()) {
        do {
            let statement = try makeStatement(sql: sql)
            try statement.setArguments(arguments)
            try statement.execute()
        } catch {
            handleFatalDatabaseError(error)
        }
    }

    /// Execute some SQL and cache the statement.
    ///
    /// Caching the statement has significant performance benefits over ``execute`` for queries
    /// that are performed repeatedly.
    public func executeAndCacheStatementHandlingErrors(sql: String, arguments: StatementArguments = .init()) {
        do {
            let statement = try cachedStatement(sql: sql)
            try statement.setArguments(arguments)
            try statement.execute()
        } catch {
            handleFatalDatabaseError(error)
        }
    }

    public func strictRead<T>(_ criticalSection: (_ database: GRDB.Database) throws -> T) -> T {
        do {
            return try criticalSection(self)
        } catch {
            handleFatalDatabaseError(error)
        }
    }
}

// MARK: -

private func handleFatalDatabaseError(_ error: Error) -> Never {
    DatabaseCorruptionState.flagDatabaseCorruptionIfNecessary(
        userDefaults: CurrentAppContext().appUserDefaults(),
        error: error
    )
    owsFail("Error: \(error)")
}
