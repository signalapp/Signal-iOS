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
            WhoAmIRequestFactory.whoAmIRequest(auth: .implicit())
        )

        guard response.responseStatusCode == 200 else {
            throw OWSAssertionError("Unexpected status code from WhoAmI! \(response.responseStatusCode)")
        }

        guard let bodyData = response.responseBodyData else {
            throw OWSAssertionError("Missing response body data from WhoAmI!")
        }

        do {
            return try JSONDecoder().decode(WhoAmIResponse.self, from: bodyData)
        } catch {
            throw OWSAssertionError("Failed to parse WhoAmI response! \(error)")
        }
    }
}

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
        }

        public enum AmIDeregistered: Int, UnknownEnumCodable {
            case notDeregistered = 200
            case deregistered = 401
            case unexpectedError = -1

            static public var unknown: Self { .unexpectedError }
        }
    }

    /// Response body should be a `Responses.WhoAmI` json.
    public static func whoAmIRequest(
        auth: ChatServiceAuth
    ) -> TSRequest {
        let result = TSRequest(
            url: URL(string: "v1/accounts/whoami")!,
            method: "GET",
            parameters: [:]
        )
        result.shouldHaveAuthorizationHeaders = true
        result.setAuth(auth)
        return result
    }

    /// Usage of this request is limited to checking if the account is deregistered via REST.
    /// This means the result contents are irrelevant; all that matters is if we get a 200, 401, or something else.
    /// See `Responses.AmIDeregistered`
    public static func amIDeregisteredRequest() -> TSRequest {
        let whoAmI = whoAmIRequest(auth: .implicit())

        // As counterintuitive as this is, we want this flag to be false.
        // (As of writing, it defaults to false anyway, but we want to be sure).
        // This flag is what tells us to make _this_ request to check for
        // de-registration, so we don't want to loop forever.
        whoAmI.shouldCheckDeregisteredOn401 = false

        return whoAmI
    }
}
