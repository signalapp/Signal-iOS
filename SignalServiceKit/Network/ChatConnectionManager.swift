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
    func makeRequest(_ request: TSRequest) async throws -> HTTPResponse

    func didReceivePush()
}

public class ChatConnectionManagerImpl: ChatConnectionManager {
    private let connectionIdentified: OWSChatConnection
    private let connectionUnidentified: OWSChatConnection
    private var connections: [OWSChatConnection] { [ connectionIdentified, connectionUnidentified ]}

    public init(accountManager: TSAccountManager, appExpiry: AppExpiry, appReadiness: AppReadiness, currentCallProvider: any CurrentCallProvider, db: any DB, libsignalNet: Net, registrationStateChangeManager: RegistrationStateChangeManager, userDefaults: UserDefaults) {
        AssertIsOnMainThread()
        self.connectionIdentified = OWSAuthConnectionUsingLibSignal(libsignalNet: libsignalNet, accountManager: accountManager, appExpiry: appExpiry, appReadiness: appReadiness, currentCallProvider: currentCallProvider, db: db, registrationStateChangeManager: registrationStateChangeManager)
        self.connectionUnidentified = OWSUnauthConnectionUsingLibSignal(libsignalNet: libsignalNet, accountManager: accountManager, appExpiry: appExpiry, appReadiness: appReadiness, currentCallProvider: currentCallProvider, db: db, registrationStateChangeManager: registrationStateChangeManager)

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
        connection(ofType: connectionType).shouldSocketBeOpen
    }

    public typealias RequestSuccess = OWSChatConnection.RequestSuccess
    public typealias RequestFailure = OWSChatConnection.RequestFailure

    public func waitForIdentifiedConnectionToOpen() async throws {
        owsAssertBeta(OWSChatConnection.canAppUseSocketsToMakeRequests)
        try await self.connectionIdentified.waitForOpen()
    }

    private func waitForSocketToOpenIfItShouldBeOpen(
        connectionType: OWSChatConnectionType
    ) async {
        let connection = self.connection(ofType: connectionType)
        guard connection.shouldSocketBeOpen else {
            // The socket wants to be open, but isn't.
            // Proceed even though we will probably fail.
            return
        }
        // After 30 seconds, we try anyways. We'll probably fail.
        let maxWaitInterval: TimeInterval = 30 * .second
        _ = try? await withCooperativeTimeout(
            seconds: maxWaitInterval,
            operation: { try await connection.waitForOpen() }
        )
    }

    // This method can be called from any thread.
    public func makeRequest(_ request: TSRequest) async throws -> HTTPResponse {
        let connectionType = try request.auth.connectionType

        // Request that the websocket open to make this request, if necessary.
        let unsubmittedRequestToken = connection(ofType: connectionType).makeUnsubmittedRequestToken()

        await self.waitForSocketToOpenIfItShouldBeOpen(connectionType: connectionType)

        return try await connection(ofType: connectionType).makeRequest(request, unsubmittedRequestToken: unsubmittedRequestToken)
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
