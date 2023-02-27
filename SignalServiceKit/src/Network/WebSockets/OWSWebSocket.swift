//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc
public enum OWSWebSocketType: Int, CaseIterable, CustomDebugStringConvertible {
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

@objc
public enum OWSWebSocketState: Int, CustomDebugStringConvertible {
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

@objc
public class OWSWebSocket: NSObject {
    // Track where Dependencies are used throughout this class.
    private struct GlobalDependencies: Dependencies {}

    @objc
    public static let webSocketStateDidChange = Notification.Name("webSocketStateDidChange")

    public static let serialQueue = DispatchQueue(label: "org.signal.websocket")
    fileprivate var serialQueue: DispatchQueue { Self.serialQueue }

    // TODO: Should we use a higher-priority queue?
    fileprivate static let messageProcessingQueue = DispatchQueue(label: "org.signal.websocket.message-processing")
    fileprivate var messageProcessingQueue: DispatchQueue { Self.messageProcessingQueue }

    @objc
    public static var verboseLogging: Bool { false && DebugFlags.internalLogging }
    fileprivate var verboseLogging: Bool { Self.verboseLogging }

    // MARK: -

    private let webSocketType: OWSWebSocketType

    private static let socketReconnectDelaySeconds: TimeInterval = 5

    private var _currentWebSocket = AtomicOptional<WebSocketConnection>(nil)
    private var currentWebSocket: WebSocketConnection? {
        get {
            _currentWebSocket.get()
        }
        set {
            let oldValue = _currentWebSocket.swap(newValue)
            if oldValue != nil || newValue != nil {
                owsAssertDebug(oldValue?.id != newValue?.id)
            }

            if verboseLogging,
               oldValue != nil || newValue != nil,
               oldValue?.id != newValue?.id {
                Logger.info("\(webSocketType) \(String(describing: oldValue?.id)) -> \(String(describing: newValue?.id))")
            }

            oldValue?.reset()

            notifyStatusChange()
        }
    }

    // MARK: -

    public var currentState: OWSWebSocketState {
        guard let currentWebSocket = self.currentWebSocket else {
            return .closed
        }
        switch currentWebSocket.state {
        case .open:
            return .open
        case .connecting:
            return .connecting
        case .disconnected:
            return .closed
        }
    }

    // This var is thread-safe.
    public var canMakeRequests: Bool {
        currentState == .open
    }

    // This var is thread-safe.
    public var hasEmptiedInitialQueue: Bool {
        guard let currentWebSocket = self.currentWebSocket else {
            return false
        }
        return currentWebSocket.hasEmptiedInitialQueue.get()
    }

    // We cache this value instead of consulting [UIApplication sharedApplication].applicationState,
    // because UIKit only provides a "will resign active" notification, not a "did resign active"
    // notification.
    private let appIsActive = AtomicBool(false)

    private let lastNewWebsocketDate = AtomicOptional<Date>(nil)
    private let lastDrainQueueDate = AtomicOptional<Date>(nil)
    private let lastReceivedPushWithoutWebsocketDate = AtomicOptional<Date>(nil)

    private static let unsubmittedRequestTokenCounter = AtomicUInt()
    public typealias UnsubmittedRequestToken = UInt
    // This method is thread-safe.
    public func makeUnsubmittedRequestToken() -> UnsubmittedRequestToken {
        let token = Self.unsubmittedRequestTokenCounter.increment()
        unsubmittedRequestTokens.insert(token)
        applyDesiredSocketState()
        return token
    }
    private let unsubmittedRequestTokens = AtomicSet<UnsubmittedRequestToken>()
    // This method is thread-safe.
    fileprivate func removeUnsubmittedRequestToken(_ token: UnsubmittedRequestToken) {
        owsAssertDebug(unsubmittedRequestTokens.contains(token))
        unsubmittedRequestTokens.remove(token)
        applyDesiredSocketState()
    }

    // MARK: - BackgroundKeepAlive

    private enum BackgroundKeepAliveRequestType {
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
            // There are many other cases as well not associated with a fixed duration,
            // such as if currentWebSocket.hasPendingRequests; see shouldSocketBeOpen().
        }
    }

    private struct BackgroundKeepAlive {
        let requestType: BackgroundKeepAliveRequestType
        let untilDate: Date
    }

    // This var should only be accessed with unfairLock acquired.
    private var _backgroundKeepAlive: BackgroundKeepAlive?
    private let unfairLock = UnfairLock()

    // This method is thread-safe.
    private func ensureBackgroundKeepAlive(_ requestType: BackgroundKeepAliveRequestType) {
        let keepAliveDuration = requestType.keepAliveDuration
        owsAssertDebug(keepAliveDuration > 0)
        let untilDate = Date().addingTimeInterval(keepAliveDuration)

        let didChange: Bool = unfairLock.withLock {
            if let oldValue = self._backgroundKeepAlive,
               oldValue.untilDate >= untilDate {
                return false
            }
            self._backgroundKeepAlive = BackgroundKeepAlive(requestType: requestType, untilDate: untilDate)
            return true
        }

        if didChange {
            var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "applicationWillResignActive")
            applyDesiredSocketState {
                assertOnQueue(Self.serialQueue)
                owsAssertDebug(backgroundTask != nil)
                backgroundTask = nil
            }
        }
    }

    // This var is thread-safe.
    private var hasBackgroundKeepAlive: Bool {
        unfairLock.withLock {
            guard let backgroundKeepAlive = self._backgroundKeepAlive else {
                return false
            }
            guard backgroundKeepAlive.untilDate >= Date() else {
                // Cull expired values.
                self._backgroundKeepAlive = nil
                return false
            }
            if Self.verboseLogging {
                Logger.info("\(self.logPrefix) requestType: \(backgroundKeepAlive.requestType)")
            }
            return true
        }
    }

    private var logPrefix: String {
        if let currentWebSocket = currentWebSocket {
            return currentWebSocket.logPrefix
        } else {
            return "[\(webSocketType)]"
        }
    }

    // MARK: -

    public required init(webSocketType: OWSWebSocketType) {
        AssertIsOnMainThread()

        self.webSocketType = webSocketType

        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReadySync { [weak self] in
            guard let self = self else { return }
            self.observeNotificationsIfNecessary()
            self.applyDesiredSocketState()
        }
    }

    // MARK: - Notifications

    private let hasObservedNotifications = AtomicBool(false)

    // We want to observe these notifications lazily to avoid accessing
    // the data store in [application: didFinishLaunchingWithOptions:].
    private func observeNotificationsIfNecessary() {
        AssertIsOnMainThread()

        guard hasObservedNotifications.tryToSetFlag() else {
            return
        }

        appIsActive.set(CurrentAppContext().isMainAppAndActive)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidBecomeActive),
                                               name: .OWSApplicationDidBecomeActive,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillResignActive),
                                               name: .OWSApplicationWillResignActive,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(registrationStateDidChange),
                                               name: .registrationStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(localNumberDidChange),
                                               name: .localNumberDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(isCensorshipCircumventionActiveDidChange),
                                               name: .isCensorshipCircumventionActiveDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(isSignalProxyReadyDidChange),
                                               name: .isSignalProxyReadyDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(deviceListUpdateModifiedDeviceList),
                                               name: OWSDevicesService.deviceListUpdateModifiedDeviceList,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appExpiryDidChange),
                                               name: AppExpiry.AppExpiryDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(storiesEnabledStateDidChange), name: .storiesEnabledStateDidChange, object: nil)
    }

    // MARK: -

    private let lastState = AtomicValue<OWSWebSocketState>(.closed)

    private func notifyStatusChange() {
        let newState = self.currentState
        let oldState = lastState.swap(newState)
        if oldState != newState {
            Logger.info("\(logPrefix): \(oldState) -> \(newState)")
        }

        NotificationCenter.default.postNotificationNameAsync(Self.webSocketStateDidChange, object: nil)
    }

    // MARK: - Message Sending

    public typealias RequestSuccess = (HTTPResponse) -> Void
    public typealias RequestFailure = (OWSHTTPErrorWrapper) -> Void
    fileprivate typealias RequestSuccessInternal = (HTTPResponse, SocketRequestInfo) -> Void

    fileprivate func makeRequestInternal(_ request: TSRequest,
                                         unsubmittedRequestToken: UnsubmittedRequestToken,
                                         success: @escaping RequestSuccessInternal,
                                         failure: @escaping RequestFailure) {
        Self.makeRequestInternal(request,
                                 unsubmittedRequestToken: unsubmittedRequestToken,
                                 webSocket: self,
                                 success: success,
                                 failure: failure)
    }

    fileprivate static func makeRequestInternal(_ request: TSRequest,
                                                unsubmittedRequestToken: UnsubmittedRequestToken,
                                                webSocket: OWSWebSocket,
                                                success: @escaping RequestSuccessInternal,
                                                failure: @escaping RequestFailure) {
        assertOnQueue(OWSWebSocket.serialQueue)

        defer {
            webSocket.removeUnsubmittedRequestToken(unsubmittedRequestToken)
        }

        let webSocketType = webSocket.webSocketType
        var label = Self.label(forRequest: request,
                               webSocketType: webSocketType,
                               requestInfo: nil)
        guard let requestUrl = request.url else {
            owsFailDebug("\(label) Missing requestUrl.")
            DispatchQueue.global().async {
                failure(OWSHTTPErrorWrapper(error: .invalidRequest(requestUrl: request.url!)))
            }
            return
        }
        guard let httpMethod = request.httpMethod.nilIfEmpty else {
            owsFailDebug("\(label) Missing httpMethod.")
            DispatchQueue.global().async {
                failure(OWSHTTPErrorWrapper(error: .invalidRequest(requestUrl: requestUrl)))
            }
            return
        }
        guard let currentWebSocket = webSocket.currentWebSocket,
              currentWebSocket.state == .open else {
            owsFailDebug("\(label) Missing currentWebSocket.")
            DispatchQueue.global().async {
                failure(OWSHTTPErrorWrapper(error: .networkFailure(requestUrl: requestUrl)))
            }
            return
        }

        let requestInfo = SocketRequestInfo(request: request,
                                            requestUrl: requestUrl,
                                            webSocketType: webSocket.webSocketType,
                                            success: success,
                                            failure: failure)
        label = Self.label(forRequest: request,
                           webSocketType: webSocketType,
                           requestInfo: requestInfo)

        owsAssertDebug(!requestUrl.path.hasPrefix("/"))
        var requestPath = "/".appending(requestUrl.path)
        if let query = requestUrl.query?.nilIfEmpty {
            requestPath += "?" + query
        }
        if let fragment = requestUrl.fragment?.nilIfEmpty {
            requestPath += "#" + fragment
        }
        let requestBuilder = WebSocketProtoWebSocketRequestMessage.builder(verb: httpMethod,
                                                                           path: requestPath,
                                                                           requestID: requestInfo.requestId)

        let httpHeaders = OWSHttpHeaders()
        httpHeaders.addHeaderMap(request.allHTTPHeaderFields, overwriteOnConflict: false)

        if let existingBody = request.httpBody {
            requestBuilder.setBody(existingBody)
        } else {
            // TODO: Do we need body & headers for requests with no parameters?
            let jsonData: Data?
            do {
                jsonData = try JSONSerialization.data(withJSONObject: request.parameters, options: [])
            } catch {
                owsFailDebug("\(label) Error: \(error).")
                requestInfo.didFailInvalidRequest()
                return
            }

            if let jsonData = jsonData {
                requestBuilder.setBody(jsonData)
                // If we're going to use the json serialized parameters as our body, we should overwrite
                // the Content-Type on the request.
                httpHeaders.addHeader("Content-Type",
                                      value: "application/json",
                                      overwriteOnConflict: true)
            }
        }

        // Set User-Agent and Accept-Language headers.
        httpHeaders.addDefaultHeaders()

        for (key, value) in httpHeaders.headers {
            let header = String(format: "%@:%@", key, value)
            requestBuilder.addHeaders(header)
        }

        do {
            let requestProto = try requestBuilder.build()

            let messageBuilder = WebSocketProtoWebSocketMessage.builder()
            messageBuilder.setType(.request)
            messageBuilder.setRequest(requestProto)
            let messageData = try messageBuilder.buildSerializedData()

            guard currentWebSocket.state == .open else {
                owsFailDebug("\(label) Socket not open.")
                requestInfo.didFailInvalidRequest()
                return
            }

            Logger.info("\(label) Making request")

            currentWebSocket.sendRequest(requestInfo: requestInfo,
                                         messageData: messageData,
                                         delegate: webSocket)
        } catch {
            owsFailDebug("\(label), Error: \(error).")
            requestInfo.didFailInvalidRequest()
            return
        }
    }

    private func processWebSocketResponseMessage(_ message: WebSocketProtoWebSocketResponseMessage,
                                                 currentWebSocket: WebSocketConnection) {
        assertOnQueue(serialQueue)

        let requestId = message.requestID
        let responseStatus = message.status
        let responseData: Data? = message.hasBody ? message.body : nil

        if DebugFlags.internalLogging,
           message.hasMessage,
           let responseMessage = message.message {
            Logger.info("received WebSocket response \(currentWebSocket.logPrefix), requestId: \(message.requestID), status: \(message.status), message: \(responseMessage)")
        } else {
            Logger.info("received WebSocket response \(currentWebSocket.logPrefix), requestId: \(message.requestID), status: \(message.status)")
        }

        ensureBackgroundKeepAlive(.receiveResponse)

        // The websocket is only used to connect to the main signal
        // service, so we need to check for remote deprecation.
        if responseStatus == AppExpiry.appExpiredStatusCode {
            appExpiry.setHasAppExpiredAtCurrentVersion()
        }

        let headers = OWSHttpHeaders()
        headers.addHeaderList(message.headers, overwriteOnConflict: true)

        guard let requestInfo = currentWebSocket.popRequestInfo(forRequestId: requestId) else {
            Logger.warn("Received response to unknown request \(currentWebSocket.logPrefix)")
            return
        }
        let hasSuccessStatus = 200 <= responseStatus && responseStatus <= 299
        if hasSuccessStatus {
            requestInfo.didSucceed(status: Int(responseStatus),
                                   headers: headers,
                                   bodyData: responseData)
        } else {
            requestInfo.didFail(responseStatus: Int(responseStatus),
                                responseHeaders: headers,
                                responseError: nil,
                                responseData: responseData)
        }

        // We may have been holding the websocket open, waiting for this response.
        // Check if we should close the websocket.
        applyDesiredSocketState()
    }

    // MARK: -

    fileprivate func processWebSocketRequestMessage(_ message: WebSocketProtoWebSocketRequestMessage,
                                                    currentWebSocket: WebSocketConnection) {
        assertOnQueue(Self.serialQueue)

        let httpMethod = message.verb.nilIfEmpty ?? ""
        let httpPath = message.path.nilIfEmpty ?? ""
        owsAssertDebug(!httpMethod.isEmpty)
        owsAssertDebug(!httpPath.isEmpty)

        Logger.info("Got message \(currentWebSocket.logPrefix): verb: \(httpMethod), path: \(httpPath)")

        if httpMethod == "PUT",
           httpPath == "/api/v1/message" {

            // If we receive a message over the socket while the app is in the background,
            // prolong how long the socket stays open.
            //
            // TODO: NSE
            ensureBackgroundKeepAlive(.receiveMessage)

            handleIncomingMessage(message, currentWebSocket: currentWebSocket)
        } else if httpPath == "/api/v1/queue/empty" {
            // Queue is drained.
            handleEmptyQueueMessage(message, currentWebSocket: currentWebSocket)
        } else {
            Logger.warn("Unsupported WebSocket Request \(currentWebSocket.logPrefix)")

            sendWebSocketMessageAcknowledgement(message, currentWebSocket: currentWebSocket)
        }
    }

    private func handleIncomingMessage(_ message: WebSocketProtoWebSocketRequestMessage,
                                       currentWebSocket: WebSocketConnection) {
        assertOnQueue(Self.serialQueue)

        var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "handleIncomingMessage")

        if Self.verboseLogging {
            Logger.info("\(currentWebSocket.logPrefix) 1")
        }

        let ackMessage = { (processingError: Error?, serverTimestamp: UInt64) in
            if Self.verboseLogging {
                Logger.info("\(currentWebSocket.logPrefix) 2 \(processingError?.localizedDescription ?? "success!")")
            }

            let ackBehavior = MessageProcessor.handleMessageProcessingOutcome(error: processingError)
            switch ackBehavior {
            case .shouldAck:
                self.sendWebSocketMessageAcknowledgement(message, currentWebSocket: currentWebSocket)
            case .shouldNotAck(let error):
                Logger.info("Skipping ack of message with serverTimestamp \(serverTimestamp) because of error: \(error)")
            }

            owsAssertDebug(backgroundTask != nil)
            backgroundTask = nil
        }

        let headers = OWSHttpHeaders()
        headers.addHeaderList(message.headers, overwriteOnConflict: true)

        var serverDeliveryTimestamp: UInt64 = 0
        if let timestampString = headers.value(forHeader: "X-Signal-Timestamp") {
            if let timestamp = UInt64(timestampString) {
                serverDeliveryTimestamp = timestamp
            } else {
                owsFailDebug("Invalidly formatted timestamp: \(timestampString)")
            }
        }

        if serverDeliveryTimestamp == 0 {
            owsFailDebug("Missing server delivery timestamp")
        }

        guard let encryptedEnvelope = message.body else {
            ackMessage(OWSGenericError("Missing encrypted envelope on message \(currentWebSocket.logPrefix)"), serverDeliveryTimestamp)
            return
        }
        let envelopeSource: EnvelopeSource = {
            switch self.webSocketType {
            case .identified:
                return .websocketIdentified
            case .unidentified:
                return .websocketUnidentified
            }
        }()

        Self.messageProcessingQueue.async {
            if Self.verboseLogging {
                Logger.info("\(currentWebSocket.logPrefix) 2")
            }
            Self.messageProcessor.processEncryptedEnvelopeData(encryptedEnvelope,
                                                               serverDeliveryTimestamp: serverDeliveryTimestamp,
                                                               envelopeSource: envelopeSource) { error in
                if Self.verboseLogging {
                    Logger.info("\(currentWebSocket.logPrefix) 3")
                }
                Self.serialQueue.async {
                    ackMessage(error, serverDeliveryTimestamp)
                }
            }
        }
    }

    private func handleEmptyQueueMessage(_ message: WebSocketProtoWebSocketRequestMessage,
                                         currentWebSocket: WebSocketConnection) {
        assertOnQueue(Self.serialQueue)

        // Queue is drained.

        sendWebSocketMessageAcknowledgement(message, currentWebSocket: currentWebSocket)

        self.lastDrainQueueDate.set(Date())

        if Self.verboseLogging {
            Logger.info("\(currentWebSocket.logPrefix) 1")
        }

        guard !currentWebSocket.hasEmptiedInitialQueue.get() else {
            owsFailDebug("Unexpected emptyQueueMessage \(currentWebSocket.logPrefix)")
            return
        }
        if Self.verboseLogging {
            Logger.info("\(currentWebSocket.logPrefix) 1")
        }
        // We need to flush the message processing and serial queues
        // to ensure that all received messages are enqueued and
        // processed before we: a) mark the queue as empty. b) notify.
        //
        // The socket might close and re-open while we're
        // flushing the queues. Therefore we capture currentWebSocket
        // flushing to ensure that we handle this case correctly.
        Self.messageProcessingQueue.async { [weak self] in
            if Self.verboseLogging {
                Logger.info("\(currentWebSocket.logPrefix) 2")
            }
            Self.serialQueue.async {
                guard let self = self else { return }
                if Self.verboseLogging {
                    Logger.info("\(currentWebSocket.logPrefix) 3")
                }
                if currentWebSocket.hasEmptiedInitialQueue.tryToSetFlag() {
                    self.notifyStatusChange()
                }
                if Self.verboseLogging {
                    Logger.info("\(currentWebSocket.logPrefix) 4")
                }

                // We may have been holding the websocket open, waiting to drain the
                // queue. Check if we should close the websocket.
                self.applyDesiredSocketState()
            }
        }
    }

    private func sendWebSocketMessageAcknowledgement(_ request: WebSocketProtoWebSocketRequestMessage,
                                                     currentWebSocket: WebSocketConnection) {
        assertOnQueue(Self.serialQueue)

        do {
            try currentWebSocket.sendResponse(for: request,
                                              status: 200,
                                              message: "OK")
        } catch {
            owsFailDebugUnlessNetworkFailure(error)
        }
    }

    // This method is thread-safe.
    public func cycleSocket() {
        if verboseLogging {
            Logger.info("\(webSocketType)")
        }

        self.currentWebSocket = nil

        applyDesiredSocketState()
    }

    // This method is thread-safe.
    private var webSocketAuthenticationQueryItems: [URLQueryItem]? {
        switch webSocketType {
        case .unidentified:
            // UD socket is unauthenticated.
            return nil
        case .identified:
            let login = tsAccountManager.storedServerUsername ?? ""
            let password = tsAccountManager.storedServerAuthToken() ?? ""
            owsAssertDebug(login.nilIfEmpty != nil)
            owsAssertDebug(password.nilIfEmpty != nil)
            return [
                URLQueryItem(name: "login", value: login),
                URLQueryItem(name: "password", value: password)
            ]
        }
    }

    // MARK: - Socket LifeCycle

    public static var canAppUseSocketsToMakeRequests: Bool {
        if FeatureFlags.deprecateREST {
            // When we deprecate REST, we will use web sockets in app extensions.
            return true
        }
        if !CurrentAppContext().isMainApp {
            return false
        }
        return true
    }

    // This var is thread-safe.
    public var shouldSocketBeOpen: Bool {
        desiredSocketState.shouldSocketBeOpen
    }

    private enum DesiredSocketState: Equatable {
        case closed(reason: String)
        case open(reason: String)

        public var shouldSocketBeOpen: Bool {
            switch self {
            case .closed:
                return false
            case .open:
                return true
            }
        }
    }

    // This method is thread-safe.
    private var desiredSocketState: DesiredSocketState {

        #if TESTABLE_BUILD
        if CurrentAppContext().isRunningTests {
            Logger.warn("\(logPrefix) Suppressing socket in tests.")
            return .closed(reason: "Running tests")
        }
        #endif

        guard AppReadiness.isAppReady else {
            return .closed(reason: "!isAppReady")
        }

        guard tsAccountManager.isRegisteredAndReady else {
            return .closed(reason: "!isRegisteredAndReady")
        }

        guard !appExpiry.isExpired else {
            return .closed(reason: "appExpiry.isExpired")
        }

        guard Self.canAppUseSocketsToMakeRequests else {
            return .closed(reason: "!canAppUseSocketsToMakeRequests")
        }

        // Starscream doesn't support the proxy
        if SignalProxy.isEnabled, #unavailable(iOS 13) {
            return .closed(reason: "signalProxyIsEnabled")
        }

        if let currentWebSocket = self.currentWebSocket,
           currentWebSocket.hasPendingRequests {
            return .open(reason: "hasPendingRequests")
        }

        if !unsubmittedRequestTokens.isEmpty {
            return .open(reason: "unsubmittedRequestTokens")
        }

        guard GlobalDependencies.webSocketFactory.canBuildWebSocket else {
            owsFailDebug("\(logPrefix) Could not build webSocket.")
            return .closed(reason: "couldNotBuildWebSocket")
        }

        let shouldDrainQueue: Bool = {
            guard Self.holdWebsocketOpenUntilDrained else {
                return false
            }
            guard CurrentAppContext().isMainApp ||
                    CurrentAppContext().isNSE else {
                return false
            }
            guard webSocketType == .identified,
                  tsAccountManager.isRegisteredAndReady else {
                return false
            }
            guard let lastDrainQueueDate = self.lastDrainQueueDate.get() else {
                if verboseLogging {
                    Logger.info("\(logPrefix) Has not drained identified queue at least once. true")
                }
                return true
            }
            guard let lastNewWebsocketDate = self.lastNewWebsocketDate.get() else {
                owsFailDebug("Missing lastNewWebsocketDate.")
                if verboseLogging {
                    Logger.info("\(logPrefix) Has never tried to open an identified websocket. true")
                }
                return true
            }
            if lastNewWebsocketDate > lastDrainQueueDate {
                if verboseLogging {
                    Logger.info("\(logPrefix) Hasn't drained most recent identified websocket. true")
                }
                return true
            }
            guard let lastReceivedPushWithoutWebsocketDate = self.lastReceivedPushWithoutWebsocketDate.get(),
                  lastReceivedPushWithoutWebsocketDate > lastDrainQueueDate else {
                return false
            }
            if verboseLogging {
                Logger.info("\(logPrefix) Has not drained queue since last received push. true")
            }
            return true
        }()
        if shouldDrainQueue {
            return .open(reason: "shouldDrainQueue")
        }

        if appIsActive.get() {
            // While app is active, keep web socket alive.
            return .open(reason: "appIsActive")
        } else if DebugFlags.keepWebSocketOpenInBackground {
            return .open(reason: "keepWebSocketOpenInBackground")
        } else if hasBackgroundKeepAlive {
            // If app is doing any work in the background, keep web socket alive.
            return .open(reason: "hasBackgroundKeepAlive")
        } else {
            return .closed(reason: "default false")
        }
    }

    private static let holdWebsocketOpenUntilDrained = false

    // This method is thread-safe.
    public func didReceivePush() {
        owsAssertDebug(AppReadiness.isAppReady)

        self.ensureBackgroundKeepAlive(.didReceivePush)

        // If we receive a push without an identified websocket,
        // hold the websocket open in the background until the
        // websocket drains it queue.
        if AppReadiness.isAppReady,
           tsAccountManager.isRegisteredAndReady,
           webSocketType == .identified,
           nil == currentWebSocket {
            lastReceivedPushWithoutWebsocketDate.set(Date())
            applyDesiredSocketState()
        }
    }

    private let lastDesiredSocketState = AtomicValue<DesiredSocketState>(.closed(reason: "App launched"))

    // This method aligns the socket state with the "desired" socket state.
    //
    // This method is thread-safe.
    private func applyDesiredSocketState(completion: (() -> Void)? = nil) {

        guard AppReadiness.isAppReady else {
            AppReadiness.runNowOrWhenAppDidBecomeReadySync { [weak self] in
                self?.applyDesiredSocketState(completion: completion)
            }
            return
        }

        serialQueue.async { [weak self] in
            guard let self = self else {
                completion?()
                return
            }

            let desiredSocketStateNew = self.desiredSocketState
            let desiredSocketStateOld = self.lastDesiredSocketState.swap(desiredSocketStateNew)
            if desiredSocketStateNew != desiredSocketStateOld {
                if Self.verboseLogging {
                    Logger.info("\(self.logPrefix), desiredSocketState: \(desiredSocketStateOld) -> \(desiredSocketStateNew), appIsActive: \(self.appIsActive.get())")
                }
            }
            var shouldHaveBackgroundKeepAlive = false
            if desiredSocketStateNew.shouldSocketBeOpen {
                self.ensureWebsocketExists()

                if self.currentState != .open {
                    // If we want the socket to be open and it's not open,
                    // start up the reconnect timer immediately (don't wait for an error).
                    // There's little harm in it and this will make us more robust to edge
                    // cases.
                    self.ensureReconnectTimer()
                }

                // If we're keeping the webSocket open in the background,
                // ensure that the "BackgroundKeepAlive" state is active.
                shouldHaveBackgroundKeepAlive = !self.appIsActive.get()
            } else {
                self.clearReconnect()
                self.currentWebSocket = nil
            }

            if shouldHaveBackgroundKeepAlive {
                if nil == self.backgroundKeepAliveTimer {
                    // Start a new timer that will fire every second while the socket is open in the background.
                    // This timer will ensure we close the websocket when the time comes.
                    self.backgroundKeepAliveTimer = OffMainThreadTimer(timeInterval: 1, repeats: true) { [weak self] timer in
                        guard let self = self else {
                            timer.invalidate()
                            return
                        }
                        self.applyDesiredSocketState()
                    }
                }
                if nil == self.backgroundKeepAliveBackgroundTask {
                    self.backgroundKeepAliveBackgroundTask = OWSBackgroundTask(label: "BackgroundKeepAlive") { [weak self] (_) in
                        AssertIsOnMainThread()
                        self?.applyDesiredSocketState()
                    }
                }
            } else {
                self.backgroundKeepAliveTimer?.invalidate()
                self.backgroundKeepAliveTimer = nil
                self.backgroundKeepAliveBackgroundTask = nil
            }

            completion?()
        }
    }

    // This timer is used to check periodically whether we should
    // close the socket.
    private var backgroundKeepAliveTimer: OffMainThreadTimer?
    // This is used to manage the iOS "background task" used to
    // keep the app alive in the background.
    private var backgroundKeepAliveBackgroundTask: OWSBackgroundTask?

    private func ensureWebsocketExists() {
        assertOnQueue(serialQueue)

        // Try to reuse the existing socket (if any) if it is in a valid state.
        if let currentWebSocket = self.currentWebSocket {
            switch currentWebSocket.state {
            case .open:
                self.clearReconnect()
                return
            case .connecting:
                return
            case .disconnected:
                break
            }
        }

        Logger.info("Creating new websocket: \(webSocketType)")

        let signalServiceType: SignalServiceType
        switch webSocketType {
        case .identified:
            signalServiceType = .mainSignalServiceIdentified
        case .unidentified:
            signalServiceType = .mainSignalServiceUnidentified
        }

        let request = WebSocketRequest(
            signalService: signalServiceType,
            urlPath: "v1/websocket/",
            urlQueryItems: webSocketAuthenticationQueryItems,
            extraHeaders: StoryManager.buildStoryHeaders()
        )

        self.lastNewWebsocketDate.set(Date())
        guard let webSocket = GlobalDependencies.webSocketFactory.buildSocket(
            request: request,
            callbackQueue: OWSWebSocket.serialQueue
        ) else {
            owsFailDebug("Missing webSocket.")
            return
        }
        webSocket.delegate = self
        let newWebSocket = WebSocketConnection(webSocketType: webSocketType, webSocket: webSocket)
        self.currentWebSocket = newWebSocket

        // `connect` could hypothetically call a delegate method (e.g. if
        // the socket failed immediately for some reason), so we update currentWebSocket
        // _before_ calling it, not after.
        webSocket.connect()

        Self.serialQueue.asyncAfter(deadline: .now() + 30) { [weak self, weak newWebSocket] in
            guard let self = self,
                  let newWebSocket = newWebSocket,
                    let currentWebSocket = self.currentWebSocket,
                    currentWebSocket.id == newWebSocket.id else {
                return
            }

            if !newWebSocket.hasConnected.get() {
                Logger.warn("Websocket failed to connect.")
                self.cycleSocket()
            }
        }
    }

    // MARK: - Reconnect

    private var reconnectTimer: OffMainThreadTimer?

    // This method is thread-safe.
    private func ensureReconnectTimer() {
        serialQueue.async { [weak self] in
            guard let self = self else { return }
            if let reconnectTimer = self.reconnectTimer {
                owsAssertDebug(reconnectTimer.isValid)
            } else {
                // TODO: It'd be nice to do exponential backoff.
                self.reconnectTimer = OffMainThreadTimer(timeInterval: Self.socketReconnectDelaySeconds,
                                                         repeats: true) { [weak self] timer in
                    guard let self = self else {
                        timer.invalidate()
                        return
                    }
                    self.applyDesiredSocketState()
                }
            }
        }
    }

    // This method is thread-safe.
    private func clearReconnect() {
        assertOnQueue(serialQueue)

        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    // MARK: - Notifications

    @objc
    private func applicationDidBecomeActive(_ notification: NSNotification) {
        AssertIsOnMainThread()

        if Self.verboseLogging {
            Logger.info("\(self.logPrefix)")
        }

        appIsActive.set(true)

        applyDesiredSocketState()
    }

    @objc
    private func applicationWillResignActive(_ notification: NSNotification) {
        AssertIsOnMainThread()

        if Self.verboseLogging {
            Logger.info("\(self.logPrefix)")
        }

        appIsActive.set(false)

        applyDesiredSocketState()
    }

    @objc
    private func registrationStateDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        if verboseLogging {
            Logger.info("\(logPrefix) \(NSStringForOWSRegistrationState(tsAccountManager.registrationState()))")
        }

        applyDesiredSocketState()
    }

    @objc
    private func localNumberDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        if verboseLogging {
            Logger.info("\(logPrefix) \(NSStringForOWSRegistrationState(tsAccountManager.registrationState()))")
        }

        cycleSocket()
    }

    @objc
    private func isCensorshipCircumventionActiveDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        if Self.verboseLogging {
            Logger.info("\(self.logPrefix)")
        }

        cycleSocket()
    }

    @objc
    private func isSignalProxyReadyDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        if Self.verboseLogging {
            Logger.info("\(self.logPrefix)")
        }

        applyDesiredSocketState()
    }

    @objc
    private func deviceListUpdateModifiedDeviceList(_ notification: NSNotification) {
        AssertIsOnMainThread()

        if Self.verboseLogging {
            Logger.info("\(self.logPrefix)")
        }

        if webSocketType == .identified {
            cycleSocket()
        }
    }

    @objc
    private func appExpiryDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        if verboseLogging {
            Logger.info("\(logPrefix) \(appExpiry.isExpired)")
        }

        cycleSocket()
    }

    @objc
    private func storiesEnabledStateDidChange(_ notification: NSNotification) {
        AssertIsOnMainThread()

        cycleSocket()
    }
}

// MARK: -

extension OWSWebSocket {

    fileprivate static func label(forRequest request: TSRequest,
                                  webSocketType: OWSWebSocketType,
                                  requestInfo: SocketRequestInfo?) -> String {

        var label = "\(webSocketType), \(request)"
        if let requestInfo = requestInfo {
            label += ", [\(requestInfo.requestId)]"
        }
        return label
    }

    public func makeRequest(_ request: TSRequest,
                            unsubmittedRequestToken: UnsubmittedRequestToken,
                            success successParam: @escaping RequestSuccess,
                            failure failureParam: @escaping RequestFailure) {
        assertOnQueue(OWSWebSocket.serialQueue)

        guard !appExpiry.isExpired else {
            removeUnsubmittedRequestToken(unsubmittedRequestToken)

            DispatchQueue.global().async {
                guard let requestUrl = request.url else {
                    owsFail("Missing requestUrl.")
                }
                let error = OWSHTTPError.invalidAppState(requestUrl: requestUrl)
                let failure = OWSHTTPErrorWrapper(error: error)
                failureParam(failure)
            }
            return
        }

        let webSocketType = self.webSocketType

        let isIdentifiedSocket = webSocketType == .identified
        let isIdentifiedRequest = request.shouldHaveAuthorizationHeaders && !request.isUDRequest
        owsAssertDebug(isIdentifiedSocket == isIdentifiedRequest)

        self.makeRequestInternal(
            request,
            unsubmittedRequestToken: unsubmittedRequestToken,
            success: { (response: HTTPResponse, requestInfo: SocketRequestInfo) in
                let label = Self.label(forRequest: request, webSocketType: webSocketType, requestInfo: requestInfo)
                Logger.info("\(label): Request Succeeded (\(response.responseStatusCode))")

                successParam(response)

                Self.outageDetection.reportConnectionSuccess()
            },
            failure: { (failure: OWSHTTPErrorWrapper) in
                if failure.error.responseStatusCode == AppExpiry.appExpiredStatusCode {
                    Self.appExpiry.setHasAppExpiredAtCurrentVersion()
                }

                failureParam(failure)
            })
    }
}

// MARK: -

private class SocketRequestInfo {

    let request: TSRequest

    let requestUrl: URL

    let requestId: UInt64 = Cryptography.randomUInt64()

    let webSocketType: OWSWebSocketType

    let startDate = Date()

    var intervalSinceStartDateFormatted: String {
        startDate.formatIntervalSinceNow
    }

    // We use an enum to ensure that the completion handlers are
    // released as soon as the message completes.
    private enum Status {
        case incomplete(success: RequestSuccess, failure: RequestFailure)
        case complete
    }

    private let status: AtomicValue<Status>

    private let backgroundTask: OWSBackgroundTask

    public typealias RequestSuccess = OWSWebSocket.RequestSuccessInternal
    public typealias RequestFailure = OWSWebSocket.RequestFailure

    public required init(request: TSRequest,
                         requestUrl: URL,
                         webSocketType: OWSWebSocketType,
                         success: @escaping RequestSuccess,
                         failure: @escaping RequestFailure) {
        self.request = request
        self.requestUrl = requestUrl
        self.webSocketType = webSocketType
        self.status = AtomicValue(.incomplete(success: success, failure: failure))
        self.backgroundTask = OWSBackgroundTask(label: "SocketRequestInfo")
    }

    public func didSucceed(status: Int,
                           headers: OWSHttpHeaders,
                           bodyData: Data?) {
        let response = HTTPResponseImpl(requestUrl: requestUrl,
                                        status: status,
                                        headers: headers,
                                        bodyData: bodyData)
        didSucceed(response: response)
    }

    public func didSucceed(response: HTTPResponse) {
        // Ensure that we only complete once.
        switch status.swap(.complete) {
        case .complete:
            return
        case .incomplete(let success, _):
            DispatchQueue.global().async {
                success(response, self)
            }
        }
    }

    // Returns true if the message timed out.
    public func timeoutIfNecessary() -> Bool {
        if OWSWebSocket.verboseLogging {
            Logger.warn("\(webSocketType) \(requestUrl)")
        }

        return didFail(error: OWSHTTPError.networkFailure(requestUrl: requestUrl))
    }

    public func didFailInvalidRequest() {
        if OWSWebSocket.verboseLogging {
            Logger.warn("\(webSocketType) \(requestUrl)")
        }

        didFail(error: OWSHTTPError.invalidRequest(requestUrl: requestUrl))
    }

    public func didFailDueToNetwork() {
        if OWSWebSocket.verboseLogging {
            Logger.warn("\(webSocketType) \(requestUrl)")
        }

        didFail(error: OWSHTTPError.networkFailure(requestUrl: requestUrl))
    }

    public func didFail(responseStatus: Int,
                        responseHeaders: OWSHttpHeaders,
                        responseError: Error?,
                        responseData: Data?) {
        if OWSWebSocket.verboseLogging {
            Logger.warn("\(webSocketType), responseStatus: \(responseStatus), responseError: \(String(describing: responseError))")
        }

        let error = HTTPUtils.preprocessMainServiceHTTPError(request: request,
                                                             requestUrl: requestUrl,
                                                             responseStatus: responseStatus,
                                                             responseHeaders: responseHeaders,
                                                             responseError: responseError,
                                                             responseData: responseData)
        didFail(error: error)
    }

    @discardableResult
    private func didFail(error: Error) -> Bool {
        // Ensure that we only complete once.
        switch status.swap(.complete) {
        case .complete:
            return false
        case .incomplete(_, let failure):
            DispatchQueue.global().async {
                let statusCode = error.httpStatusCode ?? 0
                Logger.warn("didFail, status: \(statusCode), error: \(error)")

                let error = error as! OWSHTTPError
                let socketFailure = OWSHTTPErrorWrapper(error: error)
                failure(socketFailure)
            }
            return true
        }
    }
}

// MARK: -

extension OWSWebSocket: SSKWebSocketDelegate {

    public func websocketDidConnect(socket eventSocket: SSKWebSocket) {
        assertOnQueue(Self.serialQueue)

        guard let currentWebSocket = self.currentWebSocket,
              currentWebSocket.id == eventSocket.id else {
            // Ignore events from obsolete web sockets.
            return
        }

        currentWebSocket.didConnect(delegate: self)

        if webSocketType == .identified {
            // If socket opens, we know we're not de-registered.
            tsAccountManager.setIsDeregistered(false)
        }

        outageDetection.reportConnectionSuccess()

        notifyStatusChange()
    }

    public func websocketDidDisconnectOrFail(socket eventSocket: SSKWebSocket, error: Error) {
        assertOnQueue(Self.serialQueue)

        guard let currentWebSocket = self.currentWebSocket,
              currentWebSocket.id == eventSocket.id else {
            // Ignore events from obsolete web sockets.
            return
        }

        Logger.warn("Websocket did fail \(logPrefix): \(error)")

        self.currentWebSocket = nil

        if webSocketType == .identified, case WebSocketError.httpError(statusCode: 403, _) = error {
            tsAccountManager.setIsDeregistered(true)
        }

        if shouldSocketBeOpen {
            // If we should retry, use `ensureReconnectTimer` to reconnect after a delay.
            ensureReconnectTimer()
        } else {
            // Otherwise clean up and align state.
            applyDesiredSocketState()
        }

        outageDetection.reportConnectionFailure()
    }

    public func websocket(_ eventSocket: SSKWebSocket, didReceiveData data: Data) {
        assertOnQueue(Self.serialQueue)
        let message: WebSocketProtoWebSocketMessage
        do {
            message = try WebSocketProtoWebSocketMessage(serializedData: data)
        } catch {
            owsFailDebug("Failed to deserialize message: \(error)")
            return
        }

        guard let currentWebSocket = self.currentWebSocket,
              currentWebSocket.id == eventSocket.id else {
            // Ignore events from obsolete web sockets.
            return
        }

        if !message.hasType {
            owsFailDebug("webSocket:didReceiveResponse: missing type.")
        } else if message.unwrappedType == .request {
            if let request = message.request {
                processWebSocketRequestMessage(request, currentWebSocket: currentWebSocket)
            } else {
                owsFailDebug("Missing request.")
            }
        } else if message.unwrappedType == .response {
            if let response = message.response {
                processWebSocketResponseMessage(response, currentWebSocket: currentWebSocket)
            } else {
                owsFailDebug("Missing response.")
            }
        } else {
            owsFailDebug("webSocket:didReceiveResponse: unknown.")
        }
    }
}

// MARK: -

extension OWSWebSocket: WebSocketConnectionDelegate {
    fileprivate func webSocketSendHeartBeat(_ webSocket: WebSocketConnection) {
        if shouldSocketBeOpen {
            webSocket.writePing()
        } else {
            Logger.warn("Closing web socket: \(logPrefix).")
            applyDesiredSocketState()
        }
    }

    fileprivate func webSocketRequestDidTimeout() {
        cycleSocket()
    }
}

// MARK: -

private protocol WebSocketConnectionDelegate: AnyObject {
    func webSocketSendHeartBeat(_ webSocket: WebSocketConnection)
    func webSocketRequestDidTimeout()
}

// MARK: -

private class WebSocketConnection {

    private let webSocketType: OWSWebSocketType

    private let webSocket: SSKWebSocket

    private let unfairLock = UnfairLock()

    public var id: UInt { webSocket.id }

    public let hasEmptiedInitialQueue = AtomicBool(false)

    public var state: SSKWebSocketState { webSocket.state }

    private var requestInfoMap = AtomicDictionary<UInt64, SocketRequestInfo>()

    public var hasPendingRequests: Bool {
        !requestInfoMap.isEmpty
    }

    public let hasConnected = AtomicBool(false)

    public var logPrefix: String {
        "[\(webSocketType): \(id)]"
    }

    required init(webSocketType: OWSWebSocketType, webSocket: SSKWebSocket) {
        owsAssertDebug(!CurrentAppContext().isRunningTests)

        self.webSocketType = webSocketType
        self.webSocket = webSocket
    }

    deinit {
        if OWSWebSocket.verboseLogging {
            Logger.debug("\(logPrefix)")
        }

        reset()
    }

    private var heartbeatTimer: OffMainThreadTimer?

    func didConnect(delegate: WebSocketConnectionDelegate) {
        hasConnected.set(true)

        startHeartbeat(delegate: delegate)
    }

    private func startHeartbeat(delegate: WebSocketConnectionDelegate) {
        let heartbeatPeriodSeconds: TimeInterval = 30
        self.heartbeatTimer = OffMainThreadTimer(timeInterval: heartbeatPeriodSeconds,
                                                 repeats: true) { [weak self, weak delegate] timer in
            guard let self = self,
                  let delegate = delegate else {
                owsFailDebug("Missing self or delegate.")
                timer.invalidate()
                return
            }
            delegate.webSocketSendHeartBeat(self)
        }
    }

    func writePing() {
        webSocket.writePing()
    }

    func reset() {
        unfairLock.withLock {
            webSocket.delegate = nil
            webSocket.disconnect()
        }

        heartbeatTimer?.invalidate()
        self.heartbeatTimer = nil

        let requestInfos = requestInfoMap.removeAllValues()
        failPendingMessages(requestInfos: requestInfos)
    }

    private func failPendingMessages(requestInfos: [SocketRequestInfo]) {
        guard !requestInfos.isEmpty else {
            return
        }

        Logger.info("\(logPrefix): \(requestInfos.count).")

        for requestInfo in requestInfos {
            requestInfo.didFailDueToNetwork()
        }
    }

    // This method is thread-safe.
    fileprivate func sendRequest(requestInfo: SocketRequestInfo,
                                 messageData: Data,
                                 delegate: WebSocketConnectionDelegate) {
        requestInfoMap[requestInfo.requestId] = requestInfo

        webSocket.write(data: messageData)

        let socketTimeoutSeconds: TimeInterval = 10
        DispatchQueue.global().asyncAfter(deadline: .now() + socketTimeoutSeconds) { [weak delegate, weak requestInfo] in
            guard let delegate = delegate,
                  let requestInfo = requestInfo else {
                return
            }

            if requestInfo.timeoutIfNecessary() {
                delegate.webSocketRequestDidTimeout()
            }
        }
    }

    fileprivate func popRequestInfo(forRequestId requestId: UInt64) -> SocketRequestInfo? {
        requestInfoMap.removeValue(forKey: requestId)
    }

    fileprivate func sendResponse(for request: WebSocketProtoWebSocketRequestMessage,
                                  status: UInt32,
                                  message: String) throws {
        try webSocket.sendResponse(for: request, status: status, message: message)
    }
}
