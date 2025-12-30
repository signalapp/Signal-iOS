//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc
public enum RequestMakerUDAuthError: Int, Error, IsRetryableProvider {
    case udAuthFailure

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool {
        switch self {
        case .udAuthFailure:
            return true
        }
    }
}

// MARK: -

public struct RequestMakerResult {
    public let response: HTTPResponse
    public let wasSentByUD: Bool
}

/// A utility class that handles:
///
/// - Retrying UD requests that fail due to 401/403 errors.
final class RequestMaker {

    struct Options: OptionSet {
        let rawValue: Int

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// If the initial request is unidentified and that fails, send the request
        /// again as an identified request.
        static let allowIdentifiedFallback = Options(rawValue: 1 << 0)

        /// This RequestMaker is used when fetching profiles, so it shouldn't kick
        /// off additional profile fetches when errors occur.
        static let isProfileFetch = Options(rawValue: 1 << 1)
    }

    private let label: String
    private let serviceId: ServiceId
    private let address: SignalServiceAddress
    private let canUseStoryAuth: Bool
    private let accessKey: OWSUDAccess?
    private let endorsement: GroupSendFullTokenBuilder?
    private let authedAccount: AuthedAccount
    private let options: Options

    init(
        label: String,
        serviceId: ServiceId,
        canUseStoryAuth: Bool,
        accessKey: OWSUDAccess?,
        endorsement: GroupSendFullTokenBuilder?,
        authedAccount: AuthedAccount,
        options: Options,
    ) {
        self.label = label
        self.serviceId = serviceId
        self.address = SignalServiceAddress(serviceId)
        self.canUseStoryAuth = canUseStoryAuth
        self.accessKey = accessKey
        self.endorsement = endorsement
        self.authedAccount = authedAccount
        self.options = options
    }

    private enum SealedSenderAuth {
        case story
        case accessKey(OWSUDAccess)
        case endorsement(GroupSendFullToken)

        func toRequestAuth() -> TSRequest.SealedSenderAuth {
            switch self {
            case .story: .story
            case .accessKey(let udAccess): .accessKey(udAccess.key)
            case .endorsement(let endorsement): .endorsement(endorsement)
            }
        }
    }

    /// Invokes `block` with each available authentication mechanism.
    ///
    /// The `block` is always invoked at least once, and it may be invoked
    /// multiple times when Sealed Sender auth errors occur.
    private func forEachAuthMechanism<T>(block: (SealedSenderAuth?) async throws -> T) async throws -> T {
        var authMechanisms: [() -> SealedSenderAuth?]
        if canUseStoryAuth {
            authMechanisms = [{ .story }]
            owsAssertDebug(!self.options.contains(.allowIdentifiedFallback))
        } else {
            authMechanisms = [
                accessKey.map({ accessKey in { .accessKey(accessKey) } }),
                endorsement.map({ endorsement in { .endorsement(endorsement.build()) } }),
            ].compacted()
            if authMechanisms.isEmpty || self.options.contains(.allowIdentifiedFallback) {
                authMechanisms.append({ nil })
            }
        }

        var mostRecentError: (any Error)?
        for authMechanism in authMechanisms {
            do {
                return try await block(authMechanism())
            } catch {
                mostRecentError = error
                switch error {
                case RequestMakerUDAuthError.udAuthFailure:
                    continue
                default:
                    throw error
                }
            }
        }

        // We must run the loop at least once, and we either exit successfully or
        // set `mostRecentError` to some value.
        owsPrecondition(!authMechanisms.isEmpty)
        throw mostRecentError!
    }

    func makeRequest(requestBlock: (TSRequest.SealedSenderAuth?) throws -> TSRequest) async throws -> RequestMakerResult {
        return try await self.forEachAuthMechanism { sealedSenderAuth in
            do {
                let request = try requestBlock(sealedSenderAuth?.toRequestAuth())
                let isUDRequest: Bool
                switch request.auth {
                case .identified, .registration:
                    isUDRequest = false
                case .anonymous, .sealedSender, .backup:
                    isUDRequest = true
                }
                owsPrecondition(isUDRequest == (sealedSenderAuth != nil))

                let result = try await self._makeRequest(request: request)
                await requestSucceeded(sealedSenderAuth: sealedSenderAuth)
                return result
            } catch {
                try await requestFailed(error: error, sealedSenderAuth: sealedSenderAuth)
            }
        }
    }

    private func _makeRequest(request: TSRequest) async throws -> RequestMakerResult {
        let connectionType = try request.auth.connectionType
        let networkManager = SSKEnvironment.shared.networkManagerRef
        let response = try await networkManager.asyncRequest(request)
        return RequestMakerResult(response: response, wasSentByUD: connectionType == .unidentified)
    }

    private func requestFailed(error: Error, sealedSenderAuth: SealedSenderAuth?) async throws -> Never {
        if let sealedSenderAuth, error.httpStatusCode == 401 || error.httpStatusCode == 403 {
            // If an Access Key-authenticated request fails because of a 401/403, we
            // assume the Access Key is wrong.
            if case .accessKey(let udAccess) = sealedSenderAuth {
                await updateUdAccessMode({
                    switch udAccess.mode {
                    case .unrestricted:
                        // If it was unrestricted, we *might* have the right profile key.
                        return .unknown
                    case .unknown, .enabled:
                        // If it was unknown, we may have tried the real key (if we had it) or a
                        // random key. In either of these cases, we don't want to try again because
                        // it won't work.
                        return .disabled
                    }
                }())
            }

            throw RequestMakerUDAuthError.udAuthFailure
        }
        throw error
    }

    private func requestSucceeded(sealedSenderAuth: SealedSenderAuth?) async {
        // If this was an Access Key-authed request for an "unknown" user...
        if case .accessKey(let udAccess) = sealedSenderAuth, udAccess.mode == .unknown {
            // ...fetch their profile since we know udAccessMode is out of date.
            fetchProfileIfNeeded()
        }
    }

    private func updateUdAccessMode(_ newValue: UnidentifiedAccessMode) async {
        guard let aci = self.serviceId as? Aci else {
            owsFailDebug("Can't use UAKs with PNIs")
            return
        }
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            SSKEnvironment.shared.udManagerRef.setUnidentifiedAccessMode(newValue, for: aci, tx: tx)
        }
        fetchProfileIfNeeded()
    }

    private func fetchProfileIfNeeded() {
        // If this request isn't a profile fetch, kick off a profile fetch. If it
        // is a profile fetch, don't bother fetching it *again*.
        if self.options.contains(.isProfileFetch) {
            return
        }
        Task { [serviceId, authedAccount] in
            let profileFetcher = SSKEnvironment.shared.profileFetcherRef
            _ = try? await profileFetcher.fetchProfile(
                for: serviceId,
                authedAccount: authedAccount,
            )
        }
    }
}
