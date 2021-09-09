//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import Starscream

public enum SSKWebSocketState {
    case open, connecting, disconnected
}

// MARK: -

extension SSKWebSocketState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .open:
            return "SSKWebSocketState.open"
        case .connecting:
            return "SSKWebSocketState.connecting"
        case .disconnected:
            return "SSKWebSocketState.disconnected"
        }
    }
}

// MARK: -

// TODO: Eliminate.
@objc
public class SSKWebSocketError: NSObject, CustomNSError {

    let underlyingError: Starscream.WSError

    public var code: Int { underlyingError.code }

    init(underlyingError: Starscream.WSError) {
        self.underlyingError = underlyingError
    }

    // MARK: - CustomNSError

    @objc
    public static let errorDomain = "SignalServiceKit.SSKWebSocketError"

    public var errorUserInfo: [String: Any] {
        return [
            type(of: self).kStatusCodeKey: code,
            NSUnderlyingErrorKey: (underlyingError as NSError)
        ]
    }

    // MARK: -

    // TODO: Eliminate.
    @objc
    public static let kStatusCodeKey = "SSKWebSocketErrorStatusCode"

    public override var description: String {
        return "SSKWebSocketError - underlyingError: \(underlyingError)"
    }
}

// MARK: -

public protocol SSKWebSocket {

    var delegate: SSKWebSocketDelegate? { get set }

    var id: UInt { get }

    var state: SSKWebSocketState { get }

    func connect()
    func disconnect()

    func write(data: Data)

    func writePing()
}

public extension SSKWebSocket {
    func sendResponse(for request: WebSocketProtoWebSocketRequestMessage,
                      status: UInt32,
                      message: String) throws {
        let responseBuilder = WebSocketProtoWebSocketResponseMessage.builder(requestID: request.requestID,
                                                                             status: status)
        responseBuilder.setMessage(message)
        let response = try responseBuilder.build()

        let messageBuilder = WebSocketProtoWebSocketMessage.builder()
        messageBuilder.setType(.response)
        messageBuilder.setResponse(response)

        let messageData = try messageBuilder.buildSerializedData()

        write(data: messageData)
    }
}

// MARK: -

public protocol SSKWebSocketDelegate: AnyObject {
    func websocketDidConnect(socket: SSKWebSocket)

    func websocketDidDisconnectOrFail(socket: SSKWebSocket, error: Error?)

    func websocket(_ socket: SSKWebSocket, didReceiveMessage message: WebSocketProtoWebSocketMessage)
}

// MARK: -

public class SSKWebSocketManager: NSObject {
    public class func buildSocket(request: URLRequest,
                                  callbackQueue: DispatchQueue? = nil) -> SSKWebSocket {
        if #available(iOS 13, *) {
            return SSKWebSocketNative(request: request, callbackQueue: callbackQueue)
        } else {
            return SSKWebSocketStarScream(request: request, callbackQueue: callbackQueue)
        }
    }
}

// MARK: -

@available(iOS 13, *)
class SSKWebSocketNative: SSKWebSocket {

    private static let idCounter = AtomicUInt()
    public let id = SSKWebSocketNative.idCounter.increment()
    private var webSocketTask = AtomicOptional<URLSessionWebSocketTask>(nil)
    private let request: URLRequest
    private let session = OWSURLSession(
        securityPolicy: OWSURLSession.signalServiceSecurityPolicy,
        configuration: OWSURLSession.defaultConfigurationWithoutCaching
    )
    private let callbackQueue: DispatchQueue

    init(request: URLRequest,
         callbackQueue: DispatchQueue? = nil) {

        self.request = request
        self.callbackQueue = callbackQueue ?? .main
    }

    // MARK: - SSKWebSocket

    weak var delegate: SSKWebSocketDelegate?

    private let hasEverConnected = AtomicBool(false)
    private let isConnected = AtomicBool(false)

    // This method is thread-safe.
    var state: SSKWebSocketState {
        if isConnected.get() {
            return .open
        }

        if hasEverConnected.get() {
            return .disconnected
        }

        return .connecting
    }

    func connect() {
        guard webSocketTask.get() == nil else { return }

        let task = session.webSocketTask(request: request, didOpenBlock: { [weak self] _ in
            guard let self = self else { return }
            self.isConnected.set(true)
            self.hasEverConnected.set(true)

            self.listenForNextMessage()

            self.callbackQueue.asyncIfNecessary {
                self.delegate?.websocketDidConnect(socket: self)
            }
        }, didCloseBlock: { [weak self] closeCode, _ in
            guard let self = self else { return }
            self.isConnected.set(false)
            self.webSocketTask.set(nil)

            self.reportError(OWSGenericError("WebSocket did close with code \(closeCode)"))
        })
        webSocketTask.set(task)
    }

    func listenForNextMessage() {
        DispatchQueue.global().asyncIfNecessary { [weak self] in
            self?.webSocketTask.get()?.receive { result in
                switch result {
                case .success(let message):
                    switch message {
                    case .data(let data):
                        do {
                            let message = try WebSocketProtoWebSocketMessage(serializedData: data)
                            guard let self = self else { return }
                            self.callbackQueue.asyncIfNecessary {
                                self.delegate?.websocket(self, didReceiveMessage: message)
                            }
                        } catch {
                            owsFailDebug("error: \(error)")
                        }
                    case .string:
                        owsFailDebug("We only expect binary frames.")
                    @unknown default:
                        owsFailDebug("We only expect binary frames.")
                    }
                case .failure(let error):
                    Logger.warn("Error receiving websocket message \(error)")
                    self?.reportError(error)
                    // Don't try to listen again.
                    return
                }

                self?.listenForNextMessage()
            }
        }
    }

    func disconnect() {
        webSocketTask.get()?.cancel()
        webSocketTask.set(nil)
    }

    func write(data: Data) {
        guard let webSocketTask = webSocketTask.get() else {
            reportError(OWSGenericError("Missing webSocketTask."))
            return
        }
        webSocketTask.send(.data(data)) { [weak self] error in
            if let error = error {
                Logger.warn("Error sending websocket data \(error)")
            }
            self?.reportError(error)
        }
    }

    func writePing() {
        guard let webSocketTask = webSocketTask.get() else {
            reportError(OWSGenericError("Missing webSocketTask."))
            return
        }
        webSocketTask.sendPing { [weak self] error in
            if let error = error {
                Logger.warn("Error sending websocket ping \(error)")
            }
            self?.reportError(error)
        }
    }

    private func reportError(_ error: Error?) {
        callbackQueue.asyncIfNecessary { [weak self] in
            if let self = self,
               let delegate = self.delegate {
                delegate.websocketDidDisconnectOrFail(socket: self, error: error)
            }
        }
    }
}

// MARK: -

class SSKWebSocketStarScream: SSKWebSocket {

    private static let idCounter = AtomicUInt()
    public let id = SSKWebSocketStarScream.idCounter.increment()

    private let socket: Starscream.WebSocket

    public var callbackQueue: DispatchQueue { socket.callbackQueue }

    init(request: URLRequest,
         callbackQueue: DispatchQueue? = nil) {

        let socket = WebSocket(request: request)

        if let callbackQueue = callbackQueue {
            socket.callbackQueue = callbackQueue
        }

        socket.disableSSLCertValidation = true
        socket.socketSecurityLevel = StreamSocketSecurityLevel.tlSv1_2
        let security = SSLSecurity(certs: [TextSecureCertificate()], usePublicKeys: false)
        security.validateEntireChain = false
        socket.security = security

        // TODO cipher suite selection
        // socket.enabledSSLCipherSuites = [TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384, TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256]

        self.socket = socket

        socket.delegate = self
    }

    // MARK: - SSKWebSocket

    weak var delegate: SSKWebSocketDelegate?

    private let hasEverConnected = AtomicBool(false)

    // This method is thread-safe.
    var state: SSKWebSocketState {
        if socket.isConnected {
            return .open
        }

        if hasEverConnected.get() {
            return .disconnected
        }

        return .connecting
    }

    func connect() {
        socket.connect()
    }

    func disconnect() {
        socket.disconnect()
    }

    func write(data: Data) {
        socket.write(data: data)
    }

    func writePing() {
        socket.write(ping: Data())
    }
}

// MARK: -

extension SSKWebSocketStarScream: WebSocketDelegate {
    func websocketDidConnect(socket: WebSocketClient) {
        assertOnQueue(callbackQueue)
        hasEverConnected.set(true)
        delegate?.websocketDidConnect(socket: self)
    }

    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        assertOnQueue(callbackQueue)
        let websocketError: Error?
        switch error {
        case let wsError as WSError:
            websocketError = SSKWebSocketError(underlyingError: wsError)
        case let nsError as NSError:
            // Assert that error is either a Starscream.WSError or an OS level networking error
            assert(nsError.domain == NSPOSIXErrorDomain as String
                || nsError.domain == kCFErrorDomainCFNetwork as String
                || nsError.domain == NSOSStatusErrorDomain as String)
            websocketError = error
        default:
            assert(error == nil, "unexpected error type: \(String(describing: error))")
            websocketError = error
        }

        delegate?.websocketDidDisconnectOrFail(socket: self, error: websocketError)
    }

    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        assertOnQueue(callbackQueue)
        owsFailDebug("We only expect binary frames.")
    }

    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        assertOnQueue(callbackQueue)
        do {
            let message = try WebSocketProtoWebSocketMessage(serializedData: data)
            delegate?.websocket(self, didReceiveMessage: message)
        } catch {
            owsFailDebug("error: \(error)")
        }
    }
}

// MARK: -

private func TextSecureCertificate() -> SSLCert {
    let data = SSKTextSecureServiceCertificateData()
    return SSLCert(data: data)
}

// MARK: -

private extension StreamSocketSecurityLevel {
    static var tlSv1_2: StreamSocketSecurityLevel {
        return StreamSocketSecurityLevel(rawValue: "kCFStreamSocketSecurityLevelTLSv1_2")
    }
}
