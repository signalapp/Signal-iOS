//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Stripe.PaymentMethod {

    public enum IDEAL: Equatable {
        case oneTime(name: String)
        case recurring(mandate: Mandate, name: String, email: String)
    }
}
