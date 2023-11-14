//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

extension Stripe {
    public struct StripeError: Error, IsRetryableProvider {
        public let code: String

        public var isRetryableProvider: Bool {
            return false
        }
    }
}
