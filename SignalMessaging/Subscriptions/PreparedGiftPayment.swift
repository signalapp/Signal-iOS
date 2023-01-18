//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum PreparedGiftPayment {
    case forStripe(paymentIntent: Stripe.PaymentIntent, paymentMethodId: String)
    case forPaypal(approvalParams: Paypal.OneTimePaymentWebAuthApprovalParams)
}
