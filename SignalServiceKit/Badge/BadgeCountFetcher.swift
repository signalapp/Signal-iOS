//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct BadgeCount {
    public let unreadChatCount: UInt
    public let unreadCallsCount: UInt

    public var unreadTotalCount: UInt {
        unreadChatCount + unreadCallsCount
    }
}

public protocol BadgeCountFetcher {
    func fetchBadgeCount(tx: DBReadTransaction) -> BadgeCount
}

class BadgeCountFetcherImpl: BadgeCountFetcher {
    public func fetchBadgeCount(tx: DBReadTransaction) -> BadgeCount {
        let sdsTx = SDSDB.shimOnlyBridge(tx)

        let unreadInteractionCount = InteractionFinder.unreadCountInAllThreads(transaction: sdsTx)
        let unreadMissedCallCount = DependenciesBridge.shared.callRecordMissedCallManager.countUnreadMissedCalls(tx: tx)

        return BadgeCount(
            unreadChatCount: unreadInteractionCount,
            unreadCallsCount: unreadMissedCallCount
        )
    }
}
