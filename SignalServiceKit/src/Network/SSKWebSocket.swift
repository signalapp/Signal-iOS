//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import Starscream

@objc
public enum SSKWebSocketState: UInt {
    case open, connecting, disconnected
}

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

@objc
public class SSKWebSocketError: NSObject, CustomNSError {

    init(underlyingError: Starscream.WSError) {
        self.underlyingError = underlyingError
    }

    // MARK: - CustomNSError

    @objc
    public static let errorDomain = "SignalServiceKit.SSKWebSocketError"

    public var errorUserInfo: [String: Any] {
        return [
            type(of: self).kStatusCodeKey: underlyingError.code,
            NSUnderlyingErrorKey: (underlyingError as NSError)
        ]
    }

    // MARK: -

    @objc
    public static let kStatusCodeKey = "SSKWebSocketErrorStatusCode"

    let underlyingError: Starscream.WSError

    public override var description: String {
        return "SSKWebSocketError - underlyingError: \(underlyingError)"
    }
}

@objc
public protocol SSKWebSocket {

    @objc
    var delegate: SSKWebSocketDelegate? { get set }

    @objc
    var state: SSKWebSocketState { get }

    @objc
    func connect()

    @objc
    func disconnect()

    @objc(writeData:)
    func write(data: Data)

    @objc
    func writePing()

    @objc(sendResponseForRequest:status:message:error:)
    func sendResponse(for request: WebSocketProtoWebSocketRequestMessage, status: UInt32, message: String) throws
}

@objc
public protocol SSKWebSocketDelegate: class {
    func websocketDidConnect(socket: SSKWebSocket)

    func websocketDidDisconnect(socket: SSKWebSocket, error: Error?)

    func websocket(_ socket: SSKWebSocket, didReceiveMessage message: WebSocketProtoWebSocketMessage)
}

@objc
public class SSKWebSocketManager: NSObject {

    @objc
    public class func buildSocket(request: URLRequest) -> SSKWebSocket {
        return SSKWebSocketImpl(request: request)
    }
}

class SSKWebSocketImpl: SSKWebSocket {

    private let socket: Starscream.WebSocket

    init(request: URLRequest) {
        let socket = WebSocket(request: request)

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

    var hasEverConnected = false
    var state: SSKWebSocketState {
        if socket.isConnected {
            return .open
        }

        if hasEverConnected {
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

    func sendResponse(for request: WebSocketProtoWebSocketRequestMessage, status: UInt32, message: String) throws {
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

extension SSKWebSocketImpl: WebSocketDelegate {
    func websocketDidConnect(socket: WebSocketClient) {
        hasEverConnected = true
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

private func TextSecureCertificate() -> SSLCert {
    let data = SSKTextSecureServiceCertificateData()
    return SSLCert(data: data)
}

private extension StreamSocketSecurityLevel {
    static var tlSv1_2: StreamSocketSecurityLevel {
        return StreamSocketSecurityLevel(rawValue: "kCFStreamSocketSecurityLevelTLSv1_2")
    }
}
