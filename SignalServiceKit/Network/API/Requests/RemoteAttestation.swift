//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public enum RemoteAttestation {}

// MARK: - CSDI

extension RemoteAttestation {
    static func authForCDSI() async throws -> Auth {
        return try await Auth.fetch(forService: .cdsi, auth: .implicit())
    }
}

// MARK: - SVR2

extension RemoteAttestation {
    static func authForSVR2(chatServiceAuth: ChatServiceAuth) async throws -> Auth {
        return try await Auth.fetch(forService: .svr2, auth: chatServiceAuth)
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
    struct Auth: Equatable, Codable {
        public let username: String
        public let password: String

        public init(authParamsDict: [String: Any]) throws {
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

private extension RemoteAttestation.Auth {
    static func fetch(
        forService service: RemoteAttestation.Service,
        auth: ChatServiceAuth,
    ) async throws -> RemoteAttestation.Auth {
        var request = service.authRequest()
        request.auth = .identified(auth)
        let response = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request)

#if TESTABLE_BUILD
        HTTPUtils.logCurl(for: request)
#endif

        guard let authParamsDict = response.responseBodyDict else {
            throw attestationError(reason: "Missing or invalid JSON")
        }

        return try RemoteAttestation.Auth(authParamsDict: authParamsDict)
    }
}

// MARK: - Service

private extension RemoteAttestation {
    enum Service {
        case cdsi
        case svr2

        func authRequest() -> TSRequest {
            switch self {
            case .cdsi: return OWSRequestFactory.remoteAttestationAuthRequestForCDSI()
            case .svr2: return OWSRequestFactory.remoteAttestationAuthRequestForSVR2()
            }
        }
    }
}
