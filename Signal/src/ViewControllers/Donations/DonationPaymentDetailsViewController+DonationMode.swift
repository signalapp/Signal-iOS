//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

extension DonationPaymentDetailsViewController {
    enum DonationMode {
        case oneTime
        case monthly(
            subscriptionLevel: SubscriptionLevel,
            subscriberID: Data?,
            currentSubscription: Subscription?,
            currentSubscriptionLevel: SubscriptionLevel?
        )
        case gift(thread: TSContactThread, messageText: String)
    }
}
