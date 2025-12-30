//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol ChatConnectionManager {
    func updateCanOpenWebSocket()
    func waitForIdentifiedConnectionToOpen() async throws(CancellationError)
    func waitForUnidentifiedConnectionToOpen() async throws(CancellationError)
    /// Waits until we're no longer trying to open a web socket.
    ///
    /// - Note: If an existing socket gets interrupted but we'll try to
    /// re-connect, this will keep waiting. In other words, this waits until we
    /// are no longer capable of opening a socket (e.g., we are deregistered,
    /// all connection tokens are released).
    func waitUntilIdentifiedConnectionShouldBeClosed() async throws(CancellationError)
    @MainActor
    var unidentifiedConnectionState: OWSChatConnectionState { get }
    var hasEmptiedInitialQueue: Bool { get async }

    func requestIdentifiedConnection() -> OWSChatConnection.ConnectionToken
    func requestUnidentifiedConnection() -> OWSChatConnection.ConnectionToken
    func waitForDisconnectIfClosed() async
    func makeRequest(_ request: TSRequest) async throws -> HTTPResponse

    func setRegistrationOverride(_ chatServiceAuth: ChatServiceAuth) async
    func clearRegistrationOverride() async

    /// Access a libsignal "service" on the active unauthenticated connection.
    ///
    /// Intended to be used with code completion; ``UnauthServiceSelector``
    /// has static members for each valid service. See the docs for that protocol
    /// for under-the-hood information.
    ///
    /// This will attempt to hold the connection open until the operation
    /// completes, so make sure to do any complex processing of the result
    /// *outside* the callback.
    ///
    /// This method can be called from any thread.
    func withUnauthService<Service, Output>(
        _ service: Service,
        do callback: (Service.Api) async throws -> Output,
    ) async throws -> Output where Service: UnauthServiceSelector
}

extension ChatConnectionManager {
    public func requestConnections() -> [OWSChatConnection.ConnectionToken] {
        return [
            requestIdentifiedConnection(),
            requestUnidentifiedConnection(),
        ]
    }
}

public class ChatConnectionManagerImpl: ChatConnectionManager {
    private let connectionIdentified: OWSAuthConnectionUsingLibSignal
    private let connectionUnidentified: OWSUnauthConnectionUsingLibSignal
    private var connections: [OWSChatConnection] { [connectionIdentified, connectionUnidentified] }

    @MainActor
    public init(
        accountManager: TSAccountManager,
        appContext: any AppContext,
        appExpiry: AppExpiry,
        appReadiness: AppReadiness,
        db: any DB,
        inactivePrimaryDeviceStore: InactivePrimaryDeviceStore,
        libsignalNet: Net,
        registrationStateChangeManager: RegistrationStateChangeManager,
    ) {
        self.connectionIdentified = OWSAuthConnectionUsingLibSignal(
            libsignalNet: libsignalNet,
            accountManager: accountManager,
            appContext: appContext,
            appExpiry: appExpiry,
            appReadiness: appReadiness,
            db: db,
            inactivePrimaryDeviceStore: inactivePrimaryDeviceStore,
            registrationStateChangeManager: registrationStateChangeManager,
        )
        self.connectionUnidentified = OWSUnauthConnectionUsingLibSignal(
            libsignalNet: libsignalNet,
            appExpiry: appExpiry,
            appReadiness: appReadiness,
            db: db,
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

    public func waitForIdentifiedConnectionToOpen() async throws(CancellationError) {
        try await self.connectionIdentified.waitForOpen()
    }

    public func waitForUnidentifiedConnectionToOpen() async throws(CancellationError) {
        try await self.connectionUnidentified.waitForOpen()
    }

    public func waitUntilIdentifiedConnectionShouldBeClosed() async throws(CancellationError) {
        try await self.connectionIdentified.waitUntilSocketShouldBeClosed()
    }

    public func requestIdentifiedConnection() -> OWSChatConnection.ConnectionToken {
        return connectionIdentified.requestConnection()
    }

    public func requestUnidentifiedConnection() -> OWSChatConnection.ConnectionToken {
        return connectionUnidentified.requestConnection()
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

    @MainActor
    public var unidentifiedConnectionState: OWSChatConnectionState {
        return connectionUnidentified.currentState
    }

    // This method can be called from any thread.
    public func withUnauthService<Service, Output>(
        _ service: Service,
        do callback: (Service.Api) async throws -> Output,
    ) async throws -> Output where Service: UnauthServiceSelector {
        try await connectionUnidentified.withLibsignalConnection { connection in
            // This force-cast is guaranteed by UnauthServiceSelector only being provided for valid service protocols.
            try await callback(connection as! Service.Api)
        }
    }

    public var hasEmptiedInitialQueue: Bool {
        get async {
            return await connectionIdentified.hasEmptiedInitialQueue
        }
    }

    public func setRegistrationOverride(_ chatServiceAuth: ChatServiceAuth) async {
        await connectionIdentified.setRegistrationOverride(chatServiceAuth)
    }

    public func clearRegistrationOverride() async {
        await connectionIdentified.clearRegistrationOverride()
    }
}

#if TESTABLE_BUILD

public class ChatConnectionManagerMock: ChatConnectionManager {

    public init() {}

    public func updateCanOpenWebSocket() {
    }

    public var hasEmptiedInitialQueue: Bool = false

    public func waitForIdentifiedConnectionToOpen() async throws(CancellationError) {
    }

    public func waitForUnidentifiedConnectionToOpen() async throws(CancellationError) {
    }

    public func waitUntilIdentifiedConnectionShouldBeClosed() async throws(CancellationError) {
    }

    public var unidentifiedConnectionState: OWSChatConnectionState = .closed

    public var shouldWaitForSocketToMakeRequestPerType = [OWSChatConnectionType: Bool]()

    public func requestIdentifiedConnection() -> OWSChatConnection.ConnectionToken {
        fatalError()
    }

    public func requestUnidentifiedConnection() -> OWSChatConnection.ConnectionToken {
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

    public func setRegistrationOverride(_ chatServiceAuth: ChatServiceAuth) async {
    }

    public func clearRegistrationOverride() async {
    }

    public func withUnauthService<Service, Output>(
        _ service: Service,
        do callback: (Service.Api) async throws -> Output,
    ) async throws -> Output where Service: UnauthServiceSelector {
        fatalError("must override for tests")
    }
}

#endif
