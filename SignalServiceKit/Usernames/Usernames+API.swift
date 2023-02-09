//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension Usernames {
    /// Manages interactions with username-related APIs.
    struct API {
        private let networkManager: NetworkManager

        public init(networkManager: NetworkManager) {
            self.networkManager = networkManager
        }

        private func performRequest<T>(
            request: TSRequest,
            onSuccess: @escaping (HTTPResponse) throws -> T,
            onFailure: @escaping (Error) throws -> T
        ) -> Promise<T> {
            firstly {
                networkManager.makePromise(request: request)
            }.map(on: DispatchQueue.sharedUserInitiated) { response throws in
                try onSuccess(response)
            }.recover(on: DispatchQueue.sharedUserInitiated) { error throws -> Promise<T> in
                .value(try onFailure(error))
            }
        }
    }
}

// MARK: - Reservation

public extension Usernames.API {
    struct SuccessfulReservation: Equatable {
        /// The reserved username.
        public let username: Usernames.ParsedUsername

        /// The reserved username, hashed.
        public let hashedUsername: Usernames.HashedUsername
    }

    struct ReservationResult {
        public enum State {
            case successful(reservation: SuccessfulReservation)
            case rejected
            case rateLimited
        }

        public let attemptId: UUID
        public let state: State
    }

    struct ReservationError: Error {
        public let attemptId: UUID
        public let underlying: Error
    }

    /// Attempts to reserve the given nickname.
    ///
    /// - Parameter desiredNickname
    /// A non-discriminator-suffixed nickname that the client believes is valid.
    /// - Parameter attemptId
    /// An ID for this attempt, to later disambiguate between multiple
    /// potentially-overlapping attempts.
    func attemptToReserve(
        desiredNickname: String,
        minNicknameLength: UInt32,
        maxNicknameLength: UInt32,
        attemptId: UUID
    ) -> Promise<ReservationResult> {
        func makeReservationError(from error: Error) -> ReservationError {
            .init(attemptId: attemptId, underlying: error)
        }

        let usernameCandidates: [Usernames.HashedUsername]
        do {
            usernameCandidates = try Usernames.HashedUsername.generateCandidates(
                forNickname: desiredNickname,
                minNicknameLength: minNicknameLength,
                maxNicknameLength: maxNicknameLength
            )
        } catch let error {
            return .init(error: makeReservationError(from: error))
        }

        let request = OWSRequestFactory.reserveUsernameRequest(
            usernameHashes: usernameCandidates.map { $0.hashString }
        )

        func onRequestSuccess(response: HTTPResponse) throws -> ReservationResult {
            guard response.responseStatusCode == 200 else {
                throw makeReservationError(from: OWSAssertionError(
                    "Unexpected status code from successful request: \(response.responseStatusCode)"
                ))
            }

            guard let parser = ParamParser(responseObject: response.responseBodyJson) else {
                throw makeReservationError(from: OWSAssertionError(
                    "Unexpectedly missing JSON response body!"
                ))
            }

            let usernameHash: String = try parser.required(key: "usernameHash")

            guard let acceptedCandidate = usernameCandidates.first(where: { candidate in
                candidate.hashString == usernameHash
            }) else {
                throw makeReservationError(from: OWSAssertionError(
                    "Accepted username hash did not match any candidates!"
                ))
            }

            guard let parsedUsername = Usernames.ParsedUsername(rawUsername: acceptedCandidate.usernameString) else {
                throw makeReservationError(from: OWSAssertionError(
                    "Accepted username was not parseable!"
                ))
            }

            return ReservationResult(
                attemptId: attemptId,
                state: .successful(reservation: SuccessfulReservation(
                    username: parsedUsername,
                    hashedUsername: acceptedCandidate
                ))
            )
        }

        func onRequestFailure(error: Error) throws -> ReservationResult {
            guard let statusCode = error.httpStatusCode else {
                throw makeReservationError(from: error)
            }

            let resultState = try { () throws -> ReservationResult.State in
                switch statusCode {
                case 422, 409:
                    // 422 indicates that the given hashes failed to validate.
                    //
                    // 409 indicates that none of the given hashes are available.
                    //
                    // Either way, the reservation has been rejected.
                    return .rejected
                case 413:
                    return .rateLimited
                default:
                    throw makeReservationError(
                        from: OWSAssertionError("Unexpected status code: \(statusCode)!")
                    )
                }
            }()

            return .init(attemptId: attemptId, state: resultState)
        }

        return performRequest(
            request: request,
            onSuccess: onRequestSuccess,
            onFailure: onRequestFailure
        )
    }
}

// MARK: - Confirmation

public extension Usernames.API {
    enum ConfirmationResult {
        /// The reservation was successfully confirmed.
        case success(confirmedUsername: String)
        /// The reservation was rejected. This may be because we no longer hold
        /// the reservation, the reservation lapsed, or something about the
        /// reservation was invalid.
        case rejected
        /// The reservation failed because we have been rate-limited.
        case rateLimited
    }

    func attemptToConfirm(
        reservedUsername: Usernames.HashedUsername
    ) -> Promise<ConfirmationResult> {
        let request = OWSRequestFactory.confirmReservedUsernameRequest(
            reservedUsernameHash: reservedUsername.hashString,
            reservedUsernameZKProof: reservedUsername.proofString
        )

        func onRequestSuccess(response: HTTPResponse) throws -> ConfirmationResult {
            guard response.responseStatusCode == 200 else {
                throw OWSAssertionError("Unexpected status code from successful request: \(response.responseStatusCode)")
            }

            return .success(confirmedUsername: reservedUsername.usernameString)
        }

        func onRequestFailure(error: Error) throws -> ConfirmationResult {
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
            case 413:
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
}

// MARK: - Deletion

public extension Usernames.API {
    func attemptToDeleteCurrentUsername() -> Promise<Void> {
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
}

// MARK: - Lookup

public extension Usernames.API {
    func attemptAciLookup(forUsername username: String) -> Promise<UUID?> {
        let hashedUsername: Usernames.HashedUsername
        do {
            hashedUsername = try Usernames.HashedUsername(forUsername: username)
        } catch let error {
            return .init(error: error)
        }

        let request = OWSRequestFactory.lookupAciUsernameRequest(
            usernameHashToLookup: hashedUsername.hashString
        )

        func onRequestSuccess(response: HTTPResponse) throws -> UUID {
            guard response.responseStatusCode == 200 else {
                throw OWSAssertionError("Unexpected response code: \(response.responseStatusCode)")
            }

            guard let parser = ParamParser(responseObject: response.responseBodyJson) else {
                throw OWSAssertionError("Unexpectedly missing JSON response body!")
            }

            let uuid: UUID = try parser.required(key: "uuid")

            return uuid
        }

        func onRequestFailure(error: Error) throws -> UUID? {
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
}
