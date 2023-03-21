//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalMessaging
import Starscream

public class WebSocketFactoryHybrid: WebSocketFactory, Dependencies {
    public init() {
    }

    public var canBuildWebSocket: Bool { true }

    public func buildSocket(request: WebSocketRequest, callbackQueue: DispatchQueue) -> SSKWebSocket? {
        let webSocketType: SSKWebSocket.Type
        if #available(iOS 13, *) {
            webSocketType = SSKWebSocketNative.self
        } else {
            webSocketType = SSKWebSocketStarScream.self
        }
        return webSocketType.init(request: request, signalService: signalService, callbackQueue: callbackQueue)
    }
}

// MARK: -

class SSKWebSocketStarScream: SSKWebSocket {

    private static let idCounter = AtomicUInt()
    public let id = SSKWebSocketStarScream.idCounter.increment()

    private let socket: Starscream.WebSocket

    public var callbackQueue: DispatchQueue { socket.callbackQueue }

    fileprivate let httpResponseHeaders = AtomicOptional<[String: String]>(nil)

    required init?(
        request: WebSocketRequest,
        signalService: OWSSignalServiceProtocol,
        callbackQueue: DispatchQueue
    ) {
        let endpoint = signalService.buildUrlEndpoint(for: request.signalService.signalServiceInfo())

        guard let urlRequest = request.build(for: endpoint) else {
            return nil
        }

        let socket = WebSocket(request: urlRequest)
        socket.callbackQueue = callbackQueue
        socket.disableSSLCertValidation = true
        socket.socketSecurityLevel = StreamSocketSecurityLevel.tlSv1_2
        let security = SSLSecurity(
            certs: endpoint.securityPolicy.pinnedCertificates.map { SSLCert(data: $0) },
            usePublicKeys: false
        )
        security.validateEntireChain = false
        socket.security = security

        // TODO cipher suite selection
        // socket.enabledSSLCipherSuites = [TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384, TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256]

        self.socket = socket

        socket.delegate = self
        socket.onHttpResponseHeaders = { [weak self] httpHeaders in
            self?.httpResponseHeaders.set(httpHeaders)
        }
    }

    // MARK: - SSKWebSocket

    weak var delegate: SSKWebSocketDelegate?

    private let hasEverConnected = AtomicBool(false)
    private let shouldReportError = AtomicBool(true)

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
        shouldReportError.set(false)
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
        let resolvedError: Error
        switch error {
        case .some(let wsError as WSError) where wsError.type == .protocolError:
            // Protocol errors include both normal closures & unexpected server behavior.
            resolvedError = WebSocketError.closeError(
                statusCode: wsError.code,
                closeReason: wsError.message.data(using: .utf8)
            )

        case .some(let wsError as WSError) where wsError.type == .upgradeError:
            // Upgrade errors occur in the HTTP layer during the web socket handshake.
            let httpHeaders = OWSHttpHeaders(httpHeaders: httpResponseHeaders.get(), overwriteOnConflict: true)
            resolvedError = WebSocketError.httpError(statusCode: wsError.code, retryAfter: httpHeaders.retryAfterDate)

        case .some(let wsError as WSError):
            resolvedError = wsError

        case .some(let nsError as NSError):
            // Assert that error is either a Starscream.WSError or an OS level networking error
            assert(nsError.domain == NSPOSIXErrorDomain
                   || nsError.domain == kCFErrorDomainCFNetwork as String
                   || nsError.domain == NSOSStatusErrorDomain)
            resolvedError = nsError

        case .none:
            // Based on how we use Starscream, we only expect a `nil` error in the case
            // where the underlying TCP connection is closed without going through the
            // normal web socket handshake. This should be reported as an error.
            resolvedError = OWSGenericError("Unexpected end of stream.")
        }

        guard shouldReportError.tryToClearFlag() else {
            return
        }

        delegate?.websocketDidDisconnectOrFail(socket: self, error: resolvedError)
    }

    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        assertOnQueue(callbackQueue)
        owsFailDebug("We only expect binary frames.")
    }

    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        assertOnQueue(callbackQueue)
        delegate?.websocket(self, didReceiveData: data)
    }
}

// MARK: -

private extension StreamSocketSecurityLevel {
    static var tlSv1_2: StreamSocketSecurityLevel {
        return StreamSocketSecurityLevel(rawValue: "kCFStreamSocketSecurityLevelTLSv1_2")
    }
}
