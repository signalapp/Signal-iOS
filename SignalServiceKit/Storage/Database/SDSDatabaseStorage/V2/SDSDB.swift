//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Historically, we had multiple types of database transaction, which have been
/// consolidated into `DBTransaction`; these methods served as a bridge between
/// two specific types of transaction.
///
/// They exist now only to avoid me having to update all callers in the same PR
/// that made them no-ops. If you're reading this because you found a caller and
/// wondered what it was doing, you can safely remove the call instead!
public enum SDSDB {
    public static func shimOnlyBridge(_ readTx: DBReadTransaction) -> DBReadTransaction {
        return readTx
    }

    public static func shimOnlyBridge(_ writeTx: DBWriteTransaction) -> DBWriteTransaction {
        return writeTx
    }
}
