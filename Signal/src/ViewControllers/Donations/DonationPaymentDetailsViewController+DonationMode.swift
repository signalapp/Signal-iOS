//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

extension DonationPaymentDetailsViewController {
    enum DonationMode {
        case oneTime
        case monthly(
            subscriptionLevel: DonationSubscriptionLevel,
            subscriberID: Data?,
            currentSubscription: Subscription?,
            currentSubscriptionLevel: DonationSubscriptionLevel?
        )
        case gift(thread: TSContactThread, messageText: String)
    }
}
