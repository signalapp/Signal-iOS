//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol SocketManager {
    var isAnySocketOpen: Bool { get }
    var hasEmptiedInitialQueue: Bool { get }

    func socketState(forType webSocketType: OWSWebSocketType) -> OWSWebSocketState
    func cycleSocket()

    func canMakeRequests(webSocketType: OWSWebSocketType) -> Bool
    func makeRequestPromise(request: TSRequest) -> Promise<HTTPResponse>

    func didReceivePush()
}

public class SocketManagerImpl: SocketManager {
    private let websocketIdentified: OWSWebSocket
    private let websocketUnidentified: OWSWebSocket
    private var websockets: [OWSWebSocket] { [ websocketIdentified, websocketUnidentified ]}

    public required init(appExpiry: AppExpiry, db: DB) {
        AssertIsOnMainThread()

        websocketIdentified = OWSWebSocket(
            webSocketType: .identified,
            appExpiry: appExpiry,
            db: db
        )
        websocketUnidentified = OWSWebSocket(
            webSocketType: .unidentified,
            appExpiry: appExpiry,
            db: db
        )

        SwiftSingletons.register(self)
    }

    private func webSocket(ofType webSocketType: OWSWebSocketType) -> OWSWebSocket {
        switch webSocketType {
        case .identified:
            return websocketIdentified
        case .unidentified:
            return websocketUnidentified
        }
    }

    public func canMakeRequests(webSocketType: OWSWebSocketType) -> Bool {
        webSocket(ofType: webSocketType).canMakeRequests
    }

    public typealias RequestSuccess = OWSWebSocket.RequestSuccess
    public typealias RequestFailure = OWSWebSocket.RequestFailure

    private func makeRequest(_ request: TSRequest,
                             unsubmittedRequestToken: OWSWebSocket.UnsubmittedRequestToken,
                             webSocketType: OWSWebSocketType,
                             success: @escaping RequestSuccess,
                             failure: @escaping RequestFailure) {
        assertOnQueue(OWSWebSocket.serialQueue)

        let webSocket = self.webSocket(ofType: webSocketType)
        webSocket.makeRequest(request,
                              unsubmittedRequestToken: unsubmittedRequestToken,
                              success: success,
                              failure: failure)
    }

    private func waitForSocketToOpen(webSocketType: OWSWebSocketType,
                                     waitStartDate: Date = Date()) -> Promise<Void> {
        assertOnQueue(OWSWebSocket.serialQueue)

        let webSocket = self.webSocket(ofType: webSocketType)
        if webSocket.canMakeRequests {
            // The socket is open; proceed.
            return Promise.value(())
        }
        guard webSocket.shouldSocketBeOpen else {
            // The socket wants to be open, but isn't.
            // Proceed even though we will probably fail.
            return Promise.value(())
        }
        let maxWaitInteral = kSecondInterval * 30
        guard abs(waitStartDate.timeIntervalSinceNow) < maxWaitInteral else {
            // The socket wants to be open, but isn't.
            // Proceed even though we will probably fail.
            return Promise.value(())
        }
        return firstly(on: OWSWebSocket.serialQueue) {
            Guarantee.after(seconds: kSecondInterval / 10)
        }.then(on: OWSWebSocket.serialQueue) {
            self.waitForSocketToOpen(webSocketType: webSocketType,
                                     waitStartDate: waitStartDate)
        }
    }

    // This method can be called from any thread.
    public func makeRequestPromise(request: TSRequest) -> Promise<HTTPResponse> {
        let webSocketType: OWSWebSocketType = {
            if request.isUDRequest {
                return .unidentified
            } else if !request.shouldHaveAuthorizationHeaders {
                return .unidentified
            } else {
                return .identified
            }
        }()
        return makeRequestPromise(request: request, webSocketType: webSocketType)
    }

    // This method can be called from any thread.
    private func makeRequestPromise(request: TSRequest,
                                    webSocketType: OWSWebSocketType) -> Promise<HTTPResponse> {

        // webSocketType, isUDRequest and shouldHaveAuthorizationHeaders
        // should be (mostly?) aligned.
        switch webSocketType {
        case .identified:
            owsAssertDebug(!request.isUDRequest)
            owsAssertDebug(request.shouldHaveAuthorizationHeaders)
            if request.isUDRequest || !request.shouldHaveAuthorizationHeaders {
                Logger.info("request: \(request.description), isUDRequest: \(request.isUDRequest), shouldHaveAuthorizationHeaders: \(request.shouldHaveAuthorizationHeaders)")
            }
        case .unidentified:
            owsAssertDebug(request.isUDRequest || !request.shouldHaveAuthorizationHeaders)
            if !request.isUDRequest && request.shouldHaveAuthorizationHeaders {
                Logger.info("request: \(request.description), isUDRequest: \(request.isUDRequest), shouldHaveAuthorizationHeaders: \(request.shouldHaveAuthorizationHeaders)")
            }
        }

        // Request that the websocket open to make this request, if necessary.
        let unsubmittedRequestToken = webSocket(ofType: webSocketType).makeUnsubmittedRequestToken()

        return firstly(on: OWSWebSocket.serialQueue) {
            self.waitForSocketToOpen(webSocketType: webSocketType)
        }.then(on: OWSWebSocket.serialQueue) { () -> Promise<HTTPResponse> in
            let (promise, future) = Promise<HTTPResponse>.pending()
            self.makeRequest(request,
                             unsubmittedRequestToken: unsubmittedRequestToken,
                             webSocketType: webSocketType,
                             success: { (response: HTTPResponse) in
                                future.resolve(response)
                             },
                             failure: { (failure: OWSHTTPErrorWrapper) in
                                future.reject(failure.error)
                             })
            return promise
        }
    }

    // This method can be called from any thread.
    public func didReceivePush() {
        for websocket in websockets {
            websocket.didReceivePush()
        }
    }

    public func cycleSocket() {
        AssertIsOnMainThread()

        for websocket in websockets {
            websocket.cycleSocket()
        }
    }

    public var isAnySocketOpen: Bool {
        OWSWebSocketType.allCases.contains { socketState(forType: $0) == .open }
    }

    public func socketState(forType webSocketType: OWSWebSocketType) -> OWSWebSocketState {
        webSocket(ofType: webSocketType).currentState
    }

    public var hasEmptiedInitialQueue: Bool {
        websocketIdentified.hasEmptiedInitialQueue
    }
}
