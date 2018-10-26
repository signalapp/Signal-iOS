//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalMetadataKit

@objc
public enum RequestMakerUDAuthError: Int, Error {
    case udAuthFailure
}

public enum RequestMakerError: Error {
    case websocketRequestError(statusCode : Int, responseData : Data?, underlyingError : Error)
}

@objc(OWSRequestMakerResult)
public class RequestMakerResult: NSObject {
    @objc
    public let responseObject: Any?

    @objc
    public let wasSentByUD: Bool

    @objc
    public init(responseObject: Any?,
                wasSentByUD: Bool) {
        self.responseObject = responseObject
        self.wasSentByUD = wasSentByUD
    }
}

// A utility class that handles:
//
// * UD auth-to-Non-UD auth failover.
// * Websocket-to-REST failover.
@objc(OWSRequestMaker)
public class RequestMaker: NSObject {

    public typealias RequestFactoryBlock = (SMKUDAccessKey?) -> TSRequest
    public typealias UDAuthFailureBlock = () -> Void
    public typealias WebsocketFailureBlock = () -> Void

    private let label: String
    private let requestFactoryBlock: RequestFactoryBlock
    private let udAuthFailureBlock: UDAuthFailureBlock
    private let websocketFailureBlock: WebsocketFailureBlock
    private let recipientId: String
    private let udAccessKey: SMKUDAccessKey?
    private let canFailoverUDAuth: Bool

    @objc
    public init(label: String,
                requestFactoryBlock : @escaping RequestFactoryBlock,
                udAuthFailureBlock : @escaping UDAuthFailureBlock,
                websocketFailureBlock : @escaping WebsocketFailureBlock,
                recipientId: String,
                udAccessKey: SMKUDAccessKey?,
                canFailoverUDAuth: Bool) {
        self.label = label
        self.requestFactoryBlock = requestFactoryBlock
        self.udAuthFailureBlock = udAuthFailureBlock
        self.websocketFailureBlock = websocketFailureBlock
        self.recipientId = recipientId
        self.udAccessKey = udAccessKey
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

    // MARK: -

    @objc
    public func makeRequestObjc() -> AnyPromise {
        let promise = makeRequest()
            .recover { (error: Error) -> Promise<RequestMakerResult> in
                switch error {
                case NetworkManagerError.taskError(_, let underlyingError):
                    throw underlyingError
                default:
                    throw error
                }
            }
        let anyPromise = AnyPromise(promise)
        anyPromise.retainUntilComplete()
        return anyPromise
    }

    public func makeRequest() -> Promise<RequestMakerResult> {
        return makeRequestInternal(skipUD: false, skipWebsocket: false)
    }

    private func makeRequestInternal(skipUD: Bool, skipWebsocket: Bool) -> Promise<RequestMakerResult> {
        var udAccessKeyForRequest: SMKUDAccessKey?
        if !skipUD {
            udAccessKeyForRequest = udAccessKey
        }
        let isUDSend = udAccessKeyForRequest != nil
        let request = requestFactoryBlock(udAccessKeyForRequest)
        let webSocketType: OWSWebSocketType = (isUDSend ? .UD : .default)
        let canMakeWebsocketRequests = (socketManager.canMakeRequests(of: webSocketType) && !skipWebsocket)

        if canMakeWebsocketRequests {
            return Promise { resolver in
                socketManager.make(request, webSocketType: webSocketType, success: { (responseObject: Any?) in
                    if self.udManager.isUDVerboseLoggingEnabled() {
                        if isUDSend {
                            Logger.debug("UD websocket request '\(self.label)' succeeded.")
                        } else {
                            Logger.debug("Non-UD websocket request '\(self.label)' succeeded.")
                        }
                    }

                    resolver.fulfill(RequestMakerResult(responseObject: responseObject, wasSentByUD: isUDSend))
                }) { (statusCode: Int, responseData: Data?, error: Error) in
                    resolver.reject(RequestMakerError.websocketRequestError(statusCode: statusCode, responseData: responseData, underlyingError: error))
                }
                }.recover { (error: Error) -> Promise<RequestMakerResult> in
                    switch error {
                    case RequestMakerError.websocketRequestError(let statusCode, _, _):
                        if isUDSend && (statusCode == 401 || statusCode == 403) {
                            // If a UD send fails due to service response (as opposed to network
                            // failure), mark recipient as _not_ in UD mode, then retry.
                            self.udManager.setUnidentifiedAccessMode(.disabled, recipientId: self.recipientId)
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
                    Logger.info("Non-UD Web socket request '\(self.label)' failed; failing over to REST request: \(error).")
                    return self.makeRequestInternal(skipUD: skipUD, skipWebsocket: true)
                }
        } else {
            return self.networkManager.makePromise(request: request)
                .map { (networkManagerResult: TSNetworkManager.NetworkManagerResult) -> RequestMakerResult in
                    if self.udManager.isUDVerboseLoggingEnabled() {
                        if isUDSend {
                            Logger.debug("UD REST request '\(self.label)' succeeded.")
                        } else {
                            Logger.debug("Non-UD REST request '\(self.label)' succeeded.")
                        }
                    }

                    // Unwrap the network manager promise into a request maker promise.
                    return RequestMakerResult(responseObject: networkManagerResult.responseObject, wasSentByUD: isUDSend)
                }.recover { (error: Error) -> Promise<RequestMakerResult> in
                    switch error {
                    case NetworkManagerError.taskError(let task, _):
                        let statusCode = task.statusCode()
                        if isUDSend && (statusCode == 401 || statusCode == 403) {
                            // If a UD send fails due to service response (as opposed to network
                            // failure), mark recipient as _not_ in UD mode, then retry.
                            self.udManager.setUnidentifiedAccessMode(.disabled, recipientId: self.recipientId)
                            self.udAuthFailureBlock()
                            if self.canFailoverUDAuth {
                                Logger.info("UD REST request '\(self.label)' auth failed; failing over to non-UD REST request.")
                                return self.makeRequestInternal(skipUD: true, skipWebsocket: skipWebsocket)
                            } else {
                                Logger.info("UD REST request '\(self.label)' auth failed; aborting.")
                                throw RequestMakerUDAuthError.udAuthFailure
                            }
                        }
                        break
                    default:
                        break
                    }

                    Logger.debug("Non-UD REST request '\(self.label)' failed: \(error).")
                    throw error
                }
        }
    }
}
