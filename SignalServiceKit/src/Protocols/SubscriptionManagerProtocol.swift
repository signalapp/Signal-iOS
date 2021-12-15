//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol SubscriptionManagerProtocol {
    func reconcileBadgeStates(transaction: SDSAnyWriteTransaction)
    func hasCurrentSubscription(transaction: SDSAnyReadTransaction) -> Bool
}
