//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB

/// Like ``GRDB/Database/TransactionCompletion`` but includes variant type.
public enum TransactionCompletion<T> {
    /// Confirms changes
    case commit(T)

    /// Cancel changes
    case rollback(T)

    public var typeErased: TransactionCompletion<Void> {
        switch self {
        case .commit:
            return .commit(())
        case .rollback:
            return .rollback(())
        }
    }

    public var asGRDBCompletion: GRDB.Database.TransactionCompletion {
        switch self {
        case .commit:
            return .commit
        case .rollback:
            return .rollback
        }
    }
}
