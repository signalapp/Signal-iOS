//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol ProvisioningSocketDelegate: AnyObject {
    func provisioningSocket(_ provisioningSocket: ProvisioningSocket, didReceiveDeviceId deviceID: String)
    func provisioningSocket(_ provisioningSocket: ProvisioningSocket, didReceiveEnvelope envelope: ProvisioningProtoProvisionEnvelope)
    func provisioningSocket(_ provisioningSocket: ProvisioningSocket, didError error: Error)
}

// MARK: -

public class ProvisioningSocket {
    let socket: SSKWebSocket
    public weak var delegate: ProvisioningSocketDelegate?

    public init(webSocketFactory: WebSocketFactory) {
        // TODO: Should we (sometimes?) use the unidentified service?
        let request = WebSocketRequest(
            signalService: .mainSignalServiceIdentified,
            urlPath: "v1/websocket/provisioning/",
            urlQueryItems: [URLQueryItem(name: "agent", value: OWSDeviceProvisioner.userAgent)],
            extraHeaders: [:]
        )
        let webSocket = webSocketFactory.buildSocket(request: request, callbackQueue: .main)!
        self.socket = webSocket
        webSocket.delegate = self
    }

    public convenience init() {
        struct GlobalDependencies: Dependencies {}
        self.init(webSocketFactory: GlobalDependencies.webSocketFactory)
    }

    public var state: SSKWebSocketState {
        return socket.state
    }

    public func disconnect() {
        heartBeatTimer?.invalidate()
        heartBeatTimer = nil
        socket.disconnect()
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
        Logger.debug("")
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
        Logger.debug("message: \(request.verb) \(request.path)")
        switch (request.verb, request.path) {
        case ("PUT", "/v1/address"):
            guard let body = request.body else {
                throw OWSAssertionError("body was unexpectedly nil")
            }
            let uuidProto = try ProvisioningProtoProvisioningUuid(serializedData: body)
            delegate?.provisioningSocket(self, didReceiveDeviceId: uuidProto.uuid)
        case ("PUT", "/v1/message"):
            guard let body = request.body else {
                throw OWSAssertionError("body was unexpectedly nil")
            }
            let envelopeProto = try ProvisioningProtoProvisionEnvelope(serializedData: body)
            delegate?.provisioningSocket(self, didReceiveEnvelope: envelopeProto)
        default:
            throw OWSAssertionError("unexpected request: \(request)")
        }
    }
}
