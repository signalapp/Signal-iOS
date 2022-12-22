//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PassKit
import SignalMessaging

extension DonateViewController: PKPaymentAuthorizationControllerDelegate {
    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
    }

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        switch state.donateMode {
        case .oneTime:
            paymentAuthorizationControllerForOneTime(
                controller,
                didAuthorizePayment: payment,
                handler: handler
            )
        case .monthly:
            paymentAuthorizationControllerForMonthly(
                controller,
                didAuthorizePayment: payment,
                handler: handler
            )
        }
    }
}
