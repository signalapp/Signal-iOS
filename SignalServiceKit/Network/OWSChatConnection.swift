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
    enum AlertType: String {
        case idlePrimaryDevice = "idle-primary-device"
    }

    // TODO: Should we use a higher-priority queue?
    fileprivate static let messageProcessingQueue = DispatchQueue(label: "org.signal.chat-connection.message-processing")

    public static let chatConnectionStateDidChange = Notification.Name("chatConnectionStateDidChange")
    public static let chatConnectionStateKey: String = "chatConnectionState"

    fileprivate let serialQueue: DispatchQueue

    // MARK: -

    fileprivate let type: OWSChatConnectionType
    fileprivate let appExpiry: AppExpiry
    fileprivate let appReadiness: AppReadiness
    fileprivate let db: any DB
    fileprivate let accountManager: TSAccountManager
    fileprivate let registrationStateChangeManager: RegistrationStateChangeManager
    fileprivate let inactivePrimaryDeviceStore: InactivePrimaryDeviceStore

    // This var must be thread-safe.
    public var currentState: OWSChatConnectionState {
        owsFailDebug("should be using a concrete subclass")
        return .closed
    }

    public var hasEmptiedInitialQueue: Bool {
        get async {
            return false
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
        registrationStateChangeManager: RegistrationStateChangeManager,
        inactivePrimaryDeviceStore: InactivePrimaryDeviceStore
    ) {
        AssertIsOnMainThread()

        self.serialQueue = DispatchQueue(label: "org.signal.chat-connection-\(type)")
        self.type = type
        self.appExpiry = appExpiry
        self.appReadiness = appReadiness
        self.db = db
        self.accountManager = accountManager
        self.registrationStateChangeManager = registrationStateChangeManager
        self.inactivePrimaryDeviceStore = inactivePrimaryDeviceStore

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
    }

    // MARK: -

    private struct StateObservation {
        var currentState: OWSChatConnectionState
        var onOpen: [NSObject: Monitor.Continuation]
    }

    /// This lock is sometimes waited on within an async context; make sure *all* uses release the lock quickly.
    private let stateObservation = AtomicValue(
        StateObservation(currentState: .closed, onOpen: [:]),
        lock: .init()
    )

    private let openCondition = Monitor.Condition<StateObservation>(
        isSatisfied: { $0.currentState == .open },
        waiters: \.onOpen,
    )

    fileprivate func notifyStatusChange(newState: OWSChatConnectionState) {
        // Technically this would be safe to call from anywhere,
        // but requiring it to be on the serial queue means it's less likely
        // for a caller to check a condition that's immediately out of date (a race).
        assertOnQueue(serialQueue)

        let oldState = Monitor.updateAndNotify(
            in: stateObservation,
            block: {
                let oldState = $0.currentState
                $0.currentState = newState
                return oldState
            },
            conditions: openCondition,
        )
        if newState != oldState {
            Logger.info("\(logPrefix): \(oldState) -> \(newState)")
        }
        NotificationCenter.default.postOnMainThread(
            name: Self.chatConnectionStateDidChange,
            object: nil,
            userInfo: [Self.chatConnectionStateKey: newState],
        )
    }

    fileprivate var cachedCurrentState: OWSChatConnectionState {
        stateObservation.get().currentState
    }

    func waitForOpen() async throws(CancellationError) {
        try await Monitor.waitForCondition(openCondition, in: stateObservation)
    }

    /// Only throws on cancellation or after timeout.
    private func waitForOpen(timeout: TimeInterval) async throws {
        do {
            _ = try await withCooperativeTimeout(
                seconds: timeout,
                operation: { try await self.waitForOpen() }
            )
        } catch is CooperativeTimeoutError {
            throw OWSHTTPError.networkFailure(.genericFailure)
        }
    }

    func waitForDisconnectIfClosed() async {
        owsFail("Subclasses must provide an implementation.")
    }

    // Access on serialQueue.
    private var onSocketShouldBeClosed = [NSObject: Monitor.Continuation]()

    func waitUntilSocketShouldBeClosed() async throws(CancellationError) {
        return try await Monitor.waitForCondition(shouldBeClosedCondition, in: self, on: serialQueue)
    }

    // MARK: - Socket LifeCycle

    public static var mustAppUseSocketsToMakeRequests: Bool {
        switch CurrentAppContext().type {
        case .main:
            return true
        case .nse:
            return false // because there is a kill switch
        case .share:
            return false // because there is a kill switch
        }
    }

    public static var canAppUseSocketsToMakeRequests: Bool {
        switch CurrentAppContext().type {
        case .main:
            return true
        case .nse:
            return RemoteConfig.current.isNotificationServiceWebSocketEnabled
        case .share:
            return RemoteConfig.current.isShareExtensionWebSocketEnabled
        }
    }

    public var canOpenWebSocket: Bool {
        return serialQueue.sync { self.canOpenWebSocketError == nil }
    }

    public var shouldSocketBeOpen_restOnly: Bool {
        return serialQueue.sync { self.shouldSocketBeOpen() }
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

    func updateCanOpenWebSocket() {
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

        /// Maps token IDs to how many "connected elsewhere" events can occur before
        /// the token ID is implicitly released. (Note: The owner of the token is
        /// still responsible for calling relaseConnection.)
        var activeTokenIds = [Int: Int]()

        func shouldSocketBeOpen() -> Bool {
            return self.activeTokenIds.contains(where: { $0.value > 0 })
        }
    }

    private let connectionTokenState = AtomicValue(ConnectionTokenState(), lock: .init())

    /// If another process opens a connection, should this one reconnect and
    /// reclaim the connection?
    ///
    /// The Notification Service shouldn't be launched while the Main App is
    /// running -- the Main App should always have an open web socket that's
    /// being informed of new messages. Therefore, if the Notification Service
    /// claims the connection, the Main App should take it back. The
    /// Notification Service will allow this to happen and won't try to
    /// reconnect until it receives a new notification.
    public func requestConnection(shouldReconnectIfConnectedElsewhere: Bool) -> ConnectionToken {
        let (connectionToken, shouldConnect) = connectionTokenState.update {
            $0.tokenId += 1
            let shouldConnect = !$0.shouldSocketBeOpen()
            // If we want to reconnect, set the number of retries to "Int.max" (aka
            // "infinity"). If we shouldn't reconnect, set the number of retries to 1.
            $0.activeTokenIds[$0.tokenId] = shouldReconnectIfConnectedElsewhere ? Int.max : 1
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
            let didRelease = $0.activeTokenIds.removeValue(forKey: tokenId) != nil
            return (didRelease, !$0.shouldSocketBeOpen())
        }
        if shouldDisconnect {
            applyDesiredSocketState()
        }
        return didRelease
    }

    fileprivate final func didConnectElsewhere() {
        assertOnQueue(serialQueue)

        // Decrement the number of retries for every token. Don't delete them
        // because the callers are still responsible for releasing them.
        connectionTokenState.update {
            $0.activeTokenIds = $0.activeTokenIds.mapValues { $0 - 1 }
        }

        // If the socket shouldn't be open, notify anybody who's waiting.
        notifySocketShouldBeClosedIfNeeded()
    }

    // This method aligns the socket state with the "desired" socket state.
    //
    // This method is thread-safe.
    fileprivate final func applyDesiredSocketState() {
        serialQueue.async(self._applyDesiredSocketState)
    }

    private func shouldSocketBeOpen() -> Bool {
        assertOnQueue(serialQueue)

        return (
            (canOpenWebSocketError == nil)
            && connectionTokenState.update { $0.shouldSocketBeOpen() }
        )
    }

    fileprivate final func _applyDesiredSocketState() {
        assertOnQueue(serialQueue)

        if shouldSocketBeOpen() {
            owsPrecondition(appReadiness.isAppReady)
            ensureWebsocketExists()
        } else {
            disconnectIfNeeded()
            notifySocketShouldBeClosedIfNeeded()
        }
    }

    private let shouldBeClosedCondition = Monitor.Condition<OWSChatConnection>(
        isSatisfied: { !$0.shouldSocketBeOpen() },
        waiters: \.onSocketShouldBeClosed,
    )

    private func notifySocketShouldBeClosedIfNeeded() {
        assertOnQueue(serialQueue)
        Monitor.notifyOnQueue(serialQueue, state: self, conditions: shouldBeClosedCondition)
    }

    // This method must be thread-safe.
    fileprivate func cycleSocket() {
        serialQueue.async(self._cycleSocket)
    }

    fileprivate func _cycleSocket() {
        assertOnQueue(serialQueue)

        disconnectIfNeeded()
        _applyDesiredSocketState()
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
            Logger.info("Sending… -> \(requestDescription)")

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                self.serialQueue.async {
                    if let canOpenWebSocketError = self.canOpenWebSocketError {
                        continuation.resume(throwing: canOpenWebSocketError)
                    } else {
                        continuation.resume()
                    }
                }
            }

            try await waitForOpen(timeout: 30)

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

    fileprivate func makeRequestInternal(_ request: TSRequest, requestId: UInt64) async throws -> any HTTPResponse {
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

    static let socketReconnectDelay: TimeInterval = 5
}

// MARK: -

internal class OWSChatConnectionUsingLibSignal<Connection: ChatConnection & Sendable>: OWSChatConnection, ConnectionEventsListener {
    fileprivate let libsignalNet: Net

    fileprivate enum ConnectionState {
        case closed(task: Task<Void, Never>?)
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

    private var _connection: ConnectionState = .closed(task: nil)
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

    internal init(libsignalNet: Net, type: OWSChatConnectionType, accountManager: TSAccountManager, appExpiry: AppExpiry, appReadiness: AppReadiness, db: any DB, registrationStateChangeManager: RegistrationStateChangeManager, inactivePrimaryDeviceStore: InactivePrimaryDeviceStore) {
        self.libsignalNet = libsignalNet
        super.init(type: type, accountManager: accountManager, appExpiry: appExpiry, appReadiness: appReadiness, db: db, registrationStateChangeManager: registrationStateChangeManager, inactivePrimaryDeviceStore: inactivePrimaryDeviceStore)
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

        let disconnectTask: Task<Void, Never>?
        switch connection {
        case .open(_):
            return
        case .connecting(_, _):
            // The most recent transition was attempting to connect, and we have not yet observed a failure.
            // That's as good as we're going to get.
            return
        case .closed(let task):
            disconnectTask = task
        }

        // Unique while live.
        let token = NSObject()
        connection = .connecting(token: token, task: Task { [token] () -> Connection? in
            // We need to wait until the prior connection releases the connection lock
            // before we try to acquire it again. This happens as part of this Task.
            await disconnectTask?.value

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
                return await connectionAttemptCompleted(.closed(task: nil))
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
            let result = await connectionAttemptCompleted(.closed(task: nil))
            serialQueue.async {
                self.reconnectAfterFailure()
            }
            return result
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
        // Spin off a background task to disconnect the previous connection.
        connection = .closed(task: Task {
            do {
                try await previousConnection.waitToFinishConnecting(cancel: true)?.disconnect()
            } catch {
                Logger.warn("\(self.logPrefix): error while disconnecting: \(error)")
            }
        })
    }

    override func waitForDisconnectIfClosed() async {
        let connection = await withCheckedContinuation { continuation in
            serialQueue.async { continuation.resume(returning: self.connection) }
        }
        switch connection {
        case .open(_), .connecting(_, _):
            break
        case .closed(let disconnectTask):
            await disconnectTask?.value
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

    fileprivate override func makeRequestInternal(_ request: TSRequest, requestId: UInt64) async throws -> any HTTPResponse {
        var httpHeaders = request.headers
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
                throw OWSHTTPError.invalidRequest
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
            throw OWSHTTPError.invalidRequest
        }

        let libsignalRequest = ChatConnection.Request(method: httpMethod, pathAndQuery: "/\(requestUrl.relativeString)", headers: httpHeaders.headers, body: body, timeout: request.timeoutInterval)

        let connection = await withCheckedContinuation { continuation in
            self.serialQueue.async { continuation.resume(returning: self.connection) }
        }

        // There is a race condition where we cycle the socket between
        // `waitForOpen` returning (see caller) and the code that runs here. If we
        // win the race, the request we send will be almost immediately canceled.
        // If we lose the race, we won't send the request at all. These outcomes
        // are essentially equivalent, and it's not necessary to support this race
        // condition where the socket cycles immediately after it opens.
        let chatService: Connection?
        switch connection {
        case .closed(task: _), .connecting(token: _, task: _):
            chatService = nil
        case .open(let _chatService):
            chatService = _chatService
        }

        let connectionInfo: ConnectionInfo
        let response: ChatConnection.Response
        do {
            guard let chatService else {
                throw SignalError.chatServiceInactive("no connection to chat server")
            }

            connectionInfo = chatService.info()
            response = try await chatService.send(libsignalRequest)
        } catch {
            switch error {
            case SignalError.connectionTimeoutError(_), SignalError.requestTimeoutError(_):
                // cycleSocket(), but only if the chatService we just used is the one that's still connected.
                self.serialQueue.async { [weak chatService] in
                    if let chatService, self.connection.isActive(chatService) {
                        self.disconnectIfNeeded()
                    }
                }
                applyDesiredSocketState()
                throw OWSHTTPError.networkFailure(.genericTimeout)
            case SignalError.webSocketError(_), SignalError.connectionFailed(_):
                throw OWSHTTPError.networkFailure(.genericFailure)
            case SignalError.connectionInvalidated(_):
                throw OWSHTTPError.networkFailure(.wrappedFailure(error))
            case is CancellationError:
                throw error
            default:
                owsFailDebug("[\(requestId)] failed with an unexpected error: \(error)")
                throw OWSHTTPError.networkFailure(.genericFailure)
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

            if case SignalError.connectedElsewhere(_)? = error {
                Logger.info("We were disconnected because another process connected.")
                didConnectElsewhere()
            } else if let error {
                Logger.warn("\(logPrefix) disconnected: \(error)")
            } else {
                owsFailDebug("\(logPrefix) libsignal disconnected us without being asked")
            }

            connection = .closed(task: nil)
            OutageDetection.shared.reportConnectionFailure()
            self.reconnectAfterFailure()
        }
    }

    private var mostRecentFailureDate: MonotonicDate?
    private var consecutiveFailureCount = 0

    private func reconnectAfterFailure() {
        assertOnQueue(serialQueue)

        let now = MonotonicDate()

        // If it's been "a while" since the most recent failure, reset the counter.
        // If "a while" is shorter than the maximum exponential backoff, the
        // counter may be inadvertently reset while trying to back off.
        if let mostRecentFailureDate, (now - mostRecentFailureDate).seconds > (2 * Self.socketReconnectDelay) {
            Logger.info("Resetting connection backoff state due to elapsed time.")
            self.consecutiveFailureCount = 0
        }
        self.mostRecentFailureDate = now

        let reconnectDelay: TimeInterval
        if self.consecutiveFailureCount == 0 {
            // Reconnect immediately after the first failure.
            reconnectDelay = 0
        } else {
            reconnectDelay = OWSOperation.retryIntervalForExponentialBackoff(
                failureCount: self.consecutiveFailureCount,
                maxAverageBackoff: Self.socketReconnectDelay,
            )
        }
        self.consecutiveFailureCount += 1

        let formattedReconnectDelay = String(format: "%.1f", reconnectDelay)
        Logger.warn("Scheduling reconnect after \(formattedReconnectDelay)s")

        // Wait a few seconds before retrying to reduce server load.
        self.serialQueue.asyncAfter(deadline: .now() + reconnectDelay) { [weak self] in
            self?._applyDesiredSocketState()
        }
    }
}

internal class OWSUnauthConnectionUsingLibSignal: OWSChatConnectionUsingLibSignal<UnauthenticatedChatConnection> {
    init(libsignalNet: Net, accountManager: TSAccountManager, appExpiry: AppExpiry, appReadiness: AppReadiness, db: any DB, registrationStateChangeManager: RegistrationStateChangeManager, inactivePrimaryDeviceStore: InactivePrimaryDeviceStore) {
        super.init(libsignalNet: libsignalNet, type: .unidentified, accountManager: accountManager, appExpiry: appExpiry, appReadiness: appReadiness, db: db, registrationStateChangeManager: registrationStateChangeManager, inactivePrimaryDeviceStore: inactivePrimaryDeviceStore)
    }

    fileprivate override var connection: ConnectionState {
        didSet {
            if case .open(let service) = connection {
                service.start(listener: self)
            }
        }
    }

    override func connectChatService() async throws -> UnauthenticatedChatConnection {
        return try await libsignalNet.connectUnauthenticatedChat(languages: Array(HttpHeaders.topPreferredLanguages()))
    }
}

internal class OWSAuthConnectionUsingLibSignal: OWSChatConnectionUsingLibSignal<AuthenticatedChatConnection>, ChatConnectionListener {
    private var _hasEmptiedInitialQueue = false
    override var hasEmptiedInitialQueue: Bool {
        get async {
            return await withCheckedContinuation { continuation in
                serialQueue.async {
                    continuation.resume(returning: self._hasEmptiedInitialQueue)
                }
            }
        }
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

    init(
        libsignalNet: Net,
        accountManager: TSAccountManager,
        appContext: any AppContext,
        appExpiry: AppExpiry,
        appReadiness: AppReadiness,
        db: any DB,
        registrationStateChangeManager: RegistrationStateChangeManager,
        inactivePrimaryDeviceStore: InactivePrimaryDeviceStore,
    ) {
        let priority: Int
        switch appContext.type {
        case .share: priority = 1
        case .main: priority = 2
        case .nse: priority = 3
        }
        let priorityCount = 3
        self.connectionLock = ConnectionLock(filePath: appContext.appSharedDataDirectoryPath().appendingPathComponent("chat-connection.lock"), priority: priority, of: priorityCount)
        super.init(libsignalNet: libsignalNet, type: .identified, accountManager: accountManager, appExpiry: appExpiry, appReadiness: appReadiness, db: db, registrationStateChangeManager: registrationStateChangeManager, inactivePrimaryDeviceStore: inactivePrimaryDeviceStore)
    }

    deinit {
        self.connectionLock.close()
    }

    fileprivate override func connectChatService() async throws -> AuthenticatedChatConnection {
        try await self.acquireConnectionLock()
        let (username, password) = db.read { tx in
            (accountManager.storedServerUsername(tx: tx), accountManager.storedServerAuthToken(tx: tx))
        }
        // Note that we still try to connect for an unregistered user, so that we get a consistent error thrown.
        return try await libsignalNet.connectAuthenticatedChat(username: username ?? "", password: password ?? "", receiveStories: StoryManager.areStoriesEnabled, languages: Array(HttpHeaders.topPreferredLanguages()))
    }

    fileprivate override var connection: ConnectionState {
        get {
            return super.connection
        }
        set {
            assertOnQueue(serialQueue)
            let updatedValue: ConnectionState
            if case .closed(let task) = newValue {
                updatedValue = .closed(task: Task {
                    await task?.value
                    self.releaseConnectionLock()
                })
            } else {
                updatedValue = newValue
            }
            super.connection = updatedValue
            switch updatedValue {
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
            case .closed(task: _):
                keepaliveSenderTask = nil
                _hasEmptiedInitialQueue = false
            }
        }
    }

    private let connectionLock: ConnectionLock
    private let heldConnectionLock = AtomicValue<ConnectionLock.HeldLock?>(nil, lock: .init())

    private func acquireConnectionLock() async throws {
        guard RemoteConfig.current.isConnectionLockEnabled else {
            return
        }
        owsPrecondition(self.heldConnectionLock.get() == nil)
        let newValue = try await self.connectionLock.lock(onInterrupt: (self.serialQueue, {
            Logger.warn("Cycling the socket because the connection lock was interrupted")
            self._cycleSocket()
        }))
        let oldValue = self.heldConnectionLock.swap(newValue)
        owsPrecondition(oldValue == nil)
    }

    private func releaseConnectionLock() {
        let oldValue = self.heldConnectionLock.swap(nil)
        // We might be canceled while trying to acquire the lock, and we won't have
        // a lock that needs to be released in that case.
        if let oldValue {
            self.connectionLock.unlock(oldValue)
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
                    // This 30-second timeout doesn't inherently need to match the send interval above,
                    // but neither do we need an especially tight timeout here either.
                    let request = ChatConnection.Request(method: "GET", pathAndQuery: "/v1/keepalive", timeout: 30)
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

    private func handleInactivePrimaryDeviceAlert(newInactivePrimaryDevice: Bool) {
        let storedInactivePrimaryDevice = db.read { tx in
            return inactivePrimaryDeviceStore.valueForInactivePrimaryDeviceAlert(transaction: tx)
        }

        guard storedInactivePrimaryDevice != newInactivePrimaryDevice else {
            return
        }

        Logger.info("Received new value for inactive primary device alert: \(newInactivePrimaryDevice)")

        db.write { transaction in
            inactivePrimaryDeviceStore.setValueForInactivePrimaryDeviceAlert(value: newInactivePrimaryDevice, transaction: transaction)
        }

        // Megaphones might load before we setup the OWSChatConnection
        // so we should notify the UI that the value has changed.
        NotificationCenter.default.postOnMainThread(name: .inactivePrimaryDeviceChanged, object: nil)
    }

    func chatConnection(_ chat: AuthenticatedChatConnection, didReceiveAlerts alerts: [String]) {
        self.serialQueue.async { [self] in
            guard self.connection.isActive(chat) else {
                // We have since disconnected from the chat service instance that reported the alerts.
                return
            }
            var alertSet = Set(alerts)

            handleInactivePrimaryDeviceAlert(newInactivePrimaryDevice: alertSet.contains(AlertType.idlePrimaryDevice.rawValue))

            alertSet.remove(AlertType.idlePrimaryDevice.rawValue)
            if !alertSet.isEmpty {
                Logger.warn("ignoring \(alertSet.count) alerts from the server")
            }
        }
    }

    func chatConnection(_ chat: AuthenticatedChatConnection, didReceiveIncomingMessage envelope: Data, serverDeliveryTimestamp: UInt64, sendAck: @escaping () throws -> Void) {
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
                let alreadyEmptied = self._hasEmptiedInitialQueue
                self._hasEmptiedInitialQueue = true

                if !alreadyEmptied {
                    // This notification is used to wake up anything waiting for hasEmptiedInitialQueue.
                    self.notifyStatusChange(newState: self.currentState)
                }
            }
        }
    }
}
