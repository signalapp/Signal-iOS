//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

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
                let result = _authUsername ?? DependenciesBridge.shared.tsAccountManager.storedServerUsernameWithMaybeTransaction
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
                let result = _authPassword ?? DependenciesBridge.shared.tsAccountManager.storedServerAuthTokenWithMaybeTransaction
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

    enum SealedSenderAuth {
        case story
        case accessKey(SMKUDAccessKey)
        case endorsement(GroupSendFullToken)

        var isStory: Bool {
            switch self {
            case .story: true
            case .accessKey, .endorsement: false
            }
        }
    }

    func setAuth(sealedSender: SealedSenderAuth) {
        self.isUDRequest = true
        self.shouldHaveAuthorizationHeaders = false
        switch sealedSender {
        case .story:
            break
        case .accessKey(let accessKey):
            setValue(accessKey.keyData.base64EncodedString(), forHTTPHeaderField: "Unidentified-Access-Key")
        case .endorsement(let fullToken):
            setValue(fullToken.serialize().asData.base64EncodedString(), forHTTPHeaderField: "Group-Send-Token")
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
        var result = "\(self.isUDRequest ? "UD" : "ID") \(self.httpMethod)"
        switch redactionStrategy {
        case .none:
            result += " \(self.url?.relativeString ?? "")"
        case .redactURLForSuccessResponses(let replacementString):
            result += " \(replacementString)"
        }
        if let headerFields = self.allHTTPHeaderFields, !headerFields.isEmpty {
            let formattedHeaderFields = headerFields.keys.sorted().joined(separator: "; ")
            result += " [\(formattedHeaderFields)]"
        }
        return result
    }
}
