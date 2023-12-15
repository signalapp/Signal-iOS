//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Stripe {
    // These values are somewhat arbitrary.
    public static let SCHEME_FOR_3DS = "sgnlpay"
    static let RETURN_URL_FOR_3DS = "\(SCHEME_FOR_3DS)://3ds"

    static let RETURN_URL_FOR_IDEAL = "https://signaldonations.org/ideal"

    /// Parse the redirect URL from a Stripe response. See [Stripe's docs][0].
    ///
    /// [0]: https://stripe.com/docs/api/payment_intents/object#payment_intent_object-next_action-redirect_to_url-return_url
    static func parseNextActionRedirectUrl(from responseBodyJson: Any?) -> URL? {
        if
            let responseDict = responseBodyJson as? [String: Any?],
            let nextAction = responseDict["next_action"] as? [String: Any?],
            let nextActionType = nextAction["type"] as? String,
            nextActionType == "redirect_to_url",
            let redirectToUrlDict = nextAction["redirect_to_url"] as? [String: Any?],
            let redirectToUrlString = redirectToUrlDict["url"] as? String,
            let redirectToUrl = URL(string: redirectToUrlString)
        {
            return redirectToUrl
        } else {
            return nil
        }
    }
}
