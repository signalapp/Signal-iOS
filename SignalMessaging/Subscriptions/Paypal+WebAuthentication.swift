//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AuthenticationServices
import Foundation

/// PayPal donations are authorized by a user via PayPal's web interface,
/// presented in an ``ASWebAuthenticationSession``.
///
/// We present an auth session beginning at a PayPal URL we fetch from our
/// service. However, the callback URLs that PayPal will complete our session
/// with do not use a custom URL scheme, and therefore we cannot rely on the
/// auth session completing itself. Instead, when the PayPal flow is complete
/// the user will be directed to a domain that deep-links back into the app, at
/// which point we can manually cancel the (complete) auth session.
extension Paypal {
    static let approvedCallbackUrl: URL = URL(string: "https://signaldonations.org/approved")!
    static let canceledCallbackUrl: URL = URL(string: "https://signaldonations.org/canceled")!

    /// Represents parameters returned to us after an approved PayPal
    /// authentication, which are used to confirm a payment. These fields are
    /// opaque to us.
    public struct WebAuthApprovalParams {
        let payerId: String
        let paymentId: String
        let paymentToken: String

        /// Represents the query-string keys for the elements we expect to be
        /// present in the callback URL from a successful PayPal authentication.
        private enum QueryKey: String {
            case payerId = "PayerID"
            case paymentId = "paymentId"
            case paymentToken = "token"
        }

        fileprivate init?(queryItems: [URLQueryItem]) {
            let queryItemMap: [QueryKey: String] = queryItems.reduce(into: [:]) { partialResult, queryItem in
                guard let queryKey = QueryKey(rawValue: queryItem.name) else {
                    Logger.warn("[Donations] Unexpected query item: \(queryItem.name)")
                    return
                }

                guard partialResult[queryKey] == nil else {
                    owsFailDebug("[Donations] Unexpectedly had duplicate known query items: \(queryKey)")
                    return
                }

                guard let value = queryItem.value else {
                    owsFailDebug("[Donations] Unexpectedly missing value for known query item: \(queryKey)")
                    return
                }

                partialResult[queryKey] = value
            }

            self.init(queryItemMap: queryItemMap)
        }

        private init?(queryItemMap: [QueryKey: String]) {
            guard
                let payerId = queryItemMap[.payerId],
                let paymentId = queryItemMap[.paymentId],
                let paymentToken = queryItemMap[.paymentToken]
            else {
                return nil
            }

            self.payerId = payerId
            self.paymentId = paymentId
            self.paymentToken = paymentToken
        }
    }

    /// Represents an error returned from web authentication.
    public enum AuthError: Error {
        case userCanceled
    }

    private static let _liveAuthSession: AtomicOptional<AuthSession> = AtomicOptional(nil)
}

// MARK: - Present a new auth session

public extension Paypal {
    /// Creates and presents a new auth session. Only one auth session should
    /// be able to exist at once.
    ///
    /// On iOS 13+, a `presentationContext` is required.
    @available(iOS 13, *)
    static func present(
        approvalUrl: URL,
        withPresentationContext presentationContext: ASWebAuthenticationPresentationContextProviding
    ) -> Promise<WebAuthApprovalParams> {
        let (session, promise) = makeNewAuthSession(approvalUrl: approvalUrl)
        session.presentationContextProvider = presentationContext
        owsAssert(
            session.start(),
            "[Donations] Failed to start PayPal authentication session. Was it set up correctly?"
        )

        return promise
    }

    /// Creates and presents a new auth session. Only one auth session should
    /// be able to exist at once.
    ///
    /// Only for use on iOS 12.
    @available(iOS, introduced: 12, obsoleted: 13)
    static func present(
        approvalUrl: URL
    ) -> Promise<WebAuthApprovalParams> {
        let (session, promise) = makeNewAuthSession(approvalUrl: approvalUrl)
        owsAssert(
            session.start(),
            "[Donations] Failed to start PayPal authentication session. Was it set up correctly?"
        )

        return promise
    }

    private static func makeNewAuthSession(approvalUrl: URL) -> (AuthSession, Promise<WebAuthApprovalParams>) {
        let (promise, future) = Promise<WebAuthApprovalParams>.pending()

        let newSession = AuthSession(approvalUrl: approvalUrl) { approvalParams in
            _liveAuthSession.set(nil)

            if let approvalParams {
                future.resolve(approvalParams)
            } else {
                future.reject(AuthError.userCanceled)
            }
        }

        guard _liveAuthSession.tryToSetIfNil(newSession) else {
            owsFail("[Donations] Unexpectedly tried to create a new PayPal auth session while an existing one is live!")
        }

        return (newSession, promise)
    }
}

// MARK: - Complete the current auth session

private extension Paypal {
    /// Completes the currently-running auth session. Should be called when we
    /// are deep-linked into the app at the completion of the auth flow. See
    /// comments above for more details.
    static func completeAuthSession(withApprovalParams approvalParams: WebAuthApprovalParams?) {
        guard let liveSession = _liveAuthSession.get() else {
            owsFailDebug("[Donations] Attempting to complete auth session, but no live auth session found!")
            return
        }

        liveSession.complete(withApprovalParams: approvalParams)
    }
}

// MARK: - AuthSession

private extension Paypal {
    private class AuthSession: ASWebAuthenticationSession {
        typealias CompletionHandler = (WebAuthApprovalParams?) -> Void

        private let completion: CompletionHandler

        /// Create a new auth session starting at the given URL, with the given
        /// completion handler. A `nil` value passed to the completion handler
        /// indicates that the user canceled the auth flow.
        init(approvalUrl: URL, completion: @escaping CompletionHandler) {
            self.completion = completion

            super.init(
                url: approvalUrl,
                callbackURLScheme: nil
            ) { finalUrl, error in
                Self.completedAllByMyself(finalUrl: finalUrl, error: error, completion: completion)
            }
        }

        func complete(withApprovalParams approvalParams: WebAuthApprovalParams?) {
            cancel()
            completion(approvalParams)
        }

        /// Our auth session should only complete on its own if the user cancels
        /// it interactively, since it can only auto-complete if we are using a
        /// custom URL scheme, which our callback URLs do not.
        private static func completedAllByMyself(
            finalUrl: URL?,
            error: Error?,
            completion: CompletionHandler
        ) {
            owsAssertDebug(
                finalUrl == nil,
                "[Donations] Unexpectedly found non-nil final URL when auth session completed all by itself!"
            )
            owsAssertDebug(
                error != nil,
                "[Donations] Unexpectedly found nil error when auth session completed all by itself!"
            )

            completion(nil)
        }
    }
}

// MARK: - Receiving callback URLs

private extension String {
    static var paypalCallbackScheme: String { Paypal.approvedCallbackUrl.scheme! }
    static var paypalCallbackHost: String { Paypal.approvedCallbackUrl.host! }
    static var paypalCallbackApprovedPath: String { Paypal.approvedCallbackUrl.path }
    static var paypalCallbackCanceledPath: String { Paypal.canceledCallbackUrl.path }
}

@objc
public class PaypalCallbackUrlBridge: NSObject {
    /// If the given URL is a PayPal callback URL, handles it and returns
    /// ``true``. Otherwise, returns ``false``.
    @objc
    static func handlePossibleCallbackUrl(_ url: URL) -> Bool {
        guard let callbackUrlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            owsFailDebug("[Donations] Malformed callback URL!")
            return false
        }

        guard
            callbackUrlComponents.scheme == .paypalCallbackScheme,
            callbackUrlComponents.user == nil,
            callbackUrlComponents.password == nil,
            callbackUrlComponents.host == .paypalCallbackHost,
            callbackUrlComponents.port == nil
        else {
            return false
        }

        let approvalParams: Paypal.WebAuthApprovalParams? = {
            switch callbackUrlComponents.path {
            case .paypalCallbackApprovedPath:
                if
                    let queryItems = callbackUrlComponents.queryItems,
                    let approvalParams = Paypal.WebAuthApprovalParams(queryItems: queryItems)
                {
                    Logger.info("[Donations] Received PayPal approval params, moving forward.")
                    return approvalParams
                } else {
                    owsFailDebug("[Donations] Unexpectedly failed to extract approval params from approved callback URL, canceling.")
                }
            case .paypalCallbackCanceledPath:
                Logger.info("[Donations] Received PayPal cancel.")
            default:
                owsFailDebug("[Donations] Encountered URL that looked like a PayPal callback URL but had an unrecognized path, canceling.")
            }

            return nil
        }()

        Paypal.completeAuthSession(withApprovalParams: approvalParams)
        return true
    }
}
