//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

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

public enum RequestMakerError: Error {
    case requestCreationFailed
}

// MARK: -

public struct RequestMakerResult {
    public let response: HTTPResponse
    public let wasSentByUD: Bool
    public let wasSentByWebsocket: Bool

    public var responseJson: Any? {
        response.responseBodyJson
    }
}

/// A utility class that handles:
///
/// - Sending via Web Socket or REST, depending on the process (main app vs.
/// NSE) & whether or not we're connected.
///
/// - Retrying UD requests that fail due to 401/403 errors.
public final class RequestMaker: Dependencies {

    public typealias RequestFactoryBlock = (SMKUDAccessKey?) -> TSRequest?
    public typealias UDAuthFailureBlock = () -> Void

    public struct Options: OptionSet {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// If the initial request uses UD and that fails, send the request again as
        /// an identified request.
        static let allowIdentifiedFallback = Options(rawValue: 1 << 0)

        /// This RequestMaker is used when fetching profiles, so it shouldn't kick
        /// off additional profile fetches when errors occur.
        static let isProfileFetch = Options(rawValue: 1 << 1)

        /// This request can't be sent over a web socket, so don't bother trying.
        static let skipWebSocket = Options(rawValue: 1 << 2)
    }

    private let label: String
    private let requestFactoryBlock: RequestFactoryBlock
    private let udAuthFailureBlock: UDAuthFailureBlock
    private let serviceId: ServiceId
    private let address: SignalServiceAddress
    private let udAccess: OWSUDAccess?
    private let authedAccount: AuthedAccount
    private let options: Options

    public init(
        label: String,
        requestFactoryBlock: @escaping RequestFactoryBlock,
        udAuthFailureBlock: @escaping UDAuthFailureBlock,
        serviceId: ServiceId,
        udAccess: OWSUDAccess?,
        authedAccount: AuthedAccount,
        options: Options
    ) {
        self.label = label
        self.requestFactoryBlock = requestFactoryBlock
        self.udAuthFailureBlock = udAuthFailureBlock
        self.serviceId = serviceId
        self.address = SignalServiceAddress(serviceId)
        self.udAccess = udAccess
        self.authedAccount = authedAccount
        self.options = options
    }

    public func makeRequest() -> Promise<RequestMakerResult> {
        return makeRequestInternal(skipUD: false)
    }

    private func makeRequestInternal(skipUD: Bool) -> Promise<RequestMakerResult> {
        let udAccess: OWSUDAccess? = skipUD ? nil : self.udAccess
        let isUDRequest: Bool = udAccess != nil
        guard let request: TSRequest = requestFactoryBlock(udAccess?.udAccessKey) else {
            return Promise(error: RequestMakerError.requestCreationFailed)
        }
        owsAssertDebug(isUDRequest == request.isUDRequest)

        let shouldUseWebsocket: Bool
        if FeatureFlags.deprecateREST {
            shouldUseWebsocket = true
        } else {
            let webSocketType: OWSWebSocketType = (isUDRequest ? .unidentified : .identified)
            shouldUseWebsocket = (
                !options.contains(.skipWebSocket)
                && OWSWebSocket.canAppUseSocketsToMakeRequests
                && socketManager.canMakeRequests(webSocketType: webSocketType)
            )
        }

        if shouldUseWebsocket {
            return firstly {
                socketManager.makeRequestPromise(request: request)
            }.map(on: DispatchQueue.global()) { response in
                self.requestSucceeded(udAccess: udAccess)
                return RequestMakerResult(response: response, wasSentByUD: isUDRequest, wasSentByWebsocket: true)
            }.recover(on: DispatchQueue.global()) { (error: Error) -> Promise<RequestMakerResult> in
                return try self.requestFailed(error: error, udAccess: udAccess)
            }
        } else {
            return firstly {
                networkManager.makePromise(request: request)
            }.map(on: DispatchQueue.global()) { (response: HTTPResponse) -> RequestMakerResult in
                self.requestSucceeded(udAccess: udAccess)
                return RequestMakerResult(response: response, wasSentByUD: isUDRequest, wasSentByWebsocket: false)
            }.recover(on: DispatchQueue.global()) { (error: Error) -> Promise<RequestMakerResult> in
                return try self.requestFailed(error: error, udAccess: udAccess)
            }
        }
    }

    private func requestFailed(error: Error, udAccess: OWSUDAccess?) throws -> Promise<RequestMakerResult> {
        if let udAccess, (error.httpStatusCode == 401 || error.httpStatusCode == 403) {
            // If a UD request fails due to service response (as opposed to network
            // failure), mark recipient as _not_ in UD mode, then retry.
            let newUdAccessMode: UnidentifiedAccessMode = {
                switch udAccess.udAccessMode {
                case .unrestricted:
                    // If it was unrestricted, we *might* have the right profile key.
                    return .unknown
                case .unknown, .enabled, .disabled:
                    // If it was unknown, we may have tried the real key (if we had it) or a
                    // random key. In either of these cases, we don't want to try again because
                    // it won't work.
                    return .disabled
                }
            }()
            databaseStorage.write { tx in
                self.udManager.setUnidentifiedAccessMode(newUdAccessMode, for: self.serviceId, tx: tx)
            }
            if !self.options.contains(.isProfileFetch) {
                self.profileManager.fetchProfile(for: self.address, authedAccount: self.authedAccount)
            }

            self.udAuthFailureBlock()

            if self.options.contains(.allowIdentifiedFallback) {
                Logger.info("UD request '\(self.label)' auth failed; failing over to non-UD request")
                return self.makeRequestInternal(skipUD: true)
            } else {
                throw RequestMakerUDAuthError.udAuthFailure
            }
        }
        throw error
    }

    private func requestSucceeded(udAccess: OWSUDAccess?) {
        // If this was a UD request...
        guard let udAccess = udAccess else {
            return
        }
        // ...made for a user in "unknown" UD access mode...
        guard udAccess.udAccessMode == .unknown else {
            return
        }
        let newUdAccessMode: UnidentifiedAccessMode = {
            if udAccess.isRandomKey {
                // If a UD request succeeds for an unknown user with a random key,
                // mark address as .unrestricted.
                return .unrestricted
            } else {
                // If a UD request succeeds for an unknown user with a non-random key,
                // mark address as .enabled.
                return .enabled
            }
        }()
        databaseStorage.write { tx in
            self.udManager.setUnidentifiedAccessMode(newUdAccessMode, for: self.serviceId, tx: tx)
        }
        if !self.options.contains(.isProfileFetch) {
            // If this request isn't a profile fetch, kick off a profile fetch. If it
            // is a profile fetch, don't bother fetching it *again*.
            DispatchQueue.main.async {
                self.profileManager.fetchProfile(for: self.address, authedAccount: self.authedAccount)
            }
        }
    }
}
