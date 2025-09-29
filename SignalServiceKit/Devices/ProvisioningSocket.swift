//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol ProvisioningSocketDelegate: AnyObject {
    func provisioningSocket(_ provisioningSocket: ProvisioningSocket, didReceiveProvisioningUuid provisioningUuid: String)
    func provisioningSocket(_ provisioningSocket: ProvisioningSocket, didReceiveEnvelopeData data: Data)
    func provisioningSocket(_ provisioningSocket: ProvisioningSocket, didError error: Error)
}

// MARK: -

final public class ProvisioningSocket {
    public let id = UUID()
    public weak var delegate: ProvisioningSocketDelegate?

    let socket: SSKWebSocket

    public init(webSocketFactory: WebSocketFactory) {
        // TODO: Should we (sometimes?) use the unidentified service?
        let request = WebSocketRequest(
            signalService: .mainSignalServiceIdentified,
            urlPath: "v1/websocket/provisioning/",
            urlQueryItems: [URLQueryItem(name: "agent", value: LinkingProvisioningMessage.Constants.userAgent)],
            extraHeaders: [:]
        )
        let webSocket = webSocketFactory.buildSocket(request: request, callbackScheduler: DispatchQueue.main)!
        self.socket = webSocket
        webSocket.delegate = self
    }

    public convenience init() {
        self.init(webSocketFactory: SSKEnvironment.shared.webSocketFactoryRef)
    }

    public var state: SSKWebSocketState {
        return socket.state
    }

    public func disconnect(code: URLSessionWebSocketTask.CloseCode?) {
        heartBeatTimer?.invalidate()
        heartBeatTimer = nil
        socket.disconnect(code: code)
    }

    var heartBeatTimer: Timer?
    public func connect() {
        if heartBeatTimer == nil {
            heartBeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                guard self.state == .open else { return }

                self.socket.writePing()
            }
        }
        socket.connect()
    }
}

extension ProvisioningSocket: SSKWebSocketDelegate {
    public func websocketDidConnect(socket: SSKWebSocket) {
    }

    public func websocketDidDisconnectOrFail(socket: SSKWebSocket, error: Error) {
        delegate?.provisioningSocket(self, didError: error)
    }

    public func websocket(_ socket: SSKWebSocket, didReceiveData data: Data) {
        let message: WebSocketProtoWebSocketMessage
        do {
            message = try WebSocketProtoWebSocketMessage(serializedData: data)
        } catch {
            owsFailDebug("Failed to deserialize message: \(error)")
            return
        }

        guard let request = message.request else {
            owsFailDebug("unexpected message: \(message)")
            return
        }

        do {
            try handleRequest(request)
            try socket.sendResponse(for: request, status: 200, message: "OK")
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    private func handleRequest(_ request: WebSocketProtoWebSocketRequestMessage) throws {
        switch (request.verb, request.path) {
        case ("PUT", "/v1/address"):
            guard let body = request.body else {
                throw OWSAssertionError("body was unexpectedly nil")
            }
            let uuidProto = try ProvisioningProtoProvisioningUuid(serializedData: body)
            delegate?.provisioningSocket(self, didReceiveProvisioningUuid: uuidProto.uuid)
        case ("PUT", "/v1/message"):
            guard let body = request.body else {
                throw OWSAssertionError("body was unexpectedly nil")
            }
            delegate?.provisioningSocket(self, didReceiveEnvelopeData: body)
        default:
            throw OWSAssertionError("unexpected request: \(request)")
        }
    }
}
