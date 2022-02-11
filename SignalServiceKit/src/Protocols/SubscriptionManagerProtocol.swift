//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol SubscriptionManagerProtocol {
    func reconcileBadgeStates(transaction: SDSAnyWriteTransaction)
    func hasCurrentSubscription(transaction: SDSAnyReadTransaction) -> Bool
    func timeSinceLastSubscriptionExpiration(transaction: SDSAnyReadTransaction) -> TimeInterval

    func userManuallyCancelledSubscription(transaction: SDSAnyReadTransaction) -> Bool
    func setUserManuallyCancelledSubscription(_ userCancelled: Bool, updateStorageService: Bool, transaction: SDSAnyWriteTransaction)
    var displayBadgesOnProfile: Bool { get }
    func displayBadgesOnProfile(transaction: SDSAnyReadTransaction) -> Bool
    func setDisplayBadgesOnProfile(_ displayBadgesOnProfile: Bool, updateStorageService: Bool, transaction: SDSAnyWriteTransaction)
}
