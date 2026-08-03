//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct TooManyPinnedThreadsError: Error {
}

public enum PinnedThreads {
    public static var maxPinnedThreads: UInt {
        RemoteConfig.current.pinnedThreadLimit
    }
}

public protocol PinnedThreadManager {
    /// A value used for sorting pinned threads.
    ///
    /// There may be "gaps" between values. (For example, calling this method
    /// for every thread may return `[3, nil, 1, nil, 4]`, which would mean
    /// there are five threads and three of them are pinned.)
    ///
    /// Returns nil if a thread isn't pinned.
    func pinnedThreadOrder(forThread thread: TSThread, tx: DBReadTransaction) -> Int64?

    /// Fetches pinned threads.
    ///
    /// - Warning: If a pinned thread doesn't yet exist (e.g., a group that's
    /// still being restored), it's omitted from the result.
    func pinnedThreads(tx: DBReadTransaction) -> [TSThread]

    func setPinnedThreads(
        _ threads: [TSThread],
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    )

    func setPinnedThreadIds(
        _ threadIds: [PinnedThreadId],
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    )

    func pinThread(
        _ thread: TSThread,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) throws(TooManyPinnedThreadsError)

    func unpinThread(
        _ thread: TSThread,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    )

    func handleUpdatedThread(_ thread: TSThread, tx: DBWriteTransaction)
}

protocol PinnedThreadMerger {
    func mergeRecipientId(
        _ recipientId: SignalRecipient.RowId,
        into targetRecipientId: SignalRecipient.RowId,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    )
}
