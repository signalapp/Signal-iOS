//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

// MARK: - Auth

public struct RemoteAttestationAuth: Equatable, Codable {
    public let username: String
    public let password: String

    init(authParamsDict: [String: Any]) throws {
        guard let password = authParamsDict["password"] as? String, !password.isEmpty else {
            throw OWSAssertionError("missing or empty password")
        }

        guard let username = authParamsDict["username"] as? String, !username.isEmpty else {
            throw OWSAssertionError("missing or empty username")
        }

        self.init(username: username, password: password)
    }

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

public struct RemoteAttestationAuthFetcher {

    let networkManager: any NetworkManagerProtocol

    public init(networkManager: any NetworkManagerProtocol) {
        self.networkManager = networkManager
    }

    func fetchAuth(
        forService service: Service,
        chatServiceAuth: ChatServiceAuth,
    ) async throws -> RemoteAttestationAuth {
        var request = service.authRequest()
        request.auth = .identified(chatServiceAuth)
        let response = try await networkManager.asyncRequest(request)

        guard let authParamsDict = response.responseBodyDict else {
            throw OWSAssertionError("Missing or invalid JSON")
        }

        return try RemoteAttestationAuth(authParamsDict: authParamsDict)
    }

    // MARK: - Service

    public enum Service {
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
