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

    func pinnedThreads(tx: DBReadTransaction) -> [TSThread]

    func updatePinnedThreadUniqueIds(
        _ pinnedThreadUniqueIds: [String],
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    )

    func pinThread(
        uniqueId: String,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) throws(TooManyPinnedThreadsError)

    func unpinThread(
        uniqueId: String,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    )

    func handleUpdatedThread(_ thread: TSThread, tx: DBWriteTransaction)
}
