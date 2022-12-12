//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Stripe {
    public struct StripeError: Error {
        public let code: String
    }
}
