//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension DonateViewController {
    enum DonationMode: Int {
        case oneTime
        case monthly

        /// Converts the donation mode (one-time or monthly) for this view to
        /// the equivalent in the "choose payment method" sheet.
        ///
        /// We need this because this view supports one-time or monthly, but the
        /// sheet supports one-time, monthly, and gifting.
        var forChoosePaymentMethodSheet: DonateChoosePaymentMethodSheet.DonationMode {
            switch self {
            case .oneTime: return .oneTime
            case .monthly: return .monthly
            }
        }

        /// Converts the donation mode (one-time or monthly) for this view to
        /// the equivalent in the badge thanks sheet.
        ///
        /// We need this because this view supports one-time or monthly, but the
        /// sheet supports one-time, monthly, and gifting.
        var forBadgeThanksSheet: BadgeThanksSheet.BadgeType {
            switch self {
            case .oneTime: return .boost
            case .monthly: return .subscription
            }
        }

        public var debugDescription: String {
            switch self {
            case .oneTime: return "one-time"
            case .monthly: return "monthly"
            }
        }
    }
}
