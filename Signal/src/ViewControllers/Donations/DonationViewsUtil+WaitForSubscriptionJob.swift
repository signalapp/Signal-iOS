//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

private extension Optional where Wrapped == DonationPaymentMethod {
    var timeoutDuration: TimeInterval {
        // Default to the longer duration if we don't know what payment method
        // we are.
        return self?.timeoutDuration ?? 30
    }
}

private extension DonationPaymentMethod {
    var timeoutDuration: TimeInterval {
        switch self {
        case .applePay, .creditOrDebitCard, .paypal:
            // We hope these payments will process quickly, so we'll wait a
            // decent amount of time before timing out in the hopes that we can
            // learn the status of the completed payment synchronously.
            return 30
        case .sepa, .ideal:
            // We expect SEPA payments (including those fronted by iDEAL)
            // will not process in a realistically-waitable time, so use
            // a shortened window before timing out for them.
            return 10
        }
    }
}

extension DonationViewsUtil {
    public static func waitForRedemptionJob(
        _ jobPromise: Promise<Void>,
        paymentMethod: DonationPaymentMethod?
    ) -> Promise<Void> {
        return jobPromise
            .recover({ _ in throw DonationJobError.assertion })
            .timeout(seconds: paymentMethod.timeoutDuration, timeoutErrorBlock: { DonationJobError.timeout })
    }
}
