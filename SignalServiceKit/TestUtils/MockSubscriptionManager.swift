//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class MockSubscriptionManager: NSObject, SubscriptionManager {
    public func reconcileBadgeStates(transaction: SDSAnyWriteTransaction) {
    }

    public func hasCurrentSubscription(transaction: SDSAnyReadTransaction) -> Bool {
        return false
    }

    public func timeSinceLastSubscriptionExpiration(transaction: SDSAnyReadTransaction) -> TimeInterval {
        return 0
    }

    public func userManuallyCancelledSubscription(transaction: SDSAnyReadTransaction) -> Bool { false }
    public func setUserManuallyCancelledSubscription(_ userCancelled: Bool, updateStorageService: Bool, transaction: SDSAnyWriteTransaction) {}
    public var displayBadgesOnProfile: Bool { false }
    public func displayBadgesOnProfile(transaction: SDSAnyReadTransaction) -> Bool { false }
    public func setDisplayBadgesOnProfile(_ displayBadgesOnProfile: Bool, updateStorageService: Bool, transaction: SDSAnyWriteTransaction) {}
}
