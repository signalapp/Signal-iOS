//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SignalServiceKit

public final class CachedBadge: Equatable, Dependencies {

    let badgeLevel: OneTimeBadgeLevel

    init(level: OneTimeBadgeLevel) {
        self.badgeLevel = level
    }

    public enum Value: Equatable {
        case notFound
        case profileBadge(ProfileBadge)
    }

    // If set, the badge and its assets are populated and ready to use.
    private var _cachedValue = AtomicOptional<Value>(nil)
    public var cachedValue: Value? { self._cachedValue.get() }

    // If set, there's an ongoing request to populate the badge. New callers
    // should join this chain to know when the shared request has finished.
    private var fetchPromise: Promise<Value>?

    public static func == (lhs: CachedBadge, rhs: CachedBadge) -> Bool {
        // Cached badges are considered equivalent if the underlying badge has the
        // same level. We expect the resulting ProfileBadge to be the same if the
        // levels match.
        return lhs.badgeLevel == rhs.badgeLevel
    }

    @discardableResult
    public func fetchIfNeeded() -> Promise<Value> {
        // Run on a stable queue to avoid race conditions.
        return firstly(on: DispatchQueue.main) { () -> Promise<Value> in
            // If we already have a cached value, do nothing.
            if let cachedValue = self.cachedValue {
                return Promise.value(cachedValue)
            }
            // If we're already fetching, chain onto that fetch.
            if let fetchPromise = self.fetchPromise {
                return fetchPromise
            }
            // Otherwise, kick off a new fetch.
            let fetchPromise: Promise<Value> = firstly {
                SubscriptionManagerImpl.getOneTimeBadge(level: self.badgeLevel)
            }.then { (profileBadge) -> Promise<Value> in
                switch profileBadge {
                case .none:
                    return Promise.value(.notFound)

                case .some(let profileBadge):
                    return firstly {
                        self.profileManager.badgeStore.populateAssetsOnBadge(profileBadge)
                    }.map { _ in
                        return .profileBadge(profileBadge)
                    }
                }
            }.map { (value) -> Value in
                self._cachedValue.set(value)
                return value
            }.ensure {
                self.fetchPromise = nil
            }
            // no need to catch -- network request errors are logged elsewhere
            self.fetchPromise = fetchPromise
            return fetchPromise
        }
    }
}
