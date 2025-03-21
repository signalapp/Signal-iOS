//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

// TODO: Rework to _not_ extend NSMutableURLRequest.
@objcMembers
public class TSRequest: NSMutableURLRequest {
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

    public enum Auth {
        /// A typical identified request, such as "whoami".
        case identified(ChatServiceAuth)

        /// A registration request. These lack ChatServiceAuth (because you need to
        /// register to obtain it), and many of them lack authentication altogether,
        /// but they nevertheless are "identified". They are "identified" because
        /// they must refer to your own account in order to create it.
        case registration((username: String, password: String)?)

        /// An anonymous request with no authentication whatsoever. These requests
        /// must not identify the current user.
        case anonymous

        /// An anonymous request authenticated with a GSE, UAK, or "story=true".
        case sealedSender(SealedSenderAuth)

        /// An anonymous request authenticated with a BackupAuthCredential.
        case messageBackup(MessageBackupServiceAuth)

        var connectionType: OWSChatConnectionType {
            get throws {
                switch self {
                case .identified:
                    return .identified
                case .registration:
                    // TODO: Add support for this when deprecating REST.
                    throw OWSAssertionError("Can't send registration requests via either web socket.")
                case .anonymous, .sealedSender, .messageBackup:
                    return .unidentified
                }
            }
        }

        var logTag: String {
            switch self {
            case .identified, .registration:
                return "ID"
            case .anonymous, .sealedSender, .messageBackup:
                return "UD"
            }
        }
    }

    public var auth: Auth = .identified(.implicit())

    func applyAuth(to httpHeaders: inout HttpHeaders, willSendViaWebSocket: Bool) {
        switch self.auth {
        case .identified(let auth):
            // If it's sent via the web socket, the "auth" is applied when the
            // connection is opened, and thus the value here is ignored.
            if !willSendViaWebSocket {
                switch auth.credentials {
                case .implicit:
                    let tsAccountManager = DependenciesBridge.shared.tsAccountManager
                    let username = tsAccountManager.storedServerUsernameWithMaybeTransaction ?? ""
                    let password = tsAccountManager.storedServerAuthTokenWithMaybeTransaction ?? ""
                    self.setAuth(username: username, password: password, for: &httpHeaders)
                case .explicit(let username, let password):
                    self.setAuth(username: username, password: password, for: &httpHeaders)
                }
            }
        case .registration((let username, let password)?):
            self.setAuth(username: username, password: password, for: &httpHeaders)
        case .registration(nil):
            break
        case .anonymous:
            break
        case .sealedSender(let auth):
            self.setAuth(sealedSender: auth, for: &httpHeaders)
        case .messageBackup(let auth):
            auth.apply(to: &httpHeaders)
        }
    }

    private func setAuth(username: String, password: String, for httpHeaders: inout HttpHeaders) {
        owsAssertDebug(!username.isEmpty)
        owsAssertDebug(!password.isEmpty)
        httpHeaders.addAuthHeader(username: username, password: password)
    }

    public enum SealedSenderAuth {
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

    private func setAuth(sealedSender: SealedSenderAuth, for httpHeaders: inout HttpHeaders) {
        switch sealedSender {
        case .story:
            break
        case .accessKey(let accessKey):
            httpHeaders.addHeader("Unidentified-Access-Key", value: accessKey.keyData.base64EncodedString(), overwriteOnConflict: true)
        case .endorsement(let fullToken):
            httpHeaders.addHeader("Group-Send-Token", value: fullToken.serialize().asData.base64EncodedString(), overwriteOnConflict: true)
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
        var result = "\(self.auth.logTag) \(self.httpMethod)"
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
