//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MockSubscriptionManager: NSObject, SubscriptionManagerProtocol {
    public func reconcileBadgeStates(transaction: SDSAnyWriteTransaction) {
    }

    public func hasCurrentSubscription(transaction: SDSAnyReadTransaction) -> Bool {
        return false
    }
}
