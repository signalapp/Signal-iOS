//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

public protocol WhoAmIManager {
    typealias WhoAmIResponse = WhoAmIRequestFactory.Responses.WhoAmI

    func makeWhoAmIRequest() async throws -> WhoAmIResponse
}

struct WhoAmIManagerImpl: WhoAmIManager {

    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    func makeWhoAmIRequest() async throws -> WhoAmIResponse {
        let response = try await networkManager.asyncRequest(
            WhoAmIRequestFactory.whoAmIRequest(auth: .implicit()),
        )

        guard response.responseStatusCode == 200 else {
            throw response.asError()
        }

        do {
            return try JSONDecoder().decode(WhoAmIResponse.self, from: response.responseBodyData ?? Data())
        } catch {
            throw OWSAssertionError("Failed to parse WhoAmI response! \(error)")
        }
    }
}

#if TESTABLE_BUILD

class MockWhoAmIManager: WhoAmIManager {
    var whoAmIResponse: ConsumableMockPromise<WhoAmIResponse> = .unset

    func makeWhoAmIRequest() async throws -> WhoAmIResponse {
        return try await whoAmIResponse.consumeIntoPromise().awaitable()
    }
}

#endif

// MARK: -

public enum WhoAmIRequestFactory {

    public enum Responses {
        public struct WhoAmI: Decodable {
            public struct Entitlements: Decodable {
                private enum CodingKeys: String, CodingKey {
                    case backup
                    case badges
                }

                public struct BackupEntitlement: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case backupLevel
                        case expirationSeconds
                    }

                    public let backupLevel: Int
                    public let expirationSeconds: TimeInterval
                }

                public struct BadgeEntitlement: Decodable {
                    private enum CodingKeys: String, CodingKey {
                        case badgeId = "id"
                        case isVisible = "visible"
                        case expirationSeconds
                    }

                    public let badgeId: String
                    public let isVisible: Bool
                    public let expirationSeconds: TimeInterval
                }

                public let backup: BackupEntitlement?
                public let badges: [BadgeEntitlement]
            }

            private enum CodingKeys: String, CodingKey {
                case aci = "uuid"
                case pni
                case e164 = "number"
                case usernameHash
                case entitlements
            }

            @AciUuid public var aci: Aci
            @PniUuid public var pni: Pni
            public let e164: E164
            public let usernameHash: String?
            public let entitlements: Entitlements

#if TESTABLE_BUILD

            static func forUnitTest(aci: Aci, pni: Pni, e164: E164) -> Self {
                return Self(
                    aci: aci,
                    pni: pni,
                    e164: e164,
                    usernameHash: nil,
                    entitlements: Entitlements(backup: nil, badges: []),
                )
            }

            static func forUnitTest(localIdentifiers: LocalIdentifiers) -> Self {
                return forUnitTest(aci: localIdentifiers.aci, pni: localIdentifiers.pni!, e164: E164(localIdentifiers.phoneNumber)!)
            }

#endif
        }
    }

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
