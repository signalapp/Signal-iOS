//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum PinnedThreads {
    public static let maxPinnedThreads = 6
}

public protocol PinnedThreadManager {

    func pinnedThreadIds(tx: DBReadTransaction) -> [String]

    func pinnedThreads(tx: DBReadTransaction) -> [TSThread]

    func isThreadPinned(_ thread: TSThread, tx: DBReadTransaction) -> Bool

    func updatePinnedThreadIds(
        _ pinnedThreadIds: [String],
        updateStorageService: Bool,
        tx: DBWriteTransaction
    )

    func pinThread(
        _ thread: TSThread,
        updateStorageService: Bool,
        tx: DBWriteTransaction
    ) throws

    func unpinThread(
        _ thread: TSThread,
        updateStorageService: Bool,
        tx: DBWriteTransaction
    ) throws

    func handleUpdatedThread(_ thread: TSThread, tx: DBWriteTransaction)
}

@objc
public class PinnedThreadManagerObjcBridge: NSObject {

    @objc
    static func handleUpdatedThread(_ thread: TSThread, transaction: DBWriteTransaction) {
        DependenciesBridge.shared.pinnedThreadManager.handleUpdatedThread(thread, tx: transaction)
    }
}
