//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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

// A utility class that handles:
//
// * UD auth-to-Non-UD auth failover.
// * Websocket-to-REST failover.
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
    private let address: SignalServiceAddress
    private let udAccess: OWSUDAccess?
    private let options: Options

    public init(
        label: String,
        requestFactoryBlock: @escaping RequestFactoryBlock,
        udAuthFailureBlock: @escaping UDAuthFailureBlock,
        address: SignalServiceAddress,
        udAccess: OWSUDAccess?,
        options: Options
    ) {
        self.label = label
        self.requestFactoryBlock = requestFactoryBlock
        self.udAuthFailureBlock = udAuthFailureBlock
        self.address = address
        self.udAccess = udAccess
        self.options = options
    }

    public func makeRequest() -> Promise<RequestMakerResult> {
        return makeRequestInternal(skipUD: false, skipWebsocket: options.contains(.skipWebSocket))
    }

    private func makeRequestInternal(skipUD: Bool, skipWebsocket: Bool) -> Promise<RequestMakerResult> {
        var udAccessForRequest: OWSUDAccess?
        if !skipUD {
            udAccessForRequest = udAccess
        }
        let isUDRequest: Bool = udAccessForRequest != nil
        guard let request: TSRequest = requestFactoryBlock(udAccessForRequest?.udAccessKey) else {
            return Promise(error: RequestMakerError.requestCreationFailed)
        }
        owsAssertDebug(isUDRequest == request.isUDRequest)

        let shouldUseWebsocket: Bool
        if FeatureFlags.deprecateREST {
            shouldUseWebsocket = true
        } else {
            let webSocketType: OWSWebSocketType = (isUDRequest ? .unidentified : .identified)
            shouldUseWebsocket = (
                !skipWebsocket
                && OWSWebSocket.canAppUseSocketsToMakeRequests
                && socketManager.canMakeRequests(webSocketType: webSocketType)
            )
        }

        if shouldUseWebsocket {
            return firstly {
                socketManager.makeRequestPromise(request: request)
            }.map(on: DispatchQueue.global()) { response in
                if self.udManager.isUDVerboseLoggingEnabled() {
                    if isUDRequest {
                        Logger.debug("UD websocket request '\(self.label)' succeeded.")
                    } else {
                        Logger.debug("Non-UD websocket request '\(self.label)' succeeded.")
                    }
                }

                self.requestSucceeded(udAccess: udAccessForRequest)

                return RequestMakerResult(response: response,
                                          wasSentByUD: isUDRequest,
                                          wasSentByWebsocket: true)
            }.recover(on: DispatchQueue.global()) { (error: Error) -> Promise<RequestMakerResult> in
                let statusCode = error.httpStatusCode ?? 0

                if statusCode == 413 || statusCode == 429 {
                    // We've hit rate limit; don't retry.
                    throw error
                }

                // TODO: Rework failover.
                if isUDRequest && (statusCode == 401 || statusCode == 403) {
                    // If a UD request fails due to service response (as opposed to network
                    // failure), mark address as _not_ in UD mode, then retry.
                    self.udManager.setUnidentifiedAccessMode(.disabled, address: self.address)
                    if !self.options.contains(.isProfileFetch) {
                        self.profileManager.fetchProfile(for: self.address)
                    }
                    self.udAuthFailureBlock()

                    if self.options.contains(.allowIdentifiedFallback) {
                        Logger.info("UD websocket request '\(self.label)' auth failed; failing over to non-UD websocket request.")
                        return self.makeRequestInternal(skipUD: true, skipWebsocket: skipWebsocket)
                    } else {
                        Logger.info("UD websocket request '\(self.label)' auth failed; aborting.")
                        throw RequestMakerUDAuthError.udAuthFailure
                    }
                }

                if isUDRequest {
                    Logger.info("UD Web socket request '\(self.label)' failed; failing over to REST request: \(error).")
                } else {
                    Logger.info("Non-UD Web socket request '\(self.label)' failed; failing over to REST request: \(error).")
                }

                if FeatureFlags.deprecateREST {
                    throw error
                } else {
                    return self.makeRequestInternal(skipUD: skipUD, skipWebsocket: true)
                }
            }
        } else {
            return firstly {
                networkManager.makePromise(request: request)
            }.map(on: DispatchQueue.global()) { (response: HTTPResponse) -> RequestMakerResult in
                if self.udManager.isUDVerboseLoggingEnabled() {
                    if isUDRequest {
                        Logger.debug("UD REST request '\(self.label)' succeeded.")
                    } else {
                        Logger.debug("Non-UD REST request '\(self.label)' succeeded.")
                    }
                }

                self.requestSucceeded(udAccess: udAccessForRequest)

                // Unwrap the network manager promise into a request maker promise.
                return RequestMakerResult(response: response,
                                          wasSentByUD: isUDRequest,
                                          wasSentByWebsocket: false)
            }.recover(on: DispatchQueue.global()) { (error: Error) -> Promise<RequestMakerResult> in
                if error.httpStatusCode == 413 || error.httpStatusCode == 429 {
                    // We've hit rate limit; don't retry.
                    throw error
                }

                if isUDRequest,
                   let statusCode = error.httpStatusCode,
                   statusCode == 401 || statusCode == 403 {
                    // If a UD request fails due to service response (as opposed to network
                    // failure), mark recipient as _not_ in UD mode, then retry.
                    self.udManager.setUnidentifiedAccessMode(.disabled, address: self.address)
                    if !self.options.contains(.isProfileFetch) {
                        self.profileManager.fetchProfile(for: self.address)
                    }
                    self.udAuthFailureBlock()

                    if self.options.contains(.allowIdentifiedFallback) {
                        Logger.info("UD REST request '\(self.label)' auth failed; failing over to non-UD REST request.")
                        return self.makeRequestInternal(skipUD: true, skipWebsocket: skipWebsocket)
                    } else {
                        Logger.info("UD REST request '\(self.label)' auth failed; aborting.")
                        throw RequestMakerUDAuthError.udAuthFailure
                    }
                }

                if isUDRequest {
                    Logger.debug("UD REST request '\(self.label)' failed: \(error).")
                } else {
                    Logger.debug("Non-UD REST request '\(self.label)' failed: \(error).")
                }
                throw error
            }
        }
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
        if udAccess.isRandomKey {
            // If a UD request succeeds for an unknown user with a random key,
            // mark address as .unrestricted.
            udManager.setUnidentifiedAccessMode(.unrestricted, address: address)
        } else {
            // If a UD request succeeds for an unknown user with a non-random key,
            // mark address as .enabled.
            udManager.setUnidentifiedAccessMode(.enabled, address: address)
        }

        if !self.options.contains(.isProfileFetch) {
            // If this request isn't a profile fetch, kick off a profile fetch. If it
            // is a profile fetch, don't bother fetching it *again*.
            DispatchQueue.main.async {
                self.profileManager.fetchProfile(for: self.address)
            }
        }
    }
}
