//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public protocol SocketManager {
    var isAnySocketOpen: Bool { get }
    func waitForSocketToOpen(webSocketType: OWSWebSocketType) async throws

    var hasEmptiedInitialQueue: Bool { get }

    func socketState(forType webSocketType: OWSWebSocketType) -> OWSWebSocketState

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

    public func waitForSocketToOpen(webSocketType: OWSWebSocketType) async throws {
        let (waiterPromise, waiterFuture) = Promise<Void>.pending()
        try await withTaskCancellationHandler(
            operation: {
                let openGuarantee = webSocket(ofType: webSocketType).waitForOpen()
                waiterFuture.resolve(on: SyncScheduler(), with: openGuarantee)
                try await waiterPromise.awaitable()
            },
            onCancel: { waiterFuture.reject(CancellationError()) }
        )
    }

    private func waitForSocketToOpenIfItShouldBeOpen(
        webSocketType: OWSWebSocketType
    ) -> Promise<Void> {
        assertOnQueue(OWSWebSocket.serialQueue)

        let webSocket = self.webSocket(ofType: webSocketType)
        guard webSocket.shouldSocketBeOpen else {
            // The socket wants to be open, but isn't.
            // Proceed even though we will probably fail.
            return Promise.value(())
        }
        // After 30 seconds, we try anyways. We'll probably fail.
        let maxWaitInterval = 30 * kSecondInterval
        return webSocket
            .waitForOpen()
            .timeout(on: OWSWebSocket.serialQueue, seconds: maxWaitInterval)
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
            self.waitForSocketToOpenIfItShouldBeOpen(webSocketType: webSocketType)
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

#if TESTABLE_BUILD

public class SocketManagerMock: SocketManager {

    public init() {}

    public var isAnySocketOpen: Bool = false

    public var hasEmptiedInitialQueue: Bool = false

    public func waitForSocketToOpen(webSocketType: OWSWebSocketType) async throws {
    }

    public var socketStatesPerType = [OWSWebSocketType: OWSWebSocketState]()

    public func socketState(forType webSocketType: OWSWebSocketType) -> OWSWebSocketState {
        return  socketStatesPerType[webSocketType] ?? .closed
    }

    public var canMakeRequestsPerType = [OWSWebSocketType: Bool]()

    public func canMakeRequests(webSocketType: OWSWebSocketType) -> Bool {
        return canMakeRequestsPerType[webSocketType] ?? true
    }

    public var requestFactory: (_ request: TSRequest) -> Promise<HTTPResponse> = { _ in
        fatalError("must override for tests")
    }

    public func makeRequestPromise(request: TSRequest) -> Promise<HTTPResponse> {
        return requestFactory(request)
    }

    public func didReceivePush() {
        // Do nothing
    }
}

#endif
