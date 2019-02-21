//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import Starscream

@objc
public enum SSKWebSocketState: UInt {
    case open, connecting, disconnected
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

    @objc(writeData:error:)
    func write(data: Data) throws

    @objc
    func writePing() throws
}

@objc
public protocol SSKWebSocketDelegate: class {
    func websocketDidConnect(socket: SSKWebSocket)

    func websocketDidDisconnect(socket: SSKWebSocket, error: Error?)

    func websocketDidReceiveData(socket: SSKWebSocket, data: Data)

    @objc optional func websocketDidReceiveMessage(socket: SSKWebSocket, text: String)
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

    func write(data: Data) throws {
        socket.write(data: data)
    }

    func writePing() throws {
        socket.write(ping: Data())
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
        default:
            assert(error == nil, "unexpected error type: \(String(describing: error))")
            websocketError = error
        }

        delegate?.websocketDidDisconnect(socket: self, error: websocketError)
    }

    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        if let websocketDidReceiveMessage = self.delegate?.websocketDidReceiveMessage {
            websocketDidReceiveMessage(self, text)
        }
    }

    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        delegate?.websocketDidReceiveData(socket: self, data: data)
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
