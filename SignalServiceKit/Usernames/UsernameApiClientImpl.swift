//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit

public class UsernameApiClientImpl: UsernameApiClient {
    private let networkManager: Shims.NetworkManager
    private let schedulers: Schedulers

    init(networkManager: Shims.NetworkManager, schedulers: Schedulers) {
        self.networkManager = networkManager
        self.schedulers = schedulers
    }

    private func performRequest<T>(
        request: TSRequest,
        onSuccess: @escaping (HTTPResponse) throws -> T,
        onFailure: @escaping (Error) throws -> T
    ) -> Promise<T> {
        firstly {
            networkManager.makePromise(request: request)
        }.map(on: schedulers.sharedUserInitiated) { response throws in
            try onSuccess(response)
        }.recover(on: schedulers.sharedUserInitiated) { error throws -> Promise<T> in
                .value(try onFailure(error))
        }
    }

    // MARK: Selection

    public func reserveUsernameCandidates(
        usernameCandidates: Usernames.HashedUsername.GeneratedCandidates
    ) -> Promise<Usernames.ApiClientReservationResult> {
        let request = OWSRequestFactory.reserveUsernameRequest(
            usernameHashes: usernameCandidates.candidateHashes
        )

        func onRequestSuccess(response: HTTPResponse) throws -> Usernames.ApiClientReservationResult {
            guard response.responseStatusCode == 200 else {
                throw OWSAssertionError(
                    "Unexpected status code from successful request: \(response.responseStatusCode)"
                )
            }

            guard let parser = ParamParser(responseObject: response.responseBodyJson) else {
                throw OWSAssertionError(
                    "Unexpectedly missing JSON response body!"
                )
            }

            let usernameHash: String = try parser.required(key: "usernameHash")

            guard let acceptedCandidate = usernameCandidates.candidate(matchingHash: usernameHash) else {
                throw OWSAssertionError(
                    "Accepted username hash did not match any candidates!"
                )
            }

            guard let parsedUsername = Usernames.ParsedUsername(rawUsername: acceptedCandidate.usernameString) else {
                throw OWSAssertionError(
                    "Accepted username was not parseable!"
                )
            }

            return .successful(
                username: parsedUsername,
                hashedUsername: acceptedCandidate
            )
        }

        func onRequestFailure(error: Error) throws -> Usernames.ApiClientReservationResult {
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
            case 413, 429:
                return .rateLimited
            default:
                throw OWSAssertionError("Unexpected status code: \(statusCode)!")
            }
        }

        return performRequest(
            request: request,
            onSuccess: onRequestSuccess,
            onFailure: onRequestFailure
        )
    }

    public func confirmReservedUsername(
        reservedUsername: Usernames.HashedUsername,
        encryptedUsernameForLink: Data
    ) -> Promise<Usernames.ApiClientConfirmationResult> {
        let request = OWSRequestFactory.confirmReservedUsernameRequest(
            reservedUsernameHash: reservedUsername.hashString,
            reservedUsernameZKProof: reservedUsername.proofString,
            encryptedUsernameForLink: encryptedUsernameForLink
        )

        func onRequestSuccess(response: HTTPResponse) throws -> Usernames.ApiClientConfirmationResult {
            guard response.responseStatusCode == 200 else {
                throw OWSAssertionError("Unexpected status code from successful request: \(response.responseStatusCode)")
            }

            guard let parser = ParamParser(responseObject: response.responseBodyJson) else {
                throw OWSAssertionError("Unexpectedly missing JSON response body!")
            }

            let usernameLinkHandle: UUID = try parser.required(key: "usernameLinkHandle")

            return .success(usernameLinkHandle: usernameLinkHandle)
        }

        func onRequestFailure(error: Error) throws -> Usernames.ApiClientConfirmationResult {
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
            case 413, 429:
                return .rateLimited
            default:
                throw OWSAssertionError("Unexpected status code: \(statusCode)")
            }
        }

        return performRequest(
            request: request,
            onSuccess: onRequestSuccess,
            onFailure: onRequestFailure
        )
    }

    // MARK: Deletion

    public func deleteCurrentUsername() -> Promise<Void> {
        let request = OWSRequestFactory.deleteExistingUsernameRequest()

        func onRequestSuccess(response: HTTPResponse) throws {
            guard response.responseStatusCode == 204 else {
                throw OWSAssertionError("Unexpected status code from successful request: \(response.responseStatusCode)")
            }
        }

        func onRequestFailure(error: Error) throws {
            throw error
        }

        return performRequest(
            request: request,
            onSuccess: onRequestSuccess,
            onFailure: onRequestFailure
        )
    }

    // MARK: Lookup

    public func lookupAci(
        forHashedUsername hashedUsername: Usernames.HashedUsername
    ) -> Promise<Aci?> {
        let request = OWSRequestFactory.lookupAciUsernameRequest(
            usernameHashToLookup: hashedUsername.hashString
        )

        func onRequestSuccess(response: HTTPResponse) throws -> Aci {
            guard response.responseStatusCode == 200 else {
                throw OWSAssertionError("Unexpected response code: \(response.responseStatusCode)")
            }

            guard let parser = ParamParser(responseObject: response.responseBodyJson) else {
                throw OWSAssertionError("Unexpectedly missing JSON response body!")
            }

            let aciUuid: UUID = try parser.required(key: "uuid")

            return Aci(fromUUID: aciUuid)
        }

        func onRequestFailure(error: Error) throws -> Aci? {
            guard let statusCode = error.httpStatusCode else {
                owsFailDebug("Unexpectedly missing HTTP status code!")
                throw error
            }

            switch statusCode {
            case 404:
                // If the requested username does not belong to any accounts,
                // we get a 404.
                return nil
            default:
                throw error
            }
        }

        return performRequest(
            request: request,
            onSuccess: onRequestSuccess,
            onFailure: onRequestFailure
        )
    }

    // MARK: Links

    public func setUsernameLink(encryptedUsername: Data) -> Promise<UUID> {
        let request = OWSRequestFactory.setUsernameLinkRequest(
            encryptedUsername: encryptedUsername
        )

        func onRequestSuccess(response: HTTPResponse) throws -> UUID {
            guard response.responseStatusCode == 200 else {
                throw OWSAssertionError("Unexpected response code: \(response.responseStatusCode)")
            }

            guard let parser = ParamParser(responseObject: response.responseBodyJson) else {
                throw OWSAssertionError("Unexpectedly missing JSON response body!")
            }

            return try parser.required(key: "usernameLinkHandle")
        }

        func onRequestFailure(error: Error) throws -> UUID {
            throw error
        }

        return performRequest(
            request: request,
            onSuccess: onRequestSuccess,
            onFailure: onRequestFailure
        )
    }

    public func getUsernameLink(handle: UUID) -> Promise<Data?> {
        let request = OWSRequestFactory.lookupUsernameLinkRequest(handle: handle)

        func onRequestSuccess(response: HTTPResponse) throws -> Data {
            guard response.responseStatusCode == 200 else {
                throw OWSAssertionError("Unexpected response code: \(response.responseStatusCode)")
            }

            guard let parser = ParamParser(responseObject: response.responseBodyJson) else {
                throw OWSAssertionError("Unexpectedly missing JSON response body!")
            }

            let encryptedUsernameString: String = try parser.required(
                key: "usernameLinkEncryptedValue"
            )

            return try Data.data(fromBase64Url: encryptedUsernameString)
        }

        func onRequestFailure(error: Error) throws -> Data? {
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

        return performRequest(
            request: request,
            onSuccess: onRequestSuccess,
            onFailure: onRequestFailure
        )
    }
}

// MARK: - Shims

extension UsernameApiClientImpl {
    enum Shims {
        typealias NetworkManager = _UsernameApiClientImpl_NetworkManager_Shim
    }

    enum Wrappers {
        typealias NetworkManager = _UsernameApiClientImpl_NetworkManager_Wrapper
    }
}

protocol _UsernameApiClientImpl_NetworkManager_Shim {
    func makePromise(request: TSRequest) -> Promise<HTTPResponse>
}

class _UsernameApiClientImpl_NetworkManager_Wrapper: _UsernameApiClientImpl_NetworkManager_Shim {
    private let networkManager: NetworkManager

    init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    func makePromise(request: TSRequest) -> Promise<HTTPResponse> {
        return networkManager.makePromise(request: request)
    }
}
