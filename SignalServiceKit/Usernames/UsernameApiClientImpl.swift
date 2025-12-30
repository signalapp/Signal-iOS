//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

public class UsernameApiClientImpl: UsernameApiClient {
    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    private func performRequest(
        request: TSRequest,
    ) async throws -> HTTPResponse {
        try await networkManager.asyncRequest(request)
    }

    // MARK: Selection

    public func reserveUsernameCandidates(
        usernameCandidates: Usernames.HashedUsername.GeneratedCandidates,
    ) async throws -> Usernames.ApiClientReservationResult {
        let request = OWSRequestFactory.reserveUsernameRequest(
            usernameHashes: usernameCandidates.candidateHashes,
        )

        do {
            let response = try await performRequest(request: request)

            guard response.responseStatusCode == 200 else {
                throw response.asError()
            }

            guard let parser = response.responseBodyParamParser else {
                throw OWSAssertionError(
                    "Unexpectedly missing JSON response body!",
                )
            }

            let usernameHash: String = try parser.required(key: "usernameHash")

            guard let acceptedCandidate = usernameCandidates.candidate(matchingHash: usernameHash) else {
                throw OWSAssertionError(
                    "Accepted username hash did not match any candidates!",
                )
            }

            guard let parsedUsername = Usernames.ParsedUsername(rawUsername: acceptedCandidate.usernameString) else {
                throw OWSAssertionError(
                    "Accepted username was not parseable!",
                )
            }

            return .successful(
                username: parsedUsername,
                hashedUsername: acceptedCandidate,
            )
        } catch {
            guard let statusCode = error.httpStatusCode else {
                throw error
            }

            switch statusCode {
            case 422, 409:
                // 422 indicates that the given hashes failed to validate.
                //
                // 409 indicates that none of the given hashes are available.
                //
                // Either way, the reservation has been rejected.
                return .rejected
            case 429:
                return .rateLimited
            default:
                throw OWSAssertionError("Unexpected status code: \(statusCode)!")
            }
        }
    }

    public func confirmReservedUsername(
        reservedUsername: Usernames.HashedUsername,
        encryptedUsernameForLink: Data,
        chatServiceAuth: ChatServiceAuth,
    ) async throws -> Usernames.ApiClientConfirmationResult {
        var request = OWSRequestFactory.confirmReservedUsernameRequest(
            reservedUsernameHash: reservedUsername.hashString,
            reservedUsernameZKProof: reservedUsername.proofString,
            encryptedUsernameForLink: encryptedUsernameForLink,
        )
        request.auth = .identified(chatServiceAuth)

        do {
            let response = try await performRequest(request: request)

            guard response.responseStatusCode == 200 else {
                throw response.asError()
            }

            guard let parser = response.responseBodyParamParser else {
                throw OWSAssertionError("Unexpectedly missing JSON response body!")
            }

            let usernameLinkHandle: UUID = try parser.required(key: "usernameLinkHandle")

            return .success(usernameLinkHandle: usernameLinkHandle)
        } catch {
            guard let statusCode = error.httpStatusCode else {
                owsFailDebug("Unexpectedly missing HTTP status code!")
                throw error
            }

            switch statusCode {
            case 409, 410:
                // 409 indicates that we do not actually hold the reservation
                // we thought we did, either because we never did or because we
                // have made a different reservation since.
                //
                // 410 indicates that our reservation has lapsed, and another
                // account has snagged the username - or that the reservation
                // token is invalid.
                //
                // Either way, we've been rejected.
                return .rejected
            case 429:
                return .rateLimited
            default:
                throw OWSAssertionError("Unexpected status code: \(statusCode)")
            }
        }
    }

    // MARK: Deletion

    public func deleteCurrentUsername() async throws {
        let request = OWSRequestFactory.deleteExistingUsernameRequest()
        let response = try await performRequest(request: request)
        guard response.responseStatusCode == 204 else {
            throw response.asError()
        }
    }

    // MARK: Lookup

    public func lookupAci(
        forHashedUsername hashedUsername: Usernames.HashedUsername,
    ) async throws -> Aci? {
        try await DependenciesBridge.shared.chatConnectionManager.withUnauthService(.usernames) {
            try await $0.lookUpUsernameHash(hashedUsername.rawHash)
        }
    }

    // MARK: Links

    public func setUsernameLink(
        encryptedUsername: Data,
        keepLinkHandle: Bool,
    ) async throws -> UUID {
        let request = OWSRequestFactory.setUsernameLinkRequest(
            encryptedUsername: encryptedUsername,
            keepLinkHandle: keepLinkHandle,
        )

        let response = try await performRequest(request: request)

        guard response.responseStatusCode == 200 else {
            throw response.asError()
        }

        guard let parser = response.responseBodyParamParser else {
            throw OWSAssertionError("Unexpectedly missing JSON response body!")
        }

        return try parser.required(key: "usernameLinkHandle")
    }

    public func getUsernameLink(handle: UUID) async throws -> Data? {
        let request = OWSRequestFactory.lookupUsernameLinkRequest(handle: handle)

        do {
            let response = try await performRequest(request: request)

            guard response.responseStatusCode == 200 else {
                throw response.asError()
            }

            guard let parser = response.responseBodyParamParser else {
                throw OWSAssertionError("Unexpectedly missing JSON response body!")
            }

            let encryptedUsernameString: String = try parser.required(
                key: "usernameLinkEncryptedValue",
            )

            return try Data.data(fromBase64Url: encryptedUsernameString)
        } catch {
            guard let statusCode = error.httpStatusCode else {
                owsFailDebug("Unexpectedly missing HTTP status code!")
                throw error
            }

            switch statusCode {
            case 404:
                // If the requested handle does not belong to any username link,
                // we get a 404.
                return nil
            default:
                throw error
            }
        }
    }
}
