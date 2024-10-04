//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// Wrapper around `SDSAnyReadTransaction` that allows the generation
/// of a "fake" instance in tests without touching existing code.
///
/// There should only ever be three concrete implementations of this protocol:
/// * ``SDSDB.ReadTx``
/// * ``InMemoryDB.ReadTransaction``
/// * ``MockTransaction``
///
/// Classes wishing to access the database directly (things like FooStore) should
/// access the database connection directly by using ``databaseConnection``.
/// Classes that do not directly access the database should not access the database connection.
///
/// Shims can bridge to `SDSAnyReadTransaction` by using ``SDSDB.shimOnlyBridge``;
/// this is made intentionally cumbersome as it should **never** be used in
/// any concrete class and **only** in shim classes that bridge to old-style code.
public protocol DBReadTransaction: AnyObject {}

/// Wrapper around `SDSAnyWriteTransaction` that allows the generation
/// of a "fake" instance in tests without touching existing code.
///
/// There should only ever be two concrete implementations of this
/// protocol: `SDSDB.WriteTx` and `MockWriteTransaction`
///
/// Classes wishing to access the database directly (things like FooStore) should
/// access the database connection directly by using ``databaseConnection``.
/// Classes that do not directly access the database should not access the database connection.
///
/// Shims can bridge to `SDSAnyWriteTransaction` by using ``SDSDB.shimOnlyBridge``;
/// this is made intentionally cumbersome as it should **never** be used in
/// any concrete class and **only** in shim classes that bridge to old-style code.
public protocol DBWriteTransaction: DBReadTransaction {
    func addFinalization(forKey key: String, block: @escaping () -> Void)
    func addSyncCompletion(_ block: @escaping () -> Void)
    func addAsyncCompletion(on scheduler: Scheduler, _ block: @escaping () -> Void)
}

public func databaseConnection(_ tx: DBReadTransaction) -> GRDB.Database {
    #if TESTABLE_BUILD
    if let tx = tx as? InMemoryDB.ReadTransaction {
        return tx.db
    }
    #endif

    return SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database
}

public func databaseConnection(_ tx: DBWriteTransaction) -> GRDB.Database {
    #if TESTABLE_BUILD
    if let tx = tx as? InMemoryDB.WriteTransaction {
        return tx.db
    }
    #endif
    return SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database
}
