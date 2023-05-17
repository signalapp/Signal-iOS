//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

// MARK: -

/// Exposes a SgxClient-conformant server communication channel.
///
/// This handles the initial handshake & subsequent encryption/decryption
/// of the exchanged messages using an `SgxClient` instance provided
/// by a `SgxWebsocketConfigurator`.
public protocol SgxWebsocketConnection {

    func sendRequestAndReadResponse(_ request: Data) -> Promise<Data>
    func sendRequestAndReadAllResponses(_ request: Data) -> Promise<[Data]>
    func disconnect()
}

public class SgxWebsocketConnectionImpl<Configurator: SgxWebsocketConfigurator>: SgxWebsocketConnection {

    private let webSocket: WebSocketPromise
    private let configurator: Configurator
    private let client: SgxClient
    private let queue: DispatchQueue

    private init(
        webSocket: WebSocketPromise,
        configurator: Configurator,
        client: SgxClient,
        queue: DispatchQueue
    ) {
        self.webSocket = webSocket
        self.configurator = configurator
        self.client = client
        self.queue = queue
    }

    internal static func connectAndPerformHandshake(
        configurator: Configurator,
        auth: RemoteAttestation.Auth,
        websocketFactory: WebSocketFactory,
        queue: DispatchQueue
    ) throws -> Promise<SgxWebsocketConnection> {
        let webSocket = try buildSocket(
            configurator: configurator,
            auth: auth,
            websocketFactory: websocketFactory,
            queue: queue
        )
        return firstly(on: queue) {
            webSocket.waitForResponse()
        }.then(on: queue) { attestationMessage -> Promise<SgxClient> in
            let client = try Configurator.client(
                mrenclave: configurator.mrenclave,
                attestationMessage: attestationMessage,
                currentDate: Date()
            )
            return firstly {
                webSocket.send(data: Data(client.initialRequest()))
                return webSocket.waitForResponse()
            }.map(on: queue) { handshakeResponse -> SgxClient in
                try client.completeHandshake(handshakeResponse)
                return client
            }
        }.map(on: queue) { client in
            SgxWebsocketConnectionImpl(
                webSocket: webSocket,
                configurator: configurator,
                client: client,
                queue: queue
            )
        }.recover(on: queue) { error -> Promise<SgxWebsocketConnection> in
            Logger.warn("\(type(of: configurator).loggingName): Disconnecting socket after failed handshake: \(error)")
            webSocket.disconnect()
            throw error
        }
    }

    private static func buildSocket(
        configurator: Configurator,
        auth: RemoteAttestation.Auth,
        websocketFactory: WebSocketFactory,
        queue: DispatchQueue
    ) throws -> WebSocketPromise {
        let authHeaderValue = try OWSHttpHeaders.authHeaderValue(username: auth.username, password: auth.password)
        let request = WebSocketRequest(
            signalService: Configurator.signalServiceType,
            urlPath: Configurator.websocketUrlPath(mrenclaveString: configurator.mrenclave.dataValue.hexadecimalString),
            urlQueryItems: nil,
            extraHeaders: [OWSHttpHeaders.authHeaderKey: authHeaderValue]
        )
        guard let webSocketPromise = websocketFactory.webSocketPromise(request: request, callbackQueue: queue) else {
            throw OWSAssertionError("We should always be able to get a web socket from this API.")
        }
        return webSocketPromise
    }

    public func sendRequestAndReadResponse(_ request: Data) -> Promise<Data> {
        firstly(on: queue) { () -> Promise<Data> in
            try self.encryptAndSendRequest(request)
            return self.webSocket.waitForResponse()
        }.map(on: queue) { encryptedResponse in
            try self.decryptResponse(encryptedResponse)
        }
    }

    public func sendRequestAndReadAllResponses(_ request: Data) -> Promise<[Data]> {
        firstly(on: queue) { () -> Promise<[Data]> in
            try self.encryptAndSendRequest(request)
            return self.webSocket.waitForAllResponses()
        }.map(on: queue) { encryptedResponses in
            try encryptedResponses.map { try self.decryptResponse($0) }
        }
    }

    private func encryptAndSendRequest(_ request: Data) throws {
        assertOnQueue(queue)

        let encryptedRequest = Data(try client.establishedSend(request))
        webSocket.send(data: encryptedRequest)
    }

    private func decryptResponse(_ encryptedResponse: Data) throws -> Data {
        assertOnQueue(queue)

        return Data(try client.establishedRecv(encryptedResponse))
    }

    public func disconnect() {
        webSocket.disconnect()
    }
}
