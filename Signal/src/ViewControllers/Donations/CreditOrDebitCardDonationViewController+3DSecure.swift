//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import AuthenticationServices
import SignalMessaging

extension CreditOrDebitCardDonationViewController {
    func show3DS(for redirectUrl: URL) -> Promise<String> {
        owsAssert(
            threeDSecureAuthenticationSession == nil,
            "[Donations] Unexpectedly already had a 3DS authentication session going"
        )

        Logger.info("[Donations] Presenting 3DS authentication sheet")

        let (promise, future) = Promise<String>.pending()

        let session = ASWebAuthenticationSession(
            url: redirectUrl,
            callbackURLScheme: Stripe.SCHEME_FOR_3DS
        ) { [weak self] (callbackUrl: URL?, error: Error?) -> Void in
            defer {
                self?.threeDSecureAuthenticationSession = nil
            }

            switch ASWebAuthenticationSession.resultify(callbackUrl: callbackUrl, error: error) {
            case let .success(callbackUrl):
                guard
                    let components = callbackUrl.components,
                    let queryItems = components.queryItems,
                    let intentQuery = queryItems.first(where: { $0.name == "payment_intent" }),
                    let result = intentQuery.value
                else {
                    Logger.error("[Donations] Stripe did not give us a payment intent from 3DS")
                    future.reject(DonationJobError.assertion)
                    return
                }

                future.resolve(result)
            case let .failure(error):
                Logger.warn("[Donations] 3DS error: \(error)")
                future.reject(DonationJobError.assertion)
            }
        }

        session.presentationContextProvider = self

        owsAssert(
            session.start(),
            "[Donations] Failed to start 3DS authentication session. Was it set up correctly?"
        )

        // Keep a reference so we can cancel it when this view deallocates.
        threeDSecureAuthenticationSession = session

        return promise
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension CreditOrDebitCardDonationViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window!
    }
}

// MARK: - URL utility

private extension URL {
    /// A small helper to make it easier to create ``URLComponents``.
    var components: URLComponents? { URLComponents(string: absoluteString) }
}
