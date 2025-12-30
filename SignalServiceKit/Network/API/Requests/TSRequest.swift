//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct TSRequest: CustomDebugStringConvertible {
    public let url: URL
    public let method: String
    public var headers: HttpHeaders
    public var body: Body
    public var timeoutInterval: TimeInterval = OWSRequestFactory.textSecureHTTPTimeOut
    public let logger: PrefixedLogger

    public enum Body {
        case parameters([String: Any])
        case data(Data)

        static func encodedParameters(_ parameters: [String: Any]) throws -> Data {
            return try JSONSerialization.data(withJSONObject: parameters, options: [])
        }
    }

    public init(
        url: URL,
        method: String = "GET",
        parameters: [String: Any]? = [:],
        logger: PrefixedLogger? = nil,
    ) {
        self.init(
            url: url,
            method: method,
            body: .parameters(parameters ?? [:]),
            logger: logger,
        )
    }

    public init(
        url: URL,
        method: String,
        body: Body,
        logger: PrefixedLogger? = nil,
    ) {
        owsAssertDebug(method.isEmpty.negated)

        self.url = url
        self.method = method
        self.headers = HttpHeaders()
        self.body = body
        self.logger = logger ?? .empty()
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
        case backup(BackupServiceAuth)

        var connectionType: OWSChatConnectionType {
            get throws {
                switch self {
                case .identified:
                    return .identified
                case .registration:
                    // TODO: Migrate registration requests to LibSignal.
                    throw OWSAssertionError("Can't send registration requests via either web socket.")
                case .anonymous, .sealedSender, .backup:
                    return .unidentified
                }
            }
        }

        var logTag: String {
            switch self {
            case .identified, .registration:
                return "ID"
            case .anonymous, .sealedSender, .backup:
                return "UD"
            }
        }
    }

    public var auth: Auth = .identified(.implicit())

    private struct ResolvedAuth: Equatable {
        var username: String
        var password: String
    }

    private func resolveAuth(_ chatServiceAuth: ChatServiceAuth) -> ResolvedAuth {
        switch chatServiceAuth.credentials {
        case .implicit:
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            let username = tsAccountManager.storedServerUsernameWithMaybeTransaction ?? ""
            let password = tsAccountManager.storedServerAuthTokenWithMaybeTransaction ?? ""
            return ResolvedAuth(username: username, password: password)
        case .explicit(let username, let password):
            return ResolvedAuth(username: username, password: password)
        }
    }

    func applyAuth(to httpHeaders: inout HttpHeaders, socketAuth: ChatServiceAuth?) throws {
        switch self.auth {
        case .identified(let requestAuth):
            if let socketAuth {
                guard resolveAuth(requestAuth) == resolveAuth(socketAuth) else {
                    throw OWSGenericError("Can't send request with \(requestAuth.logString) auth when the socket uses \(socketAuth.logString) auth")
                }
            } else {
                self.setAuth(resolveAuth(requestAuth), for: &httpHeaders)
            }
        case .registration((let username, let password)?):
            self.setAuth(ResolvedAuth(username: username, password: password), for: &httpHeaders)
        case .registration(nil):
            break
        case .anonymous:
            break
        case .sealedSender(let auth):
            self.setAuth(sealedSender: auth, for: &httpHeaders)
        case .backup(let auth):
            auth.apply(to: &httpHeaders)
        }
    }

    private func setAuth(_ auth: ResolvedAuth, for httpHeaders: inout HttpHeaders) {
        owsAssertDebug(!auth.username.isEmpty)
        owsAssertDebug(!auth.password.isEmpty)
        httpHeaders.addAuthHeader(username: auth.username, password: auth.password)
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
            httpHeaders.addHeader("Group-Send-Token", value: fullToken.serialize().base64EncodedString(), overwriteOnConflict: true)
        }
    }

    public enum RedactionStrategy {
        case none
        case redactURL(replacement: String = "[REDACTED]")
    }

    private var redactionStrategy = RedactionStrategy.none

    public mutating func applyRedactionStrategy(_ strategy: RedactionStrategy) {
        self.redactionStrategy = strategy
    }

    public var debugDescription: String {
        var result = "\(self.auth.logTag) \(self.method)"
        switch redactionStrategy {
        case .none:
            result += " \(self.url.relativeString)"
        case .redactURL(let replacement):
            result += " \(replacement)"
        }
        if !self.headers.headers.isEmpty {
            let formattedHeaderFields = self.headers.headers.keys.sorted().joined(separator: "; ")
            result += " [\(formattedHeaderFields)]"
        }
        return result
    }

#if TESTABLE_BUILD
    var parameters: [String: Any] {
        switch body {
        case .data:
            fatalError()
        case .parameters(let bodyParameters):
            return bodyParameters
        }
    }
#endif
}
