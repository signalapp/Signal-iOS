//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import AuthenticationServices
import Foundation

// MARK: - Present a new auth session

/// PayPal donations are authorized by a user via PayPal's web interface,
/// presented in an ``ASWebAuthenticationSession``.
public extension Paypal {
    /// Creates and presents a new auth session.
    @MainActor
    static func presentExpectingApprovalParams<ApprovalParams: FromApprovedPaypalWebAuthFinalUrlQueryItems>(
        approvalUrl: URL,
        withPresentationContext presentationContext: ASWebAuthenticationPresentationContextProviding,
    ) async throws -> ApprovalParams {
        let authSession = AuthSession<ApprovalParams>(approvalUrl: approvalUrl)
        return try await authSession.start(presentationContextProvider: presentationContext)
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
        let paymentToken: String

        /// Represents the query-string keys for the elements we expect to be
        /// present in the callback URL from a successful PayPal authentication.
        private enum QueryKey: String {
            case payerId = "PayerID"
            case paymentToken = "token"
        }

        public init(payerId: String, paymentToken: String) {
            self.payerId = payerId
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
                let paymentToken = queryItemMap[.paymentToken]
            else {
                return nil
            }

            self.payerId = payerId
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
    private class AuthSession<ApprovalParams: FromApprovedPaypalWebAuthFinalUrlQueryItems> {
        private let approvalUrl: URL

        /// Create a new auth session starting at the given URL.
        init(approvalUrl: URL) {
            self.approvalUrl = approvalUrl
        }

        func start(presentationContextProvider: ASWebAuthenticationPresentationContextProviding) async throws -> ApprovalParams {
            var authSession: ASWebAuthenticationSession!
            defer {
                // Stop retaining it once its completion handler is invoked.
                authSession = nil
            }
            return try await withCheckedThrowingContinuation { continuation in
                authSession = ASWebAuthenticationSession(
                    url: approvalUrl,
                    callbackURLScheme: Paypal.authSessionScheme,
                ) { finalUrl, error in
                    /// Our auth session should only complete on its own if the user cancels
                    /// it interactively, since it can only auto-complete if we are using a
                    /// custom URL scheme, which our callback URLs do not.
                    let result: Result<ApprovalParams, any Error>
                    if let finalUrl {
                        owsAssertDebug(error == nil)
                        result = Result(catching: { try Self.complete(withFinalUrl: finalUrl) })
                    } else if let error {
                        result = .failure(Self.complete(withError: error))
                    } else {
                        owsFail("Unexpectedly had neither a final URL nor error!")
                    }
                    continuation.resume(with: result)
                }
                authSession.presentationContextProvider = presentationContextProvider
                let result = authSession.start()
                owsPrecondition(result, "[Donations] Failed to start PayPal authentication session.")
            }
        }

        private static func complete(withFinalUrl finalUrl: URL) throws -> ApprovalParams {
            guard let callbackUrlComponents = URLComponents(url: finalUrl, resolvingAgainstBaseURL: true) else {
                throw OWSAssertionError("[Donations] Malformed callback URL!")
            }

            guard
                callbackUrlComponents.scheme == Paypal.authSessionScheme,
                callbackUrlComponents.user == nil,
                callbackUrlComponents.password == nil,
                callbackUrlComponents.host == Paypal.authSessionHost,
                callbackUrlComponents.port == nil
            else {
                throw OWSAssertionError("[Donations] Callback URL did not match expected!")
            }

            switch callbackUrlComponents.path {
            case Paypal.paymentApprovalPathComponent:
                if
                    let queryItems = callbackUrlComponents.queryItems,
                    let approvalParams = ApprovalParams(fromFinalUrlQueryItems: queryItems)
                {
                    Logger.info("[Donations] Received PayPal approval params, moving forward.")
                    return approvalParams
                } else {
                    throw OWSAssertionError("[Donations] Unexpectedly failed to extract approval params from approved callback URL!")
                }
            case Paypal.paymentCanceledPathComponent:
                Logger.info("[Donations] Received PayPal cancel.")
                throw AuthError.userCanceled
            default:
                throw OWSAssertionError("[Donations] Encountered URL that looked like a PayPal callback URL but had an unrecognized path!")
            }
        }

        private static func complete(withError error: Error) -> any Error {
            guard let authSessionError = error as? ASWebAuthenticationSessionError else {
                return OWSAssertionError("Unexpected error from auth session: \(error)!")
            }

            switch authSessionError.code {
            case .canceledLogin:
                return AuthError.userCanceled
            case
                .presentationContextNotProvided,
                .presentationContextInvalid:
                owsFail("Unexpected issue with presentation context. Was the auth session set up correctly?")
            @unknown default:
                return OWSAssertionError("Unexpected auth sesion error code: \(authSessionError.code)")
            }
        }
    }
}
