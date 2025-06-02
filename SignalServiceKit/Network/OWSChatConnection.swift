//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public enum OWSChatConnectionType: Int, CaseIterable, CustomDebugStringConvertible {
    case identified = 0
    case unidentified = 1

    public var debugDescription: String {
        switch self {
        case .identified:
            return "[type: identified]"
        case .unidentified:
            return "[type: unidentified]"
        }
    }
}

// MARK: -

public enum OWSChatConnectionState: Int, CustomDebugStringConvertible {
    case closed = 0
    case connecting = 1
    case open = 2

    public var debugDescription: String {
        switch self {
        case .closed:
            return "closed"
        case .connecting:
            return "connecting"
        case .open:
            return "open"
        }
    }
}

// MARK: -
public class OWSChatConnection {
    // TODO: Should we use a higher-priority queue?
    fileprivate static let messageProcessingQueue = DispatchQueue(label: "org.signal.chat-connection.message-processing")

    public static let chatConnectionStateDidChange = Notification.Name("chatConnectionStateDidChange")

    fileprivate let serialQueue: DispatchQueue

    // MARK: -

    fileprivate let type: OWSChatConnectionType
    fileprivate let appExpiry: AppExpiry
    fileprivate let appReadiness: AppReadiness
    fileprivate let db: any DB
    fileprivate let accountManager: TSAccountManager
    fileprivate let registrationStateChangeManager: RegistrationStateChangeManager

    // This var must be thread-safe.
    public var currentState: OWSChatConnectionState {
        owsFailDebug("should be using a concrete subclass")
        return .closed
    }

    // This var must be thread-safe.
    public var hasEmptiedInitialQueue: Bool {
        false
    }

    // MARK: - BackgroundKeepAlive

    fileprivate enum BackgroundKeepAliveRequestType {
        case didReceivePush
        case receiveMessage
        case receiveResponse

        var keepAliveDuration: TimeInterval {
            // If the app is in the background, it should keep the
            // websocket open if:
            switch self {
            case .didReceivePush:
                // Received a push notification in the last N seconds.
                return 20
            case .receiveMessage:
                // It has received a message over the socket in the last N seconds.
                return 15
            case .receiveResponse:
                // It has just received the response to a request.
                return 5
            }
        }
    }

    // This method is thread-safe.
    fileprivate func ensureBackgroundKeepAlive(_ requestType: BackgroundKeepAliveRequestType) {
        let connectionToken = requestConnection()
        let backgroundTask = OWSBackgroundTask(label: "connectionKeepAlive") { _ in
            connectionToken.releaseConnection()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + requestType.keepAliveDuration) {
            backgroundTask.end()
        }
    }

    fileprivate var logPrefix: String {
        "[\(type)]"
    }

    // MARK: -

    public init(
        type: OWSChatConnectionType,
        accountManager: TSAccountManager,
        appExpiry: AppExpiry,
        appReadiness: AppReadiness,
        db: any DB,
        registrationStateChangeManager: RegistrationStateChangeManager
    ) {
        AssertIsOnMainThread()

        self.serialQueue = DispatchQueue(label: "org.signal.chat-connection-\(type)")
        self.type = type
        self.appExpiry = appExpiry
        self.appReadiness = appReadiness
        self.db = db
        self.accountManager = accountManager
        self.registrationStateChangeManager = registrationStateChangeManager

        appReadiness.runNowOrWhenAppDidBecomeReadySync { [weak self] in
            self?.appDidBecomeReady()
        }
    }

    // MARK: - Notifications

    // We want to observe these notifications lazily to avoid accessing
    // the data store in [application: didFinishLaunchingWithOptions:].
    fileprivate func appDidBecomeReady() {
        AssertIsOnMainThread()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(isCensorshipCircumventionActiveDidChange),
                                               name: .isCensorshipCircumventionActiveDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(isSignalProxyReadyDidChange),
                                               name: .isSignalProxyReadyDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(storiesEnabledStateDidChange), name: .storiesEnabledStateDidChange, object: nil)

        // Enable the connection whenever it's allowed.
        updateCanOpenWebSocket()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(registrationStateDidChange),
            name: .registrationStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appExpiryDidChange),
            name: AppExpiry.AppExpiryDidChange,
            object: nil
        )

        // Request it whenever the app's active.
        if CurrentAppContext().isMainAppAndActive {
            self.appActiveConnectionToken = self.requestConnection()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: .OWSApplicationWillResignActive,
            object: nil
        )
    }

    // MARK: -

    private struct StateObservation {
        var currentState: OWSChatConnectionState
        var onOpen: [NSObject: CancellableContinuation<Void>]
    }

    /// This lock is sometimes waited on within an async context; make sure *all* uses release the lock quickly.
    private let stateObservation = AtomicValue(
        StateObservation(currentState: .closed, onOpen: [:]),
        lock: .init()
    )

    fileprivate func notifyStatusChange(newState: OWSChatConnectionState) {
        // Technically this would be safe to call from anywhere,
        // but requiring it to be on the serial queue means it's less likely
        // for a caller to check a condition that's immediately out of date (a race).
        assertOnQueue(serialQueue)

        let (oldState, continuationsToResolve): (OWSChatConnectionState, [NSObject: CancellableContinuation<Void>])
        (oldState, continuationsToResolve) = stateObservation.update {
            let oldState = $0.currentState
            if newState == oldState {
                return (oldState, [:])
            }
            $0.currentState = newState

            var continuationsToResolve: [NSObject: CancellableContinuation<Void>] = [:]
            if case .open = newState {
                continuationsToResolve = $0.onOpen
                $0.onOpen = [:]
            }

            return (oldState, continuationsToResolve)
        }
        if newState != oldState {
            Logger.info("\(logPrefix): \(oldState) -> \(newState)")
        }
        for (_, waiter) in continuationsToResolve {
            waiter.resume(with: .success(()))
        }
        NotificationCenter.default.postOnMainThread(name: Self.chatConnectionStateDidChange, object: nil)
    }

    fileprivate var cachedCurrentState: OWSChatConnectionState {
        stateObservation.get().currentState
    }

    /// Only throws on cancellation.
    func waitForOpen() async throws {
        let cancellationToken = NSObject()
        let cancellableContinuation = CancellableContinuation<Void>()
        stateObservation.update {
            if $0.currentState == .open {
                cancellableContinuation.resume(with: .success(()))
            } else {
                $0.onOpen[cancellationToken] = cancellableContinuation
            }
        }
        try await withTaskCancellationHandler(
            operation: cancellableContinuation.wait,
            onCancel: {
                // Don't cancel because CancellableContinuation does that.
                // We just clean up the state so that we don't leak memory.
                stateObservation.update { _ = $0.onOpen.removeValue(forKey: cancellationToken) }
            }
        )
    }

    private func waitForOpen(timeout: TimeInterval) async {
        _ = try? await withCooperativeTimeout(
            seconds: timeout,
            operation: { try await self.waitForOpen() }
        )
    }

    // MARK: - Socket LifeCycle

    public static var canAppUseSocketsToMakeRequests: Bool {
        return CurrentAppContext().isMainApp
    }

    public var canOpenWebSocket: Bool {
        return serialQueue.sync { self.canOpenWebSocketError == nil }
    }

    /// Tracks app-wide, "fatal" errors that block web sockets.
    ///
    /// If this property is nonnil, the app shouldn't attempt to open a
    /// connection to the server. If `makeRequest` is called while this property
    /// is nonnil, the request will fail with this error.
    ///
    /// This property is used for "fatal" errors: "the user isn't registered",
    /// "the app has expired", "this extension doesn't ever use web sockets",
    /// etc. Transient errors ("no network", "the server returned a 5xx", etc.)
    /// don't use this property.
    ///
    /// Must be accessed on `serialQueue`.
    private var canOpenWebSocketError: OWSHTTPError? = .networkFailure(.genericFailure)

    private func updateCanOpenWebSocket() {
        serialQueue.async(_updateCanOpenWebSocket)
    }

    private func _updateCanOpenWebSocket() {
        assertOnQueue(serialQueue)
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        let oldValue = (canOpenWebSocketError == nil)
        canOpenWebSocketError = {
            guard !appExpiry.isExpired(now: Date()) else {
                return .invalidAppState
            }
            guard Self.canAppUseSocketsToMakeRequests else {
                return .networkFailure(.genericFailure)
            }
            guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
                return .networkFailure(.genericFailure)
            }
            return nil
        }()
        let newValue = (canOpenWebSocketError == nil)
        if newValue != oldValue {
            _applyDesiredSocketState()
        }
    }

    public final class ConnectionToken {
        private let tokenId: Int
        private weak var chatConnection: OWSChatConnection?

        fileprivate init(tokenId: Int, chatConnection: OWSChatConnection) {
            self.tokenId = tokenId
            self.chatConnection = chatConnection
        }

        deinit {
            guard let chatConnection else {
                return
            }
            let didRelease = chatConnection.releaseConnection(self.tokenId)
            owsAssertDebug(!didRelease, "You must explicitly call releaseConnection().")
        }

        public func releaseConnection() {
            guard let chatConnection else {
                return
            }
            let didRelease = chatConnection.releaseConnection(self.tokenId)
            owsAssertDebug(didRelease, "You can't call releaseConnection() multiple times.")
        }
    }

    struct ConnectionTokenState {
        var tokenId = 0
        var activeTokenIds = Set<Int>()
    }

    private let connectionTokenState = AtomicValue(ConnectionTokenState(), lock: .init())

    public func requestConnection() -> ConnectionToken {
        let (connectionToken, shouldConnect) = connectionTokenState.update {
            $0.tokenId += 1
            let shouldConnect = $0.activeTokenIds.isEmpty
            $0.activeTokenIds.insert($0.tokenId)
            let connectionToken = ConnectionToken(tokenId: $0.tokenId, chatConnection: self)
            return (connectionToken, shouldConnect)
        }
        if shouldConnect {
            applyDesiredSocketState()
        }
        return connectionToken
    }

    private func releaseConnection(_ tokenId: Int) -> Bool {
        let (didRelease, shouldDisconnect) = connectionTokenState.update {
            let didRelease = $0.activeTokenIds.remove(tokenId) != nil
            return (didRelease, $0.activeTokenIds.isEmpty)
        }
        if shouldDisconnect {
            applyDesiredSocketState()
        }
        return didRelease
    }

    // This method is thread-safe.
    public func didReceivePush() {
        owsAssertDebug(appReadiness.isAppReady)

        self.ensureBackgroundKeepAlive(.didReceivePush)
    }

    // This method aligns the socket state with the "desired" socket state.
    //
    // This method is thread-safe.
    fileprivate final func applyDesiredSocketState() {
        serialQueue.async(self._applyDesiredSocketState)
    }

    fileprivate final func _applyDesiredSocketState() {
        assertOnQueue(serialQueue)

        let shouldSocketBeOpen: Bool = (
            (canOpenWebSocketError == nil)
            && connectionTokenState.update { !$0.activeTokenIds.isEmpty }
        )
        if shouldSocketBeOpen {
            owsPrecondition(appReadiness.isAppReady)
            ensureWebsocketExists()
        } else {
            disconnectIfNeeded()
        }
    }

    // This method must be thread-safe.
    fileprivate func cycleSocket() {
        serialQueue.async {
            self.disconnectIfNeeded()
            self._applyDesiredSocketState()
        }
    }

    fileprivate func ensureWebsocketExists() {
        assertOnQueue(serialQueue)
        owsFailDebug("should be using a concrete subclass")
    }

    fileprivate func disconnectIfNeeded() {
        assertOnQueue(serialQueue)
        owsFailDebug("should be using a concrete subclass")
    }

    // MARK: - Notifications

    private var appActiveConnectionToken: ConnectionToken?

    @objc
    private func applicationDidBecomeActive(_ notification: NSNotification) {
        AssertIsOnMainThread()

        appActiveConnectionToken?.releaseConnection()
        appActiveConnectionToken = requestConnection()
    }

    @objc
    private func applicationWillResignActive(_ notification: NSNotification) {
        AssertIsOnMainThread()

        appActiveConnectionToken?.releaseConnection()
        appActiveConnectionToken = nil
    }

    @objc
    fileprivate func registrationStateDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        updateCanOpenWebSocket()
    }

    @objc
    fileprivate func isCensorshipCircumventionActiveDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        cycleSocket()
    }

    @objc
    fileprivate func isSignalProxyReadyDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        guard SignalProxy.isEnabledAndReady else {
            // When we tear down the relay, everything gets canceled.
            return
        }
        // When we start the relay, we need to reconnect.
        cycleSocket()
    }

    @objc
    private func appExpiryDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        updateCanOpenWebSocket()
    }

    @objc
    fileprivate func storiesEnabledStateDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        cycleSocket()
    }

    // MARK: - Message Sending

    func makeRequest(_ request: TSRequest) async throws -> HTTPResponse {
        owsAssertDebug(Self.canAppUseSocketsToMakeRequests)

        let requestId = UInt64.random(in: .min ... .max)
        let requestDescription = "\(request) [\(requestId)]"
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                self.serialQueue.async {
                    if let canOpenWebSocketError = self.canOpenWebSocketError {
                        continuation.resume(throwing: canOpenWebSocketError)
                    } else {
                        continuation.resume()
                    }
                }
            }

            // After 30 seconds, we try anyways. We'll probably fail.
            await waitForOpen(timeout: 30)

            Logger.info("Sending… -> \(requestDescription)")

            let backgroundTask = OWSBackgroundTask(label: #function)
            defer { backgroundTask.end() }

            let response = try await self.makeRequestInternal(request, requestId: requestId)

            Logger.info("HTTP \(response.responseStatusCode) <- \(requestDescription)")

            OutageDetection.shared.reportConnectionSuccess()
            return response
        } catch {
            if let statusCode = error.httpStatusCode {
                Logger.warn("HTTP \(statusCode) <- \(requestDescription)")
            } else {
                Logger.warn("Failure. <- \(requestDescription): \(error)")
            }
            throw error
        }
    }

    fileprivate func makeRequestInternal(_ request: TSRequest, requestId: UInt64) async throws(OWSHTTPError) -> any HTTPResponse {
        owsFail("must be using a concrete subclass")
    }

    fileprivate final func handleRequestResponse(
        requestUrl: URL,
        responseStatus: Int,
        responseHeaders: HttpHeaders,
        responseData: Data?
    ) async throws(OWSHTTPError) -> HTTPResponse {
        if (200...299).contains(responseStatus) {
            let response = HTTPResponseImpl(
                requestUrl: requestUrl,
                status: responseStatus,
                headers: responseHeaders,
                bodyData: responseData
            )
            return response
        } else {
            let error = await HTTPUtils.preprocessMainServiceHTTPError(
                requestUrl: requestUrl,
                responseStatus: responseStatus,
                responseHeaders: responseHeaders,
                responseData: responseData
            )
            throw error
        }
    }

    // MARK: - Reconnect

    fileprivate static let socketReconnectDelay: TimeInterval = 5
}

// MARK: -

internal class OWSChatConnectionUsingLibSignal<Connection: ChatConnection>: OWSChatConnection, ConnectionEventsListener {
    fileprivate let libsignalNet: Net

    fileprivate enum ConnectionState {
        case closed
        case connecting(token: NSObject, task: Task<Connection?, Never>)
        case open(Connection)

        var asExternalState: OWSChatConnectionState {
            switch self {
            case .closed: .closed
            case .connecting(token: _, task: _): .connecting
            case .open(_): .open
            }
        }

        func isCurrentlyConnecting(_ token: NSObject) -> Bool {
            guard case .connecting(token: let activeToken, task: _) = self else {
                return false
            }
            return activeToken === token
        }

        func isActive(_ connection: Connection) -> Bool {
            guard case .open(let activeConnection) = self else {
                return false
            }
            return activeConnection === connection
        }

        func waitToFinishConnecting(cancel: Bool = false) async -> Connection? {
            switch self {
            case .closed:
                return nil
            case .connecting(token: _, task: let task):
                if cancel {
                    task.cancel()
                }
                return await task.value
            case .open(let connection):
                return connection
            }
        }
    }

    private var _connection: ConnectionState = .closed
    fileprivate var connection: ConnectionState {
        get {
            assertOnQueue(serialQueue)
            return _connection
        }
        set {
            assertOnQueue(serialQueue)
            _connection = newValue
            notifyStatusChange(newState: newValue.asExternalState)
        }
    }

    internal init(libsignalNet: Net, type: OWSChatConnectionType, accountManager: TSAccountManager, appExpiry: AppExpiry, appReadiness: AppReadiness, db: any DB, registrationStateChangeManager: RegistrationStateChangeManager) {
        self.libsignalNet = libsignalNet
        super.init(type: type, accountManager: accountManager, appExpiry: appExpiry, appReadiness: appReadiness, db: db, registrationStateChangeManager: registrationStateChangeManager)
    }

    fileprivate func connectChatService() async throws -> Connection {
        fatalError("must be overridden by subclass")
    }

    fileprivate override func isSignalProxyReadyDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()
        // The libsignal connection needs to be recreated whether the proxy is going up,
        // changing, or going down.
        cycleSocket()
    }

    fileprivate override func ensureWebsocketExists() {
        assertOnQueue(serialQueue)

        switch connection {
        case .open(_):
            return
        case .connecting(_, _):
            // The most recent transition was attempting to connect, and we have not yet observed a failure.
            // That's as good as we're going to get.
            return
        case .closed:
            break
        }

        // Unique while live.
        let token = NSObject()
        connection = .connecting(token: token, task: Task { [token] in
            func connectionAttemptCompleted(_ state: ConnectionState) async -> Connection? {
                // We're not done until self.connection has been updated.
                // (Otherwise, we might try to send requests before calling start(listener:).)
                return await withCheckedContinuation { continuation in
                    self.serialQueue.async {
                        guard self.connection.isCurrentlyConnecting(token) else {
                            // We finished connecting, but we've since been asked to disconnect
                            // (either because we should be offline, or because config has changed).
                            continuation.resume(returning: nil)
                            return
                        }

                        self.connection = state

                        if case .open(let connection) = state {
                            continuation.resume(returning: connection)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }

            do {
                let chatService = try await self.connectChatService()
                if type == .identified {
                    self.didConnectIdentified()
                }
                OutageDetection.shared.reportConnectionSuccess()
                return await connectionAttemptCompleted(.open(chatService))

            } catch is CancellationError {
                // We've been asked to disconnect, no other action necessary.
                // (We could even skip updating state, since the disconnect action should have already set it to "closed",
                // but just in case it's still on "connecting" we'll continue on to execute that cleanup.)
            } catch SignalError.appExpired(_) {
                await appExpiry.setHasAppExpiredAtCurrentVersion(db: db)
            } catch SignalError.deviceDeregistered(_) {
                serialQueue.async {
                    if self.connection.isCurrentlyConnecting(token) {
                        self.db.write { tx in
                            self.registrationStateChangeManager.setIsDeregisteredOrDelinked(true, tx: tx)
                        }
                    }
                }
            } catch {
                Logger.error("\(self.logPrefix): failed to connect: \(error)")
                OutageDetection.shared.reportConnectionFailure()
            }

            // Only failure cases get here.
            return await connectionAttemptCompleted(.closed)
        })
    }

    fileprivate func didConnectIdentified() {
        // Overridden by subclass.
    }

    fileprivate override func disconnectIfNeeded() {
        assertOnQueue(serialQueue)

        let previousConnection = connection
        if case .closed = previousConnection {
            // Either we are already disconnecting,
            // or we finished disconnecting,
            // or we were never connected to begin with.
            return
        }
        connection = .closed

        // Spin off a background task to disconnect the previous connection.
        _ = Task {
            do {
                try await previousConnection.waitToFinishConnecting(cancel: true)?.disconnect()
            } catch {
                Logger.warn("\(self.logPrefix): error while disconnecting: \(error)")
            }
        }
    }

    public override var currentState: OWSChatConnectionState {
        // We update cachedCurrentState based on lifecycle events,
        // so this should be accurate (with the usual caveats about races).
        return cachedCurrentState
    }

    fileprivate override var logPrefix: String {
        "[\(type): libsignal]"
    }

    fileprivate override func makeRequestInternal(_ request: TSRequest, requestId: UInt64) async throws(OWSHTTPError) -> any HTTPResponse {
        var httpHeaders = request.headers
        httpHeaders.addDefaultHeaders()
        request.applyAuth(to: &httpHeaders, willSendViaWebSocket: true)

        let body: Data
        switch request.body {
        case .data(let bodyData):
            body = bodyData
        case .parameters(let bodyParameters):
            // TODO: Do we need body & headers for requests with no parameters?
            do {
                body = try TSRequest.Body.encodedParameters(bodyParameters)
            } catch {
                owsFailDebug("[\(requestId)]: \(error).")
                throw .invalidRequest
            }

            // If we're going to use the json serialized parameters as our body, we should overwrite
            // the Content-Type on the request.
            httpHeaders["Content-Type"] = "application/json"
        }

        let requestUrl = request.url
        owsAssertDebug(requestUrl.scheme == nil)
        owsAssertDebug(requestUrl.host == nil)
        owsAssertDebug(!requestUrl.path.hasPrefix("/"))

        guard let httpMethod = request.method.nilIfEmpty else {
            throw .invalidRequest
        }

        let libsignalRequest = ChatConnection.Request(method: httpMethod, pathAndQuery: "/\(requestUrl.relativeString)", headers: httpHeaders.headers, body: body, timeout: request.timeoutInterval)

        let connection = await withCheckedContinuation { continuation in
            self.serialQueue.async { continuation.resume(returning: self.connection) }
        }
        let chatService = await connection.waitToFinishConnecting()

        let connectionInfo: ConnectionInfo
        let response: ChatConnection.Response
        do {
            guard let chatService else {
                throw SignalError.chatServiceInactive("no connection to chat server")
            }

            connectionInfo = chatService.info()
            response = try await chatService.send(libsignalRequest)
        } catch {
            switch error as? SignalError {
            case .connectionTimeoutError(_), .requestTimeoutError(_):
                // cycleSocket(), but only if the chatService we just used is the one that's still connected.
                self.serialQueue.async { [weak chatService] in
                    if let chatService, self.connection.isActive(chatService) {
                        self.disconnectIfNeeded()
                    }
                }
                applyDesiredSocketState()
                throw .networkFailure(.genericTimeout)
            case .webSocketError(_), .connectionFailed(_):
                throw .networkFailure(.genericFailure)
            default:
                owsFailDebug("[\(requestId)] failed with an unexpected error: \(error)")
                throw .networkFailure(.genericFailure)
            }
        }

        if DebugFlags.internalLogging {
            Logger.info("received response for requestId: \(requestId), message: \(response.message), route: \(connectionInfo)")
        }

#if TESTABLE_BUILD
        if response.status/100 != 2 {
            HTTPUtils.logCurl(for: request)
        }
#endif

        self.ensureBackgroundKeepAlive(.receiveResponse)

        let headers = HttpHeaders(httpHeaders: response.headers, overwriteOnConflict: false)
        return try await handleRequestResponse(
            requestUrl: request.url,
            responseStatus: Int(response.status),
            responseHeaders: headers,
            responseData: response.body
        )
    }

    func connectionWasInterrupted(_ service: Connection, error: Error?) {
        self.serialQueue.async { [self] in
            guard connection.isActive(service) else {
                // Already done with this service.
                if let error {
                    Logger.warn("\(logPrefix) previous service was disconnected: \(error)")
                }
                return
            }

            if let error {
                Logger.error("\(logPrefix) disconnected: \(error)")
            } else {
                owsFailDebug("\(logPrefix) libsignal disconnected us without being asked")
            }

            connection = .closed

            // Wait a few seconds before retrying to reduce server load.
            self.serialQueue.asyncAfter(deadline: .now() + Self.socketReconnectDelay) { [weak self] in
                self?._applyDesiredSocketState()
            }

            OutageDetection.shared.reportConnectionFailure()
        }
    }
}

internal class OWSUnauthConnectionUsingLibSignal: OWSChatConnectionUsingLibSignal<UnauthenticatedChatConnection> {
    init(libsignalNet: Net, accountManager: TSAccountManager, appExpiry: AppExpiry, appReadiness: AppReadiness, db: any DB, registrationStateChangeManager: RegistrationStateChangeManager) {
        super.init(libsignalNet: libsignalNet, type: .unidentified, accountManager: accountManager, appExpiry: appExpiry, appReadiness: appReadiness, db: db, registrationStateChangeManager: registrationStateChangeManager)
    }

    fileprivate override var connection: ConnectionState {
        didSet {
            if case .open(let service) = connection {
                service.start(listener: self)
            }
        }
    }

    override func connectChatService() async throws -> UnauthenticatedChatConnection {
        return try await libsignalNet.connectUnauthenticatedChat()
    }
}

internal class OWSAuthConnectionUsingLibSignal: OWSChatConnectionUsingLibSignal<AuthenticatedChatConnection>, ChatConnectionListener {
    private let _hasEmptiedInitialQueue = AtomicBool(false, lock: .sharedGlobal)
    override var hasEmptiedInitialQueue: Bool {
        _hasEmptiedInitialQueue.get()
    }

    private var _keepaliveSenderTask: Task<Void, Never>?
    private var keepaliveSenderTask: Task<Void, Never>? {
        get {
            assertOnQueue(serialQueue)
            return _keepaliveSenderTask
        }
        set {
            assertOnQueue(serialQueue)
            _keepaliveSenderTask?.cancel()
            _keepaliveSenderTask = newValue
        }
    }

    init(libsignalNet: Net, accountManager: TSAccountManager, appExpiry: AppExpiry, appReadiness: AppReadiness, db: any DB, registrationStateChangeManager: RegistrationStateChangeManager) {
        super.init(libsignalNet: libsignalNet, type: .identified, accountManager: accountManager, appExpiry: appExpiry, appReadiness: appReadiness, db: db, registrationStateChangeManager: registrationStateChangeManager)
    }

    fileprivate override func connectChatService() async throws -> AuthenticatedChatConnection {
        let (username, password) = db.read { tx in
            (accountManager.storedServerUsername(tx: tx), accountManager.storedServerAuthToken(tx: tx))
        }
        // Note that we still try to connect for an unregistered user, so that we get a consistent error thrown.
        return try await libsignalNet.connectAuthenticatedChat(username: username ?? "", password: password ?? "", receiveStories: StoryManager.areStoriesEnabled)
    }

    fileprivate override var connection: ConnectionState {
        didSet {
            assertOnQueue(serialQueue)

            switch connection {
            case .connecting(token: _, task: _):
                break
            case .open(let service):
                // Note that we don't get callbacks until this point.
                service.start(listener: self)
                if accountManager.registrationStateWithMaybeSneakyTransaction.isDeregistered {
                    db.write { tx in
                        registrationStateChangeManager.setIsDeregisteredOrDelinked(false, tx: tx)
                    }
                }
                keepaliveSenderTask = makeKeepaliveTask(service)
            case .closed:
                // While _hasEmptiedInitialQueue is atomic, that's not sufficient to guarantee the
                // *order* of writes. We do that by making sure we only set it on the serial queue,
                // and then make sure libsignal's serialized callbacks result in scheduling on the
                // serial queue.
                keepaliveSenderTask = nil
                _hasEmptiedInitialQueue.set(false)
                Logger.debug("Reset _hasEmptiedInitialQueue")
            }
        }
    }

    /// Starts a task to call `/v1/keepalive` at regular intervals to allow the server to do some consistency checks.
    ///
    /// This is on top of the websocket pings libsignal already uses to keep connections alive.
    func makeKeepaliveTask(_ chat: AuthenticatedChatConnection) -> Task<Void, Never> {
        let keepaliveInterval: TimeInterval = 30
        return Task(priority: .low) { [logPrefix = self.logPrefix, weak chat] in
            while true {
                do {
                    // This does not quite send keepalives "every 30 seconds".
                    // Instead, it sends the next keepalive *at least 30 seconds* after the *response* for the previous one arrives.
                    try await Task.sleep(nanoseconds: keepaliveInterval.clampedNanoseconds)
                    guard let chat else {
                        // We've disconnected.
                        return
                    }

                    // Skip the full overhead of makeRequest(...).
                    // We don't need keepalives to count as background activity or anything like that.
                    var httpHeaders = HttpHeaders()
                    httpHeaders.addDefaultHeaders()
                    // This 30-second timeout doesn't inherently need to match the send interval above,
                    // but neither do we need an especially tight timeout here either.
                    let request = ChatConnection.Request(method: "GET", pathAndQuery: "/v1/keepalive", headers: httpHeaders.headers, body: nil, timeout: 30)
                    Logger.debug("\(logPrefix) Sending /v1/keepalive")
                    _ = try await chat.send(request)

                } catch is CancellationError,
                        SignalError.chatServiceInactive(_) {
                    // No action necessary, we're done with this service.
                    return
                } catch SignalError.rateLimitedError(retryAfter: let delay, message: _) {
                    // Not likely to happen, but best to be careful about it if it does.
                    if delay > keepaliveInterval {
                        // Wait out the part of the delay longer than 30s.
                        // Ignore cancellation here; when we get back to the top of the loop we'll check it then.
                        _ = try? await Task.sleep(nanoseconds: (delay - keepaliveInterval).clampedNanoseconds)
                    }
                } catch {
                    // Also no action necessary! Log just in case the failure has something interesting going on,
                    // but continue to rely on libsignal reporting disconnects via delegate callback.
                    // Importantly, we will continue to send keepalives until disconnected, in case this was a temporary thing.
                    Logger.info("\(logPrefix) /v1/keepalive failed: \(error)")
                }
            }
        }
    }

    func chatConnection(_ chat: AuthenticatedChatConnection, didReceiveAlerts alerts: [String]) {
        self.serialQueue.async { [self] in
            guard self.connection.isActive(chat) else {
                // We have since disconnected from the chat service instance that reported the alerts.
                return
            }

            if !alerts.isEmpty {
                Logger.warn("ignoring \(alerts.count) alerts from the server")
            }
        }
    }

    func chatConnection(_ chat: AuthenticatedChatConnection, didReceiveIncomingMessage envelope: Data, serverDeliveryTimestamp: UInt64, sendAck: @escaping () throws -> Void) {
        ensureBackgroundKeepAlive(.receiveMessage)
        let backgroundTask = OWSBackgroundTask(label: "handleIncomingMessage")

        Self.messageProcessingQueue.async {
            SSKEnvironment.shared.messageProcessorRef.processReceivedEnvelopeData(
                envelope,
                serverDeliveryTimestamp: serverDeliveryTimestamp,
                envelopeSource: .websocketIdentified
            ) {
                defer { backgroundTask.end() }

                do {
                    // Note that this does not wait for a response.
                    try sendAck()
                } catch {
                    Logger.warn("Failed to ack message with serverTimestamp \(serverDeliveryTimestamp): \(error)")
                }
            }
        }
    }

    func chatConnectionDidReceiveQueueEmpty(_ chat: AuthenticatedChatConnection) {
        // We need to "flush" (i.e., "jump through") the message processing queue
        // to ensure that all received messages (see prior method) are enqueued for
        // processing before we: a) mark the queue as empty, b) notify.
        //
        // The socket might close and re-open while we're flushing the queue, so
        // we make sure it's still active before marking the queue as empty.
        Self.messageProcessingQueue.async {
            self.serialQueue.async {
                guard self.connection.isActive(chat) else {
                    // We have since disconnected from the chat service instance that reported the empty queue.
                    return
                }
                let alreadyEmptied = self._hasEmptiedInitialQueue.swap(true)
                Logger.debug("Initial queue emptied")

                if !alreadyEmptied {
                    // This notification is used to wake up anything waiting for hasEmptiedInitialQueue.
                    self.notifyStatusChange(newState: self.currentState)
                }
            }
        }
    }
}
