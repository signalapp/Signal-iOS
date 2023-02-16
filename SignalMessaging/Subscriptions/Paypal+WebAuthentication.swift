//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import AuthenticationServices
import Foundation

// MARK: - Present a new auth session

/// PayPal donations are authorized by a user via PayPal's web interface,
/// presented in an ``ASWebAuthenticationSession``.
public extension Paypal {
    /// On iOS 13+, we are required to hold a strong reference to any
    /// in-progress ``ASWebAuthenticationSession``s.
    private static let _runningAuthSession: AtomicOptional<ASWebAuthenticationSession> = AtomicOptional(nil)

    /// Creates and presents a new auth session. Only one auth session should
    /// be able to exist at once.
    ///
    /// On iOS 13+, a `presentationContext` is required.
    @available(iOS 13, *)
    static func presentExpectingApprovalParams<ApprovalParams: FromApprovedPaypalWebAuthFinalUrlQueryItems>(
        approvalUrl: URL,
        withPresentationContext presentationContext: ASWebAuthenticationPresentationContextProviding
    ) -> Promise<ApprovalParams> {
        let (session, promise): (AuthSession<ApprovalParams>, Promise<ApprovalParams>) = makeNewAuthSession(
            approvalUrl: approvalUrl
        )

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
    static func presentExpectingApprovalParams<ApprovalParams: FromApprovedPaypalWebAuthFinalUrlQueryItems>(
        approvalUrl: URL
    ) -> Promise<ApprovalParams> {
        let (session, promise): (AuthSession<ApprovalParams>, Promise<ApprovalParams>) = makeNewAuthSession(
            approvalUrl: approvalUrl
        )

        owsAssert(
            session.start(),
            "[Donations] Failed to start PayPal authentication session. Was it set up correctly?"
        )

        return promise
    }

    private static func makeNewAuthSession<ApprovalParams: FromApprovedPaypalWebAuthFinalUrlQueryItems>(
        approvalUrl: URL
    ) -> (AuthSession<ApprovalParams>, Promise<ApprovalParams>) {
        let (promise, future) = Promise<ApprovalParams>.pending()

        let newSession = AuthSession<ApprovalParams>(approvalUrl: approvalUrl) { approvalResult in
            _runningAuthSession.set(nil)

            switch approvalResult {
            case let .approved(params):
                future.resolve(params)
            case .canceled:
                future.reject(AuthError.userCanceled)
            case let .error(error):
                future.reject(error)
            }
        }

        guard _runningAuthSession.tryToSetIfNil(newSession) else {
            owsFail("Unexpectedly found existing auth session while creating a new one! This should be impossible.")
        }

        return (newSession, promise)
    }
}

// MARK: - Callback URLs

/// We present an auth session beginning at a PayPal URL we fetch from our
/// service. However, the callback URLs that PayPal will complete our session
/// with do not use a custom URL scheme (and instead use `https`), due to
/// restrictions from PayPal. Consequently, the callback URLs we give to PayPal
/// should redirect to custom-scheme URLs, which will complete the session.
extension Paypal {
    /// The scheme used in PayPal callback URLs. Required by PayPal to be
    /// `https`.
    private static let redirectUrlScheme: String = "https"

    /// The host used in PayPal callback URLs.
    private static let redirectUrlHost: String = "signaldonations.org"

    /// A path component used in PayPal callback URLs that will tell the server
    /// to redirect us to the `sgnl://` custom scheme with all path and query
    /// components after `/redirect`.
    ///
    /// For example, the URL `https://signaldonations.org/redirect/whatever?foo=bar`
    /// will be redirected by the server to `sgnl://whatever?foo=bar`.
    private static let paymentRedirectPathComponent: String = "/redirect/\(authSessionHost)"

    /// A path component used in PayPal callback URLs to indicate that the user
    /// approved payment.
    private static let paymentApprovalPathComponent: String = "/approved"

    /// A path component used in PayPal callback URLs to indicate that the user
    /// canceled payment.
    private static let paymentCanceledPathComponent: String = "/canceled"

    /// The URL PayPal will redirect the user to after a successful web
    /// authentication and payment approval. Passed while setting up web
    /// authentication.
    ///
    /// This URL is expected to redirect to a custom scheme URL. See
    /// ``paymentRedirectPathComponent`` for more.
    static let webAuthReturnUrl: URL = {
        var components = URLComponents()
        components.scheme = redirectUrlScheme
        components.host = redirectUrlHost
        components.path = paymentRedirectPathComponent + paymentApprovalPathComponent

        return components.url!
    }()

    /// The URL PayPal will redirect the user to after a canceled web
    /// authentication. Passed while setting up web authentication.
    ///
    /// This URL is expected to redirect to a custom scheme URL. See
    /// ``paymentRedirectPathComponent`` for more.
    static let webAuthCancelUrl: URL = {
        var components = URLComponents()
        components.scheme = redirectUrlScheme
        components.host = redirectUrlHost
        components.path = paymentRedirectPathComponent + paymentCanceledPathComponent

        return components.url!
    }()

    /// The scheme for the URL we expect to be redirected to by our `https`
    /// PayPal callback URLs.
    ///
    /// See ``paymentRedirectPathComponent`` for more.
    ///
    /// Per ``ASWebAuthenticationSession``'s documentation [here][0], even if
    /// other apps register this scheme the auth session will ensure that they
    /// are not invoked (so we are the only ones to capture the callback).
    ///
    /// [0]: https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession
    private static let authSessionScheme: String = "sgnl"

    /// The host for the URL we expect to be redirected to by our `https`
    /// PayPal callback URLs. See ``paymentRedirectPathComponent``.
    private static let authSessionHost: String = "paypal-payment"

    /// The URL we expect to be redirected to by ``approvalUrl``.
    ///
    /// See ``paymentRedirectPathComponent`` for more.
    private static let authSessionApprovalCallbackUrl: URL = {
        var components = URLComponents()
        components.scheme = authSessionScheme
        components.host = authSessionHost
        components.path = paymentApprovalPathComponent

        return components.url!
    }()

    /// The URL we expect to be redirected to by ``cancelUrl``.
    ///
    /// See ``paymentRedirectPathComponent`` for more.
    private static let authSessionCancelCallbackUrl: URL = {
        var components = URLComponents()
        components.scheme = authSessionScheme
        components.host = authSessionHost
        components.path = paymentCanceledPathComponent

        return components.url!
    }()
}

// MARK: - Auth results

/// Represents a type that may be constructable from a given set of URL query
/// items retrieved from the final URL from a successfully-completed PayPal web
/// auth session.
public protocol FromApprovedPaypalWebAuthFinalUrlQueryItems {
    /// Init using the given URL query items, retrieved from the final URL from
    /// a successfully-completed PayPal web auth session. Returns `nil` if
    /// initialization is not possible, e.g. a required query item is missing.
    init?(fromFinalUrlQueryItems queryItems: [URLQueryItem])
}

public extension Paypal {
    /// Represents parameters returned to us after an approved PayPal
    /// authentication for a one-time payment, which are used to confirm
    /// the payment. These fields are opaque to us.
    struct OneTimePaymentWebAuthApprovalParams: FromApprovedPaypalWebAuthFinalUrlQueryItems {
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

        public init(payerId: String, paymentId: String, paymentToken: String) {
            self.payerId = payerId
            self.paymentId = paymentId
            self.paymentToken = paymentToken
        }

        public init?(fromFinalUrlQueryItems queryItems: [URLQueryItem]) {
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

    /// Represents parameters returned to us after an approved PayPal
    /// authentication for a monthly payment.
    ///
    /// In practice, we do not need any data returned from the PayPal
    /// authentication.
    struct MonthlyPaymentWebAuthApprovalParams: FromApprovedPaypalWebAuthFinalUrlQueryItems {
        public init?(fromFinalUrlQueryItems queryItems: [URLQueryItem]) {}
    }

    /// Represents an error returned from web authentication.
    enum AuthError: Error {
        case userCanceled
    }
}

// MARK: - AuthSession

private extension Paypal {
    private class AuthSession<ApprovalParams: FromApprovedPaypalWebAuthFinalUrlQueryItems>: ASWebAuthenticationSession {
        enum AuthResult {
            case approved(ApprovalParams)
            case canceled
            case error(Error)
        }

        typealias CompletionHandler = (AuthResult) -> Void

        /// Create a new auth session starting at the given URL, with the given
        /// completion handler. A `nil` value passed to the completion handler
        /// indicates that the user canceled the auth flow.
        init(approvalUrl: URL, completion: @escaping CompletionHandler) {
            super.init(
                url: approvalUrl,
                callbackURLScheme: Paypal.authSessionScheme
            ) { finalUrl, error in
                Self.onCompleted(finalUrl: finalUrl, error: error, completion: completion)
            }
        }

        /// Our auth session should only complete on its own if the user cancels
        /// it interactively, since it can only auto-complete if we are using a
        /// custom URL scheme, which our callback URLs do not.
        private static func onCompleted(
            finalUrl: URL?,
            error: Error?,
            completion: CompletionHandler
        ) {
            if let finalUrl {
                owsAssertDebug(error == nil)
                complete(withFinalUrl: finalUrl, completion: completion)
            } else if let error {
                complete(withError: error, completion: completion)
            } else {
                owsFail("Unexpectedly had neither a final URL nor error!")
            }
        }

        private static func complete(withFinalUrl finalUrl: URL, completion: CompletionHandler) {
            guard let callbackUrlComponents = URLComponents(url: finalUrl, resolvingAgainstBaseURL: true) else {
                completion(.error(OWSAssertionError("[Donations] Malformed callback URL!")))
                return
            }

            guard
                callbackUrlComponents.scheme == Paypal.authSessionScheme,
                callbackUrlComponents.user == nil,
                callbackUrlComponents.password == nil,
                callbackUrlComponents.host == Paypal.authSessionHost,
                callbackUrlComponents.port == nil
            else {
                completion(.error(OWSAssertionError("[Donations] Callback URL did not match expected!")))
                return
            }

            let authResult: AuthResult = {
                switch callbackUrlComponents.path {
                case Paypal.paymentApprovalPathComponent:
                    if
                        let queryItems = callbackUrlComponents.queryItems,
                        let approvalParams = ApprovalParams(fromFinalUrlQueryItems: queryItems)
                    {
                        Logger.info("[Donations] Received PayPal approval params, moving forward.")
                        return .approved(approvalParams)
                    } else {
                        return .error(OWSAssertionError("[Donations] Unexpectedly failed to extract approval params from approved callback URL!"))
                    }
                case Paypal.paymentCanceledPathComponent:
                    Logger.info("[Donations] Received PayPal cancel.")
                    return .canceled
                default:
                    return .error(OWSAssertionError("[Donations] Encountered URL that looked like a PayPal callback URL but had an unrecognized path!"))
                }
            }()

            completion(authResult)
        }

        private static func complete(withError error: Error, completion: CompletionHandler) {
            guard let authSessionError = error as? ASWebAuthenticationSessionError else {
                completion(.error(OWSAssertionError("Unexpected error from auth session: \(error)!")))
                return
            }

            switch authSessionError.code {
            case .canceledLogin:
                completion(.canceled)
            case
                    .presentationContextNotProvided,
                    .presentationContextInvalid:
                owsFail("Unexpected issue with presentation context. Was the auth session set up correctly?")
            @unknown default:
                completion(.error(OWSAssertionError("Unexpected auth session error code: \(authSessionError.code)")))
            }
        }
    }
}
