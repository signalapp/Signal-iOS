//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// TODO: Rework to _not_ extend NSMutableURLRequest.
@objcMembers
public class TSRequest: NSMutableURLRequest {
    public var isUDRequest: Bool = false
    public var shouldHaveAuthorizationHeaders: Bool = true

    /// If true, an HTTP 401 will trigger a follow up request to see if the account is deregistered.
    /// If it is, the account will be marked as de-registered.
    ///
    /// - Warning: This only applies to REST requests. We handle HTTP 403 errors
    /// (*not* HTTP 401) for web sockets during the initial handshake, not
    /// during the processing for individual requests.
    public var shouldCheckDeregisteredOn401: Bool = false

    public let parameters: [String: Any]

    public init(url: URL) {
        parameters = [:]
        super.init(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: OWSRequestFactory.textSecureHTTPTimeOut
        )
    }

    public init(url: URL, method: String, parameters: [String: Any]?) {
        owsAssertDebug(method.isEmpty.negated)

        self.parameters = parameters ?? [:]
        super.init(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: OWSRequestFactory.textSecureHTTPTimeOut
        )
        self.httpMethod = method
    }

    @objc(requestWithUrl:method:parameters:)
    public static func request(url: URL, method: String, paramters: [String: Any]?) -> TSRequest {
        return TSRequest(url: url, method: method, parameters: paramters)
    }

    @available(*, unavailable)
    public override init(url: URL, cachePolicy: NSURLRequest.CachePolicy, timeoutInterval: TimeInterval) {
        fatalError()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) unavailable")
    }

    // MARK: - Authorization

    private let authLock = UnfairLock()

    private var _authUsername: String?
    public var authUsername: String? {
        get {
            owsAssertDebug(shouldHaveAuthorizationHeaders)
            return authLock.withLock {
                let result = _authUsername ?? self.tsAccountManager.storedServerUsername
                if result.isEmptyOrNil {
                    Logger.verbose(self.debugDescription)
                }
                owsAssertDebug(result.isEmptyOrNil.negated)
                return result
            }
        }
        set {
            owsAssertDebug(shouldHaveAuthorizationHeaders)
            authLock.withLock {
                _authUsername = newValue
            }
        }
    }

    private var _authPassword: String?
    public var authPassword: String? {
        get {
            owsAssertDebug(shouldHaveAuthorizationHeaders)
            return authLock.withLock {
                let result = _authPassword ?? self.tsAccountManager.storedServerAuthToken
                if result.isEmptyOrNil {
                    Logger.verbose(self.debugDescription)
                }
                owsAssertDebug(result.isEmptyOrNil.negated)
                return result
            }
        }
        set {
            owsAssertDebug(shouldHaveAuthorizationHeaders)
            authLock.withLock {
                _authPassword = newValue
            }
        }
    }

    public enum RedactionStrategy {
        case none
        /// Error responses must be separately handled
        case redactURLForSuccessResponses(replacementString: String = "[REDACTED]")
    }

    private var redactionStrategy = RedactionStrategy.none

    public func applyRedactionStrategy(_ strategy: RedactionStrategy) {
        self.redactionStrategy = strategy
    }

    public func objc_applySuccessResponsesURLRedactionStrategy() {
        self.applyRedactionStrategy(.redactURLForSuccessResponses())
    }

    public override var description: String {
        switch redactionStrategy {
        case .none:
            return "{ \(self.httpMethod): \(String(describing: self.url)) }"
        case .redactURLForSuccessResponses(let replacementString):
            return "{ \(self.httpMethod): \(replacementString) }"
        }
    }
}
