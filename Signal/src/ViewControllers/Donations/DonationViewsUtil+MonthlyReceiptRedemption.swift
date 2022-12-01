//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

extension DonationViewsUtil {
    static func redeemMonthlyReceipts(
        usingPaymentProcessor paymentProcessor: PaymentProcessor,
        subscriberID: Data,
        newSubscriptionLevel: SubscriptionLevel,
        priorSubscriptionLevel: SubscriptionLevel?
    ) {
        SubscriptionManager.terminateTransactionIfPossible = false

        SubscriptionManager.requestAndRedeemReceiptsIfNecessary(
            for: subscriberID,
            usingPaymentProcessor: paymentProcessor,
            subscriptionLevel: newSubscriptionLevel.level,
            priorSubscriptionLevel: priorSubscriptionLevel?.level
        )
    }
}
