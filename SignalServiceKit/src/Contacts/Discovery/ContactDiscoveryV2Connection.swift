//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

// MARK: -

protocol ContactDiscoveryV2ConnectionFactory {
    /// Connect to CDSv2 and perform the initial handshake.
    ///
    /// - Parameters:
    ///   - queue: The queue to use.
    /// - Returns:
    ///     A Promise for an established connection. If the Promise doesn’t
    ///     resolve to an error, the caller is responsible for ensuring the
    ///     returned connection is properly disconnected.
    func connectAndPerformHandshake(on queue: DispatchQueue) -> Promise<ContactDiscoveryV2Connection>
}

final class ContactDiscoveryV2ConnectionFactoryImpl: ContactDiscoveryV2ConnectionFactory {
    func connectAndPerformHandshake(on queue: DispatchQueue) -> Promise<ContactDiscoveryV2Connection> {
        firstly {
            RemoteAttestation.authForCDSI()
        }.then(on: queue) { auth -> Promise<ContactDiscoveryV2Connection> in
            try ContactDiscoveryV2ConnectionImpl.connectAndPerformHandshake(
                auth: auth,
                mrenclave: TSConstants.contactDiscoveryV2MrEnclave,
                queue: queue
            )
        }
    }
}

// MARK: -

/// Exposes a CDSv2 communication channel.
///
/// Types conforming to this protocol handle the initial handshake &
/// subsequent encryption/decryption of the exchanged messages.
protocol ContactDiscoveryV2Connection {
    func sendRequestAndReadResponse(_ request: Data) -> Promise<Data>
    func sendRequestAndReadAllResponses(_ request: Data) -> Promise<[Data]>
    func disconnect()
}

private class ContactDiscoveryV2ConnectionImpl: ContactDiscoveryV2Connection, Dependencies {
    private let webSocket: WebSocketPromise
    private let cds2Client: Cds2Client
    private let queue: DispatchQueue

    private init(webSocket: WebSocketPromise, cds2Client: Cds2Client, queue: DispatchQueue) {
        self.webSocket = webSocket
        self.cds2Client = cds2Client
        self.queue = queue
    }

    fileprivate static func connectAndPerformHandshake(
        auth: RemoteAttestation.Auth,
        mrenclave: MrEnclave,
        queue: DispatchQueue
    ) throws -> Promise<ContactDiscoveryV2Connection> {
        let webSocket = try buildSocket(auth: auth, mrenclave: mrenclave, queue: queue)
        return firstly(on: queue) {
            webSocket.waitForResponse()
        }.then(on: queue) { attestationMessage -> Promise<Cds2Client> in
            let cds2Client = try Cds2Client(
                mrenclave: mrenclave.dataValue,
                attestationMessage: attestationMessage,
                currentDate: Date()
            )
            return firstly {
                webSocket.send(data: Data(cds2Client.initialRequest()))
                return webSocket.waitForResponse()
            }.map(on: queue) { handshakeResponse -> Cds2Client in
                try cds2Client.completeHandshake(handshakeResponse)
                return cds2Client
            }
        }.map(on: queue) { cds2Client in
            ContactDiscoveryV2ConnectionImpl(webSocket: webSocket, cds2Client: cds2Client, queue: queue)
        }.recover(on: queue) { error -> Promise<ContactDiscoveryV2Connection> in
            Logger.warn("CDSv2: Disconnecting socket after failed handshake: \(error)")
            webSocket.disconnect()
            throw error
        }
    }

    private static func buildSocket(
        auth: RemoteAttestation.Auth,
        mrenclave: MrEnclave,
        queue: DispatchQueue
    ) throws -> WebSocketPromise {
        let authHeaderValue = try OWSHttpHeaders.authHeaderValue(username: auth.username, password: auth.password)
        let request = WebSocketRequest(
            signalService: .contactDiscoveryV2,
            urlPath: "v1/\(mrenclave.dataValue.hexadecimalString)/discovery",
            urlQueryItems: nil,
            extraHeaders: [OWSHttpHeaders.authHeaderKey: authHeaderValue]
        )
        guard let webSocketPromise = webSocketFactory.webSocketPromise(request: request, callbackQueue: queue) else {
            throw OWSAssertionError("We should always be able to get a web socket from this API.")
        }
        return webSocketPromise
    }

    func sendRequestAndReadResponse(_ request: Data) -> Promise<Data> {
        firstly(on: queue) { () -> Promise<Data> in
            try self.encryptAndSendRequest(request)
            return self.webSocket.waitForResponse()
        }.map(on: queue) { encryptedResponse in
            try self.decryptResponse(encryptedResponse)
        }
    }

    func sendRequestAndReadAllResponses(_ request: Data) -> Promise<[Data]> {
        firstly(on: queue) { () -> Promise<[Data]> in
            try self.encryptAndSendRequest(request)
            return self.webSocket.waitForAllResponses()
        }.map(on: queue) { encryptedResponses in
            try encryptedResponses.map { try self.decryptResponse($0) }
        }
    }

    private func encryptAndSendRequest(_ request: Data) throws {
        assertOnQueue(queue)

        let encryptedRequest = Data(try cds2Client.establishedSend(request))
        webSocket.send(data: encryptedRequest)
    }

    private func decryptResponse(_ encryptedResponse: Data) throws -> Data {
        assertOnQueue(queue)

        return Data(try cds2Client.establishedRecv(encryptedResponse))
    }

    func disconnect() {
        webSocket.disconnect()
    }
}
