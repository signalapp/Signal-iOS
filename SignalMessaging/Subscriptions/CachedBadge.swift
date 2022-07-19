//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

public final class CachedBadge: Equatable, Dependencies {

    let badgeLevel: OneTimeBadgeLevel

    init(level: OneTimeBadgeLevel) {
        self.badgeLevel = level
    }

    // If set, the badge and its assets are populated and ready to use.
    private var _profileBadge = AtomicOptional<ProfileBadge>(nil)
    public var profileBadge: ProfileBadge? { self._profileBadge.get() }

    // If set, there's an ongoing request to populate the badge. New callers
    // should join this chain to know when the shared request has finished.
    private var fetchPromise: Promise<ProfileBadge>?

    public static func == (lhs: CachedBadge, rhs: CachedBadge) -> Bool {
        // Cached badges are considered equivalent if the underlying badge has the
        // same level. We expect the resulting ProfileBadge to be the same if the
        // levels match.
        return lhs.badgeLevel == rhs.badgeLevel
    }

    @discardableResult
    public func fetchIfNeeded() -> Promise<ProfileBadge> {
        // Run on a stable queue to avoid race conditions.
        return firstly(on: .main) { () -> Promise<ProfileBadge> in
            // If we already have a cached value, do nothing.
            if let profileBadge = self.profileBadge {
                return Promise.value(profileBadge)
            }
            // If we're already fetching, chain onto that fetch.
            if let fetchPromise = self.fetchPromise {
                return fetchPromise
            }
            // Otherwise, kick off a new fetch.
            let fetchPromise: Promise<ProfileBadge> = firstly {
                SubscriptionManager.getBadge(level: self.badgeLevel)
            }.then { profileBadge in
                firstly {
                    self.profileManager.badgeStore.populateAssetsOnBadge(profileBadge)
                }.map { _ in
                    profileBadge
                }
            }.map { (profileBadge) -> ProfileBadge in
                self._profileBadge.set(profileBadge)
                return profileBadge
            }.ensure {
                self.fetchPromise = nil
            }
            // no need to catch -- network request errors are logged elsewhere
            self.fetchPromise = fetchPromise
            return fetchPromise
        }
    }
}
