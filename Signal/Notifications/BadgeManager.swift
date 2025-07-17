//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public protocol BadgeObserver {
    func didUpdateBadgeCount(
        _ badgeManager: BadgeManager,
        badgeCount: BadgeCount
    )
}

public class BadgeManager {
    public typealias FetchBadgeCountBlock = () -> BadgeCount

    let serialQueue = DispatchQueue(label: "badge-manager")
    private let fetchBadgeCountBlock: FetchBadgeCountBlock

    public init(fetchBadgeCountBlock: @escaping FetchBadgeCountBlock) {
        self.fetchBadgeCountBlock = fetchBadgeCountBlock
    }

    public convenience init(
        badgeCountFetcher: any BadgeCountFetcher,
        databaseStorage: SDSDatabaseStorage,
    ) {
        self.init(
            fetchBadgeCountBlock: {
                return databaseStorage.read { tx -> BadgeCount in
                    return badgeCountFetcher.fetchBadgeCount(tx: tx)
                }
            }
        )
    }

    private var observers = [Weak<BadgeObserver>]()
    private var shouldFetch: Bool = true
    private var isFetching: Bool = false
    private(set) var mostRecentBadgeCount: BadgeCount?

    private func fetchBadgeValueIfNeeded() {
        guard shouldFetch, !observers.isEmpty, !isFetching else {
            return
        }
        isFetching = true
        shouldFetch = false
        let backgroundTask = OWSBackgroundTask(label: #function)
        serialQueue.async {
            let badgeCount = self.fetchBadgeCountBlock()
            DispatchQueue.main.async {
                self.isFetching = false
                self.observers.removeAll(where: { $0.value == nil })
                if self.observers.isEmpty {
                    // If there are no observers, we're going to stop fetching badge values for
                    // a while, so don't keep around a value that's potentially outdated.
                    self.mostRecentBadgeCount = nil
                } else {
                    self.mostRecentBadgeCount = badgeCount
                    self.observers.forEach { $0.value?.didUpdateBadgeCount(self, badgeCount: badgeCount) }
                    self.fetchBadgeValueIfNeeded()
                }
                backgroundTask.end()
            }
        }
    }

    /// Invalidates any previous/active badge count fetches.
    ///
    /// Once you call this method, all observers will eventually be notified
    /// with a new badge value that was computed after this method was called.
    public func invalidateBadgeValue() {
        AssertIsOnMainThread()
        shouldFetch = true
        fetchBadgeValueIfNeeded()
    }

    /// Adds an observer that should be informed when the badge value changes.
    ///
    /// If there is already some other observer, and if we already fetched the
    /// badge value for that observer, we'll provide the most recent cached
    /// value to the new observer, even if it's slightly out of date.
    public func addObserver(_ observer: BadgeObserver) {
        AssertIsOnMainThread()
        if let mostRecentBadgeCount {
            observer.didUpdateBadgeCount(self, badgeCount: mostRecentBadgeCount)
        }
        observers.append(Weak(value: observer))
        fetchBadgeValueIfNeeded()
    }

    @MainActor
    public func startObservingChanges(in databaseChangeObserver: DatabaseChangeObserver) {
        databaseChangeObserver.appendDatabaseChangeDelegate(self)
    }
}

extension BadgeManager: DatabaseChangeDelegate {
    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        let badgeMightBeDifferent = (
            databaseChanges.didUpdateInteractions
            || databaseChanges.didUpdate(tableName: ThreadAssociatedData.databaseTableName)
            || databaseChanges.didUpdate(tableName: CallRecord.databaseTableName)
        )
        guard badgeMightBeDifferent else {
            return
        }
        invalidateBadgeValue()
    }

    public func databaseChangesDidUpdateExternally() {
        invalidateBadgeValue()
    }

    public func databaseChangesDidReset() {
        invalidateBadgeValue()
    }
}
