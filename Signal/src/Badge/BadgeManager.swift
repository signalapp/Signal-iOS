//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SignalServiceKit

public protocol BadgeObserver {
    func didUpdateBadgeValue(_ badgeManager: BadgeManager, badgeValue: UInt)
}

public class BadgeManager {
    private let mainScheduler: Scheduler
    private let serialScheduler: Scheduler
    private let fetchBadgeValueBlock: () -> UInt

    public init(
        mainScheduler: Scheduler,
        serialScheduler: Scheduler,
        fetchBadgeValue: @escaping () -> UInt
    ) {
        self.mainScheduler = mainScheduler
        self.serialScheduler = serialScheduler
        self.fetchBadgeValueBlock = fetchBadgeValue
    }

    public convenience init(
        databaseStorage: SDSDatabaseStorage,
        mainScheduler: Scheduler,
        serialScheduler: Scheduler
    ) {
        self.init(
            mainScheduler: mainScheduler,
            serialScheduler: serialScheduler,
            fetchBadgeValue: {
                databaseStorage.read { tx in
                    InteractionFinder.unreadCountInAllThreads(transaction: tx)
                }
            }
        )
    }

    private var observers = [Weak<BadgeObserver>]()
    private var shouldFetch: Bool = true
    private var isFetching: Bool = false
    private(set) var mostRecentBadgeValue: UInt?

    private func fetchBadgeValueIfNeeded() {
        guard shouldFetch, !observers.isEmpty, !isFetching else {
            return
        }
        isFetching = true
        shouldFetch = false
        let backgroundTask = OWSBackgroundTask(label: #function)
        serialScheduler.async {
            let badgeValue = self.fetchBadgeValueBlock()
            self.mainScheduler.async {
                self.isFetching = false
                self.observers.removeAll(where: { $0.value == nil })
                if self.observers.isEmpty {
                    // If there are no observers, we're going to stop fetching badge values for
                    // a while, so don't keep around a value that's potentially outdated.
                    self.mostRecentBadgeValue = nil
                } else {
                    self.mostRecentBadgeValue = badgeValue
                    self.observers.forEach { $0.value?.didUpdateBadgeValue(self, badgeValue: badgeValue) }
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
        if let mostRecentBadgeValue {
            observer.didUpdateBadgeValue(self, badgeValue: mostRecentBadgeValue)
        }
        observers.append(Weak(value: observer))
        fetchBadgeValueIfNeeded()
    }

    public func startObservingChanges(in databaseStorage: SDSDatabaseStorage) {
        databaseStorage.appendDatabaseChangeDelegate(self)
    }
}

extension BadgeManager: DatabaseChangeDelegate {
    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        let badgeMightBeDifferent = (
            databaseChanges.didUpdateInteractions
            || databaseChanges.didUpdateModel(collection: String(describing: ThreadAssociatedData.self))
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
