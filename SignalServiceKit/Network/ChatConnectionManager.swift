//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol ChatConnectionManager {
    func updateCanOpenWebSocket()
    func waitForIdentifiedConnectionToOpen() async throws
    /// Waits until we're no longer trying to open a web socket.
    ///
    /// - Note: If an existing socket gets interrupted but we'll try to
    /// re-connect, this will keep waiting. In other words, this waits until we
    /// are no longer capable of opening a socket (e.g., we are deregistered,
    /// all connection tokens are released).
    func waitUntilIdentifiedConnectionShouldBeClosed() async throws(CancellationError)
    var identifiedConnectionState: OWSChatConnectionState { get }
    var hasEmptiedInitialQueue: Bool { get async }

    func shouldWaitForSocketToMakeRequest(connectionType: OWSChatConnectionType) -> Bool
    func shouldSocketBeOpen_restOnly(connectionType: OWSChatConnectionType) -> Bool
    func requestIdentifiedConnection(shouldReconnectIfConnectedElsewhere: Bool) -> OWSChatConnection.ConnectionToken
    func requestUnidentifiedConnection(shouldReconnectIfConnectedElsewhere: Bool) -> OWSChatConnection.ConnectionToken
    func waitForDisconnectIfClosed() async
    func makeRequest(_ request: TSRequest) async throws -> HTTPResponse
}

extension ChatConnectionManager {
    public func requestConnections(shouldReconnectIfConnectedElsewhere: Bool) -> [OWSChatConnection.ConnectionToken] {
        return [
            requestIdentifiedConnection(shouldReconnectIfConnectedElsewhere: shouldReconnectIfConnectedElsewhere),
            requestUnidentifiedConnection(shouldReconnectIfConnectedElsewhere: shouldReconnectIfConnectedElsewhere),
        ]
    }
}

public class ChatConnectionManagerImpl: ChatConnectionManager {
    private let connectionIdentified: OWSChatConnection
    private let connectionUnidentified: OWSChatConnection
    private var connections: [OWSChatConnection] { [ connectionIdentified, connectionUnidentified ]}

    public init(
        accountManager: TSAccountManager,
        appContext: any AppContext,
        appExpiry: AppExpiry,
        appReadiness: AppReadiness,
        db: any DB,
        libsignalNet: Net,
        registrationStateChangeManager: RegistrationStateChangeManager,
        inactivePrimaryDeviceStore: InactivePrimaryDeviceStore,
        userDefaults: UserDefaults,
    ) {
        AssertIsOnMainThread()
        self.connectionIdentified = OWSAuthConnectionUsingLibSignal(
            libsignalNet: libsignalNet,
            accountManager: accountManager,
            appContext: appContext,
            appExpiry: appExpiry,
            appReadiness: appReadiness,
            db: db,
            registrationStateChangeManager: registrationStateChangeManager,
            inactivePrimaryDeviceStore: inactivePrimaryDeviceStore,
        )
        self.connectionUnidentified = OWSUnauthConnectionUsingLibSignal(
            libsignalNet: libsignalNet,
            accountManager: accountManager,
            appExpiry: appExpiry,
            appReadiness: appReadiness,
            db: db,
            registrationStateChangeManager: registrationStateChangeManager,
            inactivePrimaryDeviceStore: inactivePrimaryDeviceStore,
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

    public func updateCanOpenWebSocket() {
        for connection in connections {
            connection.updateCanOpenWebSocket()
        }
    }

    public func shouldWaitForSocketToMakeRequest(connectionType: OWSChatConnectionType) -> Bool {
        return connection(ofType: connectionType).canOpenWebSocket
    }

    public func shouldSocketBeOpen_restOnly(connectionType: OWSChatConnectionType) -> Bool {
        return connection(ofType: connectionType).shouldSocketBeOpen_restOnly
    }

    public func waitForIdentifiedConnectionToOpen() async throws {
        owsAssertBeta(OWSChatConnection.canAppUseSocketsToMakeRequests)
        try await self.connectionIdentified.waitForOpen()
    }

    public func waitUntilIdentifiedConnectionShouldBeClosed() async throws(CancellationError) {
        owsAssertBeta(OWSChatConnection.canAppUseSocketsToMakeRequests)
        try await self.connectionIdentified.waitUntilSocketShouldBeClosed()
    }

    public func requestIdentifiedConnection(shouldReconnectIfConnectedElsewhere: Bool) -> OWSChatConnection.ConnectionToken {
        return connectionIdentified.requestConnection(shouldReconnectIfConnectedElsewhere: shouldReconnectIfConnectedElsewhere)
    }

    public func requestUnidentifiedConnection(shouldReconnectIfConnectedElsewhere: Bool) -> OWSChatConnection.ConnectionToken {
        return connectionUnidentified.requestConnection(shouldReconnectIfConnectedElsewhere: shouldReconnectIfConnectedElsewhere)
    }

    public func waitForDisconnectIfClosed() async {
        await withTaskGroup { taskGroup in
            for connection in connections {
                taskGroup.addTask { await connection.waitForDisconnectIfClosed() }
            }
            await taskGroup.waitForAll()
        }
    }

    // This method can be called from any thread.
    public func makeRequest(_ request: TSRequest) async throws -> HTTPResponse {
        let connectionType = try request.auth.connectionType

        return try await connection(ofType: connectionType).makeRequest(request)
    }

    public var identifiedConnectionState: OWSChatConnectionState {
        connectionIdentified.currentState
    }

    public var hasEmptiedInitialQueue: Bool {
        get async {
            return await connectionIdentified.hasEmptiedInitialQueue
        }
    }
}

#if TESTABLE_BUILD

public class ChatConnectionManagerMock: ChatConnectionManager {

    public init() {}

    public func updateCanOpenWebSocket() {
    }

    public var hasEmptiedInitialQueue: Bool = false

    public func waitForIdentifiedConnectionToOpen() async throws {
    }

    public func waitUntilIdentifiedConnectionShouldBeClosed() async throws(CancellationError) {
    }

    public var identifiedConnectionState: OWSChatConnectionState = .closed

    public var shouldWaitForSocketToMakeRequestPerType = [OWSChatConnectionType: Bool]()

    public func shouldWaitForSocketToMakeRequest(connectionType: OWSChatConnectionType) -> Bool {
        return shouldWaitForSocketToMakeRequestPerType[connectionType] ?? true
    }

    public func shouldSocketBeOpen_restOnly(connectionType: OWSChatConnectionType) -> Bool {
        fatalError()
    }

    public func requestIdentifiedConnection(shouldReconnectIfConnectedElsewhere: Bool) -> OWSChatConnection.ConnectionToken {
        fatalError()
    }

    public func requestUnidentifiedConnection(shouldReconnectIfConnectedElsewhere: Bool) -> OWSChatConnection.ConnectionToken {
        fatalError()
    }

    public func waitForDisconnectIfClosed() async {
    }

    public var requestHandler: (_ request: TSRequest) async throws -> HTTPResponse = { _ in
        fatalError("must override for tests")
    }

    public func makeRequest(_ request: TSRequest) async throws -> HTTPResponse {
        return try await requestHandler(request)
    }
}

#endif
