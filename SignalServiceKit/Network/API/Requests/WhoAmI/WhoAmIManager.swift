//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public protocol WhoAmIManager {
    func makeWhoAmIRequest() async throws -> AccountIdentityResponse
}

struct WhoAmIManagerImpl: WhoAmIManager {

    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    func makeWhoAmIRequest() async throws -> AccountIdentityResponse {
        let response = try await networkManager.asyncRequest(
            WhoAmIRequestFactory.whoAmIRequest(auth: .implicit()),
        )

        guard response.responseStatusCode == 200 else {
            throw response.asError()
        }

        return try JSONDecoder().decode(AccountIdentityResponse.self, from: response.responseBodyData ?? Data())
    }
}

#if TESTABLE_BUILD

class MockWhoAmIManager: WhoAmIManager {
    var whoAmIResponse: ConsumableMockPromise<AccountIdentityResponse> = .unset

    func makeWhoAmIRequest() async throws -> AccountIdentityResponse {
        return try await whoAmIResponse.consumeIntoPromise().awaitable()
    }
}

#endif

// MARK: -

public enum WhoAmIRequestFactory {
    /// Response body should be a `Responses.WhoAmI` json.
    public static func whoAmIRequest(
        auth: ChatServiceAuth,
    ) -> TSRequest {
        var result = TSRequest(
            url: URL(string: "v1/accounts/whoami")!,
            method: "GET",
            parameters: [:],
        )
        result.auth = .identified(auth)
        return result
    }
}
