//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

public enum RemoteAttestation {}

// MARK: - CSDI

extension RemoteAttestation {
    static func authForCDSI() -> Promise<Auth> {
        return Auth.fetch(forService: .cdsi, auth: .implicit())
    }
}

// MARK: - SVR2

extension RemoteAttestation {
    static func authForSVR2(chatServiceAuth: ChatServiceAuth) -> Promise<Auth> {
        return Auth.fetch(forService: .svr2, auth: chatServiceAuth)
    }
}

// MARK: - Errors

public extension RemoteAttestation {
    enum Error: Swift.Error {
        case assertion(reason: String)
    }
}

private func attestationError(reason: String) -> RemoteAttestation.Error {
    owsFailDebug("Error: \(reason)")
    return .assertion(reason: reason)
}

// MARK: - Auth

public extension RemoteAttestation {
    struct Auth: Dependencies, Equatable, Codable {
        public let username: String
        public let password: String

        public init(authParams: Any) throws {
            guard let authParamsDict = authParams as? [String: Any] else {
                throw attestationError(reason: "Invalid auth response.")
            }

            guard let password = authParamsDict["password"] as? String, !password.isEmpty else {
                throw attestationError(reason: "missing or empty password")
            }

            guard let username = authParamsDict["username"] as? String, !username.isEmpty else {
                throw attestationError(reason: "missing or empty username")
            }

            self.init(username: username, password: password)
        }

        public init(username: String, password: String) {
            self.username = username
            self.password = password
        }
    }
}

fileprivate extension RemoteAttestation.Auth {
    /// - parameter authUsername: If present (alongside authPassword), used in the request.
    ///   If either authUsername or authPassword is missing, uses auth information from TSAccountManager.
    /// - parameter authPassword: If present (alongside authUsername), used in the request.
    ///   If either authUsername or authPassword is missing, uses auth information from TSAccountManager.
    static func fetch(
        forService service: RemoteAttestation.Service,
        auth: ChatServiceAuth
    ) -> Promise<RemoteAttestation.Auth> {
        if DebugFlags.internalLogging {
            Logger.info("service: \(service)")
        }

        let request = service.authRequest()

        switch auth.credentials {
        case .implicit:
            guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
                return Promise(error: OWSGenericError("Not registered."))
            }
        case let .explicit(username, password):
            request.shouldHaveAuthorizationHeaders = true
            request.authUsername = username
            request.authPassword = password
        }

        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            if DebugFlags.internalLogging {
                let statusCode = response.responseStatusCode
                Logger.info("statusCode: \(statusCode)")
                for (header, headerValue) in response.responseHeaders {
                    Logger.info("Header: \(header) -> \(headerValue)")
                }

                #if TESTABLE_BUILD
                HTTPUtils.logCurl(for: request as URLRequest)
                #endif
            }

            guard let json = response.responseBodyJson else {
                throw attestationError(reason: "Missing or invalid JSON")
            }

            return try RemoteAttestation.Auth(authParams: json)
        }.recover(on: DispatchQueue.global()) { error -> Promise<RemoteAttestation.Auth> in
            let statusCode = error.httpStatusCode ?? 0
            Logger.verbose("Remote attestation auth failure: \(statusCode)")
            throw error
        }
    }
}

// MARK: - Service

fileprivate extension RemoteAttestation {
    enum Service {
        case keyBackup
        case cdsi
        case svr2

        func authRequest() -> TSRequest {
            switch self {
            case .keyBackup: return OWSRequestFactory.remoteAttestationAuthRequestForKeyBackup()
            case .cdsi: return OWSRequestFactory.remoteAttestationAuthRequestForCDSI()
            case .svr2: return OWSRequestFactory.remoteAttestationAuthRequestForSVR2()
            }
        }
    }
}
