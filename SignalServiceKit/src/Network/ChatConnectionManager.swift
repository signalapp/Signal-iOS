//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public protocol ChatConnectionManager {
    var isAnyConnectionOpen: Bool { get }
    func waitForConnectionToOpen(type: OWSChatConnectionType) async throws

    var hasEmptiedInitialQueue: Bool { get }

    func connectionState(forType type: OWSChatConnectionType) -> OWSChatConnectionState

    func canMakeRequests(connectionType: OWSChatConnectionType) -> Bool
    func makeRequestPromise(request: TSRequest) -> Promise<HTTPResponse>

    func didReceivePush()
}

public class ChatConnectionManagerImpl: ChatConnectionManager {
    private let connectionIdentified: OWSChatConnection
    private let connectionUnidentified: OWSChatConnection
    private var connections: [OWSChatConnection] { [ connectionIdentified, connectionUnidentified ]}

    public required init(appExpiry: AppExpiry, db: DB) {
        AssertIsOnMainThread()

        connectionIdentified = OWSChatConnection(
            type: .identified,
            appExpiry: appExpiry,
            db: db
        )
        connectionUnidentified = OWSChatConnection(
            type: .unidentified,
            appExpiry: appExpiry,
            db: db
        )

        SwiftSingletons.register(self)
    }

    private func connection(ofType type: OWSChatConnectionType) -> OWSChatConnection {
        switch type {
        case .identified:
            return connectionIdentified
        case .unidentified:
            return connectionUnidentified
        }
    }

    public func canMakeRequests(connectionType: OWSChatConnectionType) -> Bool {
        connection(ofType: connectionType).canMakeRequests
    }

    public typealias RequestSuccess = OWSChatConnection.RequestSuccess
    public typealias RequestFailure = OWSChatConnection.RequestFailure

    private func makeRequest(_ request: TSRequest,
                             unsubmittedRequestToken: OWSChatConnection.UnsubmittedRequestToken,
                             connectionType: OWSChatConnectionType,
                             success: @escaping RequestSuccess,
                             failure: @escaping RequestFailure) {
        assertOnQueue(OWSChatConnection.serialQueue)

        let connection = self.connection(ofType: connectionType)
        connection.makeRequest(request,
                               unsubmittedRequestToken: unsubmittedRequestToken,
                               success: success,
                               failure: failure)
    }

    public func waitForConnectionToOpen(type: OWSChatConnectionType) async throws {
        let (waiterPromise, waiterFuture) = Promise<Void>.pending()
        try await withTaskCancellationHandler(
            operation: {
                let openGuarantee = connection(ofType: type).waitForOpen()
                waiterFuture.resolve(on: SyncScheduler(), with: openGuarantee)
                try await waiterPromise.awaitable()
            },
            onCancel: { waiterFuture.reject(CancellationError()) }
        )
    }

    private func waitForSocketToOpenIfItShouldBeOpen(
        connectionType: OWSChatConnectionType
    ) -> Promise<Void> {
        assertOnQueue(OWSChatConnection.serialQueue)

        let connection = self.connection(ofType: connectionType)
        guard connection.shouldSocketBeOpen else {
            // The socket wants to be open, but isn't.
            // Proceed even though we will probably fail.
            return Promise.value(())
        }
        // After 30 seconds, we try anyways. We'll probably fail.
        let maxWaitInterval = 30 * kSecondInterval
        return connection
            .waitForOpen()
            .timeout(on: OWSChatConnection.serialQueue, seconds: maxWaitInterval)
    }

    // This method can be called from any thread.
    public func makeRequestPromise(request: TSRequest) -> Promise<HTTPResponse> {
        let connectionType: OWSChatConnectionType = {
            if request.isUDRequest {
                return .unidentified
            } else if !request.shouldHaveAuthorizationHeaders {
                return .unidentified
            } else {
                return .identified
            }
        }()
        return makeRequestPromise(request: request, connectionType: connectionType)
    }

    // This method can be called from any thread.
    private func makeRequestPromise(request: TSRequest,
                                    connectionType: OWSChatConnectionType) -> Promise<HTTPResponse> {

        // connectionType, isUDRequest and shouldHaveAuthorizationHeaders
        // should be (mostly?) aligned.
        switch connectionType {
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
        let unsubmittedRequestToken = connection(ofType: connectionType).makeUnsubmittedRequestToken()

        return firstly(on: OWSChatConnection.serialQueue) {
            self.waitForSocketToOpenIfItShouldBeOpen(connectionType: connectionType)
        }.then(on: OWSChatConnection.serialQueue) { () -> Promise<HTTPResponse> in
            let (promise, future) = Promise<HTTPResponse>.pending()
            self.makeRequest(request,
                             unsubmittedRequestToken: unsubmittedRequestToken,
                             connectionType: connectionType,
                             success: { (response: HTTPResponse) in
                                future.resolve(response)
                             },
                             failure: { (failure: OWSHTTPError) in
                                future.reject(failure)
                             })
            return promise
        }
    }

    // This method can be called from any thread.
    public func didReceivePush() {
        for connection in connections {
            connection.didReceivePush()
        }
    }

    public var isAnyConnectionOpen: Bool {
        OWSChatConnectionType.allCases.contains { connectionState(forType: $0) == .open }
    }

    public func connectionState(forType type: OWSChatConnectionType) -> OWSChatConnectionState {
        connection(ofType: type).currentState
    }

    public var hasEmptiedInitialQueue: Bool {
        connectionIdentified.hasEmptiedInitialQueue
    }
}

#if TESTABLE_BUILD

public class ChatConnectionManagerMock: ChatConnectionManager {

    public init() {}

    public var isAnyConnectionOpen: Bool = false

    public var hasEmptiedInitialQueue: Bool = false

    public func waitForConnectionToOpen(type: OWSChatConnectionType) async throws {
    }

    public var socketStatesPerType = [OWSChatConnectionType: OWSChatConnectionState]()

    public func connectionState(forType type: OWSChatConnectionType) -> OWSChatConnectionState {
        return  socketStatesPerType[type] ?? .closed
    }

    public var canMakeRequestsPerType = [OWSChatConnectionType: Bool]()

    public func canMakeRequests(connectionType: OWSChatConnectionType) -> Bool {
        return canMakeRequestsPerType[connectionType] ?? true
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
