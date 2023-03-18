//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Wrapper around `SDSAnyReadTransaction` that allows the generation
/// of a "fake" instance in tests without touching existing code.
///
/// There should only ever be two concrete implementations of this
/// protocol: `SDSDB.ReadTx` and `MockReadTransaction`.
///
/// Users can bridge to `SDSAnyReadTransaction` by using `SDSDB.shimOnlyBridge`;
/// this is made intentionally cumbersome as it should **never** be used in
/// any concrete class and **only** in shim classes that bridge to old-style code.
public protocol DBReadTransaction {}

/// Wrapper around `SDSAnyWriteTransaction` that allows the generation
/// of a "fake" instance in tests without touching existing code.
///
/// There should only ever be two concrete implementations of this
/// protocol: `SDSDB.WriteTx` and `MockWriteTransaction`
///
/// Users can bridge to `SDSAnyWriteTransaction` by using `SDSDB.shimOnlyBridge`;
/// this is made intentionally cumbersome as it should **never** be used in
/// any concrete class and **only** in shim classes that bridge to old-style code.
public protocol DBWriteTransaction: DBReadTransaction {

    func addAsyncCompletion(on scheduler: Scheduler, _ block: @escaping () -> Void)
}
