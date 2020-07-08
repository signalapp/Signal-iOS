//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalMetadataKit

@objc
public enum RequestMakerUDAuthError: Int, Error {
    case udAuthFailure
}

public enum RequestMakerError: Error {
    case requestCreationFailed
    case websocketRequestError(statusCode: Int, responseData: Data?, underlyingError: Error)
}

@objc(OWSRequestMakerResult)
public class RequestMakerResult: NSObject {
    @objc
    public let responseObject: Any?

    @objc
    public let wasSentByUD: Bool

    @objc
    public let wasSentByWebsocket: Bool

    @objc
    public init(responseObject: Any?,
                wasSentByUD: Bool,
                wasSentByWebsocket: Bool) {
        self.responseObject = responseObject
        self.wasSentByUD = wasSentByUD
        self.wasSentByWebsocket = wasSentByWebsocket
    }
}

// A utility class that handles:
//
// * UD auth-to-Non-UD auth failover.
// * Websocket-to-REST failover.
@objc(OWSRequestMaker)
public class RequestMaker: NSObject {

    public typealias RequestFactoryBlock = (SMKUDAccessKey?) -> TSRequest?
    public typealias UDAuthFailureBlock = () -> Void
    public typealias WebsocketFailureBlock = () -> Void

    private let label: String
    private let requestFactoryBlock: RequestFactoryBlock
    private let udAuthFailureBlock: UDAuthFailureBlock
    private let websocketFailureBlock: WebsocketFailureBlock
    private let address: SignalServiceAddress
    private let udAccess: OWSUDAccess?
    private let canFailoverUDAuth: Bool

    @objc
    public init(label: String,
                requestFactoryBlock : @escaping RequestFactoryBlock,
                udAuthFailureBlock : @escaping UDAuthFailureBlock,
                websocketFailureBlock : @escaping WebsocketFailureBlock,
                address: SignalServiceAddress,
                udAccess: OWSUDAccess?,
                canFailoverUDAuth: Bool) {
        self.label = label
        self.requestFactoryBlock = requestFactoryBlock
        self.udAuthFailureBlock = udAuthFailureBlock
        self.websocketFailureBlock = websocketFailureBlock
        self.address = address
        self.udAccess = udAccess
        self.canFailoverUDAuth = canFailoverUDAuth
    }

    // MARK: - Dependencies

    private var socketManager: TSSocketManager {
        return SSKEnvironment.shared.socketManager
    }

    private var networkManager: TSNetworkManager {
        return SSKEnvironment.shared.networkManager
    }

    private var udManager: OWSUDManager {
        return SSKEnvironment.shared.udManager
    }

    private var profileManager: ProfileManagerProtocol {
        return SSKEnvironment.shared.profileManager
    }

    // MARK: -

    @objc
    public func makeRequestObjc() -> AnyPromise {
        let promise = makeRequest()
            .recover(on: .global()) { (error: Error) -> Promise<RequestMakerResult> in
                switch error {
                case NetworkManagerError.taskError(_, let underlyingError):
                    throw underlyingError
                default:
                    throw error
                }
            }
        return AnyPromise(promise)
    }

    public func makeRequest() -> Promise<RequestMakerResult> {
        return makeRequestInternal(skipUD: false, skipWebsocket: false)
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
        let canMakeWebsocketRequests = (socketManager.canMakeRequests() && !skipWebsocket && !isUDRequest)

        if canMakeWebsocketRequests {
            return Promise { resolver in
                socketManager.make(request, success: { (responseObject: Any?) in
                    if self.udManager.isUDVerboseLoggingEnabled() {
                        if isUDRequest {
                            Logger.debug("UD websocket request '\(self.label)' succeeded.")
                        } else {
                            Logger.debug("Non-UD websocket request '\(self.label)' succeeded.")
                        }
                    }

                    self.requestSucceeded(udAccess: udAccessForRequest)

                    resolver.fulfill(RequestMakerResult(responseObject: responseObject,
                                                        wasSentByUD: isUDRequest,
                                                        wasSentByWebsocket: true))
                    },
                                   failure: { (statusCode: Int, responseData: Data?, error: Error) in
                                    resolver.reject(RequestMakerError.websocketRequestError(statusCode: statusCode, responseData: responseData, underlyingError: error))
                    })
                }.recover(on: .global()) { (error: Error) -> Promise<RequestMakerResult> in
                    if error.httpStatusCode == 413 {
                        // We've hit rate limit; don't retry.
                        throw error
                    }

                    switch error {
                    case RequestMakerError.websocketRequestError(let statusCode, _, _):
                        if isUDRequest && (statusCode == 401 || statusCode == 403) {
                            // If a UD request fails due to service response (as opposed to network
                            // failure), mark address as _not_ in UD mode, then retry.
                            self.udManager.setUnidentifiedAccessMode(.disabled, address: self.address)
                            self.profileManager.fetchProfile(for: self.address)
                            self.udAuthFailureBlock()

                            if self.canFailoverUDAuth {
                                Logger.info("UD websocket request '\(self.label)' auth failed; failing over to non-UD websocket request.")
                                return self.makeRequestInternal(skipUD: true, skipWebsocket: skipWebsocket)
                            } else {
                                Logger.info("UD websocket request '\(self.label)' auth failed; aborting.")
                                throw RequestMakerUDAuthError.udAuthFailure
                            }
                        }
                        break
                    default:
                        break
                    }

                    self.websocketFailureBlock()
                    if isUDRequest {
                        Logger.info("UD Web socket request '\(self.label)' failed; failing over to REST request: \(error).")
                    } else {
                        Logger.info("Non-UD Web socket request '\(self.label)' failed; failing over to REST request: \(error).")
                    }
                    return self.makeRequestInternal(skipUD: skipUD, skipWebsocket: true)
                }
        } else {
            return self.networkManager.makePromise(request: request)
                .map(on: DispatchQueue.global()) { (networkManagerResult: TSNetworkManager.Response) -> RequestMakerResult in
                    if self.udManager.isUDVerboseLoggingEnabled() {
                        if isUDRequest {
                            Logger.debug("UD REST request '\(self.label)' succeeded.")
                        } else {
                            Logger.debug("Non-UD REST request '\(self.label)' succeeded.")
                        }
                    }

                    self.requestSucceeded(udAccess: udAccessForRequest)

                    // Unwrap the network manager promise into a request maker promise.
                    return RequestMakerResult(responseObject: networkManagerResult.responseObject,
                                              wasSentByUD: isUDRequest,
                                              wasSentByWebsocket: false)
                }.recover(on: .global()) { (error: Error) -> Promise<RequestMakerResult> in
                    if error.httpStatusCode == 413 {
                        // We've hit rate limit; don't retry.
                        throw error
                    }

                    if isUDRequest,
                        let statusCode = error.httpStatusCode,
                        statusCode == 401 || statusCode == 403 {
                        // If a UD request fails due to service response (as opposed to network
                        // failure), mark recipient as _not_ in UD mode, then retry.
                        self.udManager.setUnidentifiedAccessMode(.disabled, address: self.address)
                        self.profileManager.fetchProfile(for: self.address)
                        self.udAuthFailureBlock()

                        if self.canFailoverUDAuth {
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
        DispatchQueue.main.async {
            self.profileManager.fetchProfile(for: self.address)
        }
    }
}
