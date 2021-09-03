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

    func sendResponse(for request: WebSocketProtoWebSocketRequestMessage, status: UInt32, message: String) throws
}

// MARK: -

public protocol SSKWebSocketDelegate: AnyObject {
    func websocketDidConnect(socket: SSKWebSocket)

    func websocketDidDisconnect(socket: SSKWebSocket, error: Error?)

    func websocket(_ socket: SSKWebSocket, didReceiveMessage message: WebSocketProtoWebSocketMessage)
}

// MARK: -

public class SSKWebSocketManager: NSObject {
    public class func buildSocket(request: URLRequest,
                                  callbackQueue: DispatchQueue? = nil) -> SSKWebSocket {
        SSKWebSocketImpl(request: request, callbackQueue: callbackQueue)
    }
}

// MARK: -

class SSKWebSocketImpl: SSKWebSocket {

    private static let idCounter = AtomicUInt()
    public let id = SSKWebSocketImpl.idCounter.increment()

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

        socket.write(data: messageData)
    }
}

// MARK: -

extension SSKWebSocketImpl: WebSocketDelegate {
    func websocketDidConnect(socket: WebSocketClient) {
        hasEverConnected.set(true)
        delegate?.websocketDidConnect(socket: self)
    }

    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
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

        delegate?.websocketDidDisconnect(socket: self, error: websocketError)
    }

    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        owsFailDebug("We only expect binary frames.")
    }

    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
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
