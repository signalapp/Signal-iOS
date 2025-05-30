//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol ChatConnectionManager {
    func waitForIdentifiedConnectionToOpen() async throws
    var identifiedConnectionState: OWSChatConnectionState { get }
    var hasEmptiedInitialQueue: Bool { get }

    func shouldWaitForSocketToMakeRequest(connectionType: OWSChatConnectionType) -> Bool
    func requestConnections() -> [OWSChatConnection.ConnectionToken]
    func makeRequest(_ request: TSRequest) async throws -> HTTPResponse

    func didReceivePush()
}

public class ChatConnectionManagerImpl: ChatConnectionManager {
    private let connectionIdentified: OWSChatConnection
    private let connectionUnidentified: OWSChatConnection
    private var connections: [OWSChatConnection] { [ connectionIdentified, connectionUnidentified ]}

    public init(accountManager: TSAccountManager, appExpiry: AppExpiry, appReadiness: AppReadiness, db: any DB, libsignalNet: Net, registrationStateChangeManager: RegistrationStateChangeManager, userDefaults: UserDefaults) {
        AssertIsOnMainThread()
        self.connectionIdentified = OWSAuthConnectionUsingLibSignal(libsignalNet: libsignalNet, accountManager: accountManager, appExpiry: appExpiry, appReadiness: appReadiness, db: db, registrationStateChangeManager: registrationStateChangeManager)
        self.connectionUnidentified = OWSUnauthConnectionUsingLibSignal(libsignalNet: libsignalNet, accountManager: accountManager, appExpiry: appExpiry, appReadiness: appReadiness, db: db, registrationStateChangeManager: registrationStateChangeManager)

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

    public func shouldWaitForSocketToMakeRequest(connectionType: OWSChatConnectionType) -> Bool {
        return connection(ofType: connectionType).canOpenWebSocket
    }

    public func waitForIdentifiedConnectionToOpen() async throws {
        owsAssertBeta(OWSChatConnection.canAppUseSocketsToMakeRequests)
        try await self.connectionIdentified.waitForOpen()
    }

    public func requestConnections() -> [OWSChatConnection.ConnectionToken] {
        return [connectionIdentified.requestConnection(), connectionUnidentified.requestConnection()]
    }

    // This method can be called from any thread.
    public func makeRequest(_ request: TSRequest) async throws -> HTTPResponse {
        let connectionType = try request.auth.connectionType

        // Request that the websocket open to make this request, if necessary.
        let connectionToken = connection(ofType: connectionType).requestConnection()
        defer { connectionToken.releaseConnection() }

        return try await connection(ofType: connectionType).makeRequest(request)
    }

    // This method can be called from any thread.
    public func didReceivePush() {
        for connection in connections {
            connection.didReceivePush()
        }
    }

    public var identifiedConnectionState: OWSChatConnectionState {
        connectionIdentified.currentState
    }

    public var hasEmptiedInitialQueue: Bool {
        connectionIdentified.hasEmptiedInitialQueue
    }
}

#if TESTABLE_BUILD

public class ChatConnectionManagerMock: ChatConnectionManager {

    public init() {}

    public var hasEmptiedInitialQueue: Bool = false

    public func waitForIdentifiedConnectionToOpen() async throws {
    }

    public var identifiedConnectionState: OWSChatConnectionState = .closed

    public var shouldWaitForSocketToMakeRequestPerType = [OWSChatConnectionType: Bool]()

    public func shouldWaitForSocketToMakeRequest(connectionType: OWSChatConnectionType) -> Bool {
        return shouldWaitForSocketToMakeRequestPerType[connectionType] ?? true
    }

    public func requestConnections() -> [OWSChatConnection.ConnectionToken] {
        return []
    }

    public var requestHandler: (_ request: TSRequest) async throws -> HTTPResponse = { _ in
        fatalError("must override for tests")
    }

    public func makeRequest(_ request: TSRequest) async throws -> HTTPResponse {
        return try await requestHandler(request)
    }

    public func didReceivePush() {
        // Do nothing
    }
}

#endif
