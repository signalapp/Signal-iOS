//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import AuthenticationServices
import SignalMessaging

extension DonationPaymentDetailsViewController {
    func show3DS(for redirectUrl: URL) -> Promise<String> {
        owsAssert(
            threeDSecureAuthenticationSession == nil,
            "[Donations] Unexpectedly already had a 3DS authentication session going"
        )

        Logger.info("[Donations] Presenting 3DS authentication sheet")

        let (promise, future) = Promise<String>.pending()

        let queryItemName = {
            switch self.donationMode {
            case .monthly:
                return "setup_intent"
            case .gift, .oneTime:
                return "payment_intent"
            }
        }()

        let session = ASWebAuthenticationSession(
            url: redirectUrl,
            callbackURLScheme: Stripe.SCHEME_FOR_3DS
        ) { (callbackUrl: URL?, error: Error?) -> Void in
            switch ASWebAuthenticationSession.resultify(callbackUrl: callbackUrl, error: error) {
            case let .success(callbackUrl):
                guard
                    let components = callbackUrl.components,
                    let queryItems = components.queryItems,
                    let intentQuery = queryItems.first(where: { $0.name == queryItemName }),
                    let result = intentQuery.value
                else {
                    Logger.error("[Donations] Stripe did not give us a payment intent from 3DS")
                    future.reject(Stripe.RedirectAuthorizationError.invalidCallback)
                    return
                }

                future.resolve(result)
            case let .failure(error):
                Logger.warn("[Donations] Payment authorization redirect error: \(error)")
                future.reject(Stripe.RedirectAuthorizationError.cancelled)
            }
        }

        session.presentationContextProvider = self

        owsAssert(
            session.start(),
            "[Donations] Failed to start 3DS authentication session. Was it set up correctly?"
        )

        // Keep a reference so we can cancel it when this view deallocates.
        threeDSecureAuthenticationSession = session
        threeDSecureAuthenticationFuture = future

        return promise.ensure { [weak self] in
            self?.threeDSecureAuthenticationSession = nil
            self?.threeDSecureAuthenticationFuture = nil
        }
    }

    /// Expose a way to externally call back into the 3DSecure flow with the necessary information. This
    /// method presumes the necessary actions have been taken in the 3DSecure flow to authenticate with
    /// the Stripe backend before continuing. Otherwise, the transaction will eventually fail as unauthed.
    /// The main consumer of this endpoint is from a 3rd party banking app deep-linking back into the app
    /// after external authentication, allowing the in-app flow to continue from where it left off.
    /// - Returns:
    /// `true` or `false` depending on if the donation was able to continue with an existing donation flow.
    public func completeExternal3DS(success: Bool, intentID: String) -> Bool {
        guard let future = threeDSecureAuthenticationFuture else { return false }
        defer {
            threeDSecureAuthenticationFuture = nil
        }
        if !success {
            future.reject(Stripe.RedirectAuthorizationError.denied)
        } else {
            future.resolve(intentID)
        }
        return true
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension DonationPaymentDetailsViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        view.window!
    }
}

// MARK: - URL utility

private extension URL {
    /// A small helper to make it easier to create ``URLComponents``.
    var components: URLComponents? { URLComponents(string: absoluteString) }
}
