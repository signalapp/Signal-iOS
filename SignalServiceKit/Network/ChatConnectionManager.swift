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

    func canMakeRequests(connectionType: OWSChatConnectionType) -> Bool
    func makeRequest(_ request: TSRequest) async throws -> HTTPResponse

    func didReceivePush()
}

public class ChatConnectionManagerImpl: ChatConnectionManager {
    private let connectionIdentified: OWSChatConnection
    private let connectionUnidentified: OWSChatConnection
    private var connections: [OWSChatConnection] { [ connectionIdentified, connectionUnidentified ]}

    public init(accountManager: TSAccountManager, appExpiry: AppExpiry, appReadiness: AppReadiness, currentCallProvider: any CurrentCallProvider, db: any DB, libsignalNet: Net, registrationStateChangeManager: RegistrationStateChangeManager, userDefaults: UserDefaults) {
        AssertIsOnMainThread()
        if userDefaults.bool(forKey: Self.shouldUseLibsignalForIdentifiedDefaultsKey) {
            connectionIdentified = OWSAuthConnectionUsingLibSignal(libsignalNet: libsignalNet, accountManager: accountManager, appExpiry: appExpiry, appReadiness: appReadiness, currentCallProvider: currentCallProvider, db: db, registrationStateChangeManager: registrationStateChangeManager)
        } else {
            connectionIdentified = OWSChatConnectionUsingSSKWebSocket(
                type: .identified,
                accountManager: accountManager,
                appExpiry: appExpiry,
                appReadiness: appReadiness,
                currentCallProvider: currentCallProvider,
                db: db,
                registrationStateChangeManager: registrationStateChangeManager
            )
        }

        if userDefaults.bool(forKey: Self.shouldUseLibsignalForUnidentifiedDefaultsKey) {
            connectionUnidentified = OWSUnauthConnectionUsingLibSignal(libsignalNet: libsignalNet, accountManager: accountManager, appExpiry: appExpiry, appReadiness: appReadiness, currentCallProvider: currentCallProvider, db: db, registrationStateChangeManager: registrationStateChangeManager)
        } else if userDefaults.bool(forKey: Self.enableShadowingDefaultsKey) {
            let shadowingConnection = OWSChatConnectionWithLibSignalShadowing(
                libsignalNet: libsignalNet,
                type: .unidentified,
                accountManager: accountManager,
                appExpiry: appExpiry,
                appReadiness: appReadiness,
                currentCallProvider: currentCallProvider,
                db: db,
                registrationStateChangeManager: registrationStateChangeManager,
                shadowingFrequency: 0.0
            )
            // RemoteConfig isn't available while we're still setting up singletons,
            // so we might not shadow the first few requests.
            appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
                let frequency = RemoteConfig.current.experimentalTransportShadowingHigh ? 1.0 : 0.1
                Logger.info("Using unauth OWSChatConnectionWithLibSignalShadowing, shadowing frequency \(frequency)")
                shadowingConnection.updateShadowingFrequency(frequency)
            }
            connectionUnidentified = shadowingConnection
        } else {
            connectionUnidentified = OWSChatConnectionUsingSSKWebSocket(type: .unidentified, accountManager: accountManager, appExpiry: appExpiry, appReadiness: appReadiness, currentCallProvider: currentCallProvider, db: db, registrationStateChangeManager: registrationStateChangeManager)
        }

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
        let maxWaitInterval = 30 * kSecondInterval
        _ = try? await withCooperativeTimeout(
            seconds: maxWaitInterval,
            operation: { try await connection.waitForOpen() }
        )
    }

    // This method can be called from any thread.
    public func makeRequest(_ request: TSRequest) async throws -> HTTPResponse {
        let connectionType: OWSChatConnectionType = {
            if request.isUDRequest {
                return .unidentified
            } else if !request.shouldHaveAuthorizationHeaders {
                return .unidentified
            } else {
                return .identified
            }
        }()

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

    // MARK: -

    private static var enableShadowingDefaultsKey: String = "EnableShadowingForUnidentifiedWebsocket"

    /// We cache this in UserDefaults because it's used too early to access the RemoteConfig object.
    static func saveEnableShadowingForUnidentifiedWebsocket(
        _ enableShadowingForUnidentifiedWebsocket: Bool,
        in defaults: UserDefaults
    ) {
        defaults.set(enableShadowingForUnidentifiedWebsocket, forKey: enableShadowingDefaultsKey)
    }

    private static var shouldUseLibsignalForUnidentifiedDefaultsKey: String = "UseLibsignalForUnidentifiedWebsocket"

    /// We cache this in UserDefaults because it's used too early to access the RemoteConfig object.
    ///
    /// It also makes it possible to override the setting in Xcode via the Scheme settings:
    /// add the arguments "-UseLibsignalForUnidentifiedWebsocket YES" to the invocation of the app.
    static func saveShouldUseLibsignalForUnidentifiedWebsocket(
        _ shouldUseLibsignalForUnidentifiedWebsocket: Bool,
        in defaults: UserDefaults
    ) {
        defaults.set(shouldUseLibsignalForUnidentifiedWebsocket, forKey: shouldUseLibsignalForUnidentifiedDefaultsKey)
    }

    private static var shouldUseLibsignalForIdentifiedDefaultsKey: String = "UseLibsignalForIdentifiedWebsocket"

    /// We cache this in UserDefaults because it's used too early to access the RemoteConfig object.
    ///
    /// It also makes it possible to override the setting in Xcode via the Scheme settings:
    /// add the arguments "-UseLibsignalForIdentifiedWebsocket YES" to the invocation of the app.
    static func saveShouldUseLibsignalForIdentifiedWebsocket(
        _ shouldUseLibsignalForIdentifiedWebsocket: Bool,
        in defaults: UserDefaults
    ) {
        defaults.set(shouldUseLibsignalForIdentifiedWebsocket, forKey: shouldUseLibsignalForIdentifiedDefaultsKey)
    }
}

#if TESTABLE_BUILD

public class ChatConnectionManagerMock: ChatConnectionManager {

    public init() {}

    public var hasEmptiedInitialQueue: Bool = false

    public func waitForIdentifiedConnectionToOpen() async throws {
    }

    public var identifiedConnectionState: OWSChatConnectionState = .closed

    public var canMakeRequestsPerType = [OWSChatConnectionType: Bool]()

    public func canMakeRequests(connectionType: OWSChatConnectionType) -> Bool {
        return canMakeRequestsPerType[connectionType] ?? true
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
