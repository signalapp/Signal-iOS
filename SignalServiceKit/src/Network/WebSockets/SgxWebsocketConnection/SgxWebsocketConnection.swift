//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit
import SwiftProtobuf

/// Exposes a SgxClient-conformant server communication channel.
///
/// This handles the initial handshake & subsequent encryption/decryption
/// of the exchanged messages using an `SgxClient` instance provided
/// by a `SgxWebsocketConfigurator`.
///
/// While this is a class, there should never be an instance of this base class; all instances
/// should be of a concrete subclass. It is only a class and not a protocol so users can refer
/// to an instance by config type without specifying the implementation,
/// e.g. `SgxWebsocketConnection<FooServerConfigurator>`.
/// That is not possible for a protocol with an associated type.
public class SgxWebsocketConnection<Configurator: SgxWebsocketConfigurator> {

    // Never add an initializer to this class; instances should be impossible.
    fileprivate init() {}

    public var mrEnclave: MrEnclave { fatalError("Concrete subclass must implement") }

    public var client: Configurator.Client { fatalError("Concrete subclass must implement") }

    public var auth: RemoteAttestation.Auth { fatalError("Concrete subclass must implement") }

    // Subclasses must implement.
    func sendRequestAndReadResponse(_ request: Configurator.Request) -> Promise<Configurator.Response> {
        fatalError("Concrete subclass must implement")
    }

    // Subclasses must implement.
    func sendRequestAndReadAllResponses(_ request: Configurator.Request) -> Promise<[Configurator.Response]> {
        fatalError("Concrete subclass must implement")
    }

    // Subclasses must implement.
    func disconnect() {
        fatalError("Concrete subclass must implement")
    }
}

public class SgxWebsocketConnectionImpl<Configurator: SgxWebsocketConfigurator>: SgxWebsocketConnection<Configurator> {

    private let webSocket: WebSocketPromise
    private let configurator: Configurator
    private let _client: Configurator.Client
    private let _auth: RemoteAttestation.Auth
    private let scheduler: Scheduler

    private init(
        webSocket: WebSocketPromise,
        configurator: Configurator,
        client: Configurator.Client,
        auth: RemoteAttestation.Auth,
        scheduler: Scheduler
    ) {
        self.webSocket = webSocket
        self.configurator = configurator
        self._client = client
        self._auth = auth
        self.scheduler = scheduler
        super.init()
    }

    internal static func connectAndPerformHandshake(
        configurator: Configurator,
        auth: RemoteAttestation.Auth,
        websocketFactory: WebSocketFactory,
        scheduler: Scheduler
    ) throws -> Promise<SgxWebsocketConnection<Configurator>> {
        let webSocket = try buildSocket(
            configurator: configurator,
            auth: auth,
            websocketFactory: websocketFactory,
            scheduler: scheduler
        )
        return firstly(on: scheduler) {
            webSocket.waitForResponse()
        }.then(on: scheduler) { attestationMessage -> Promise<Configurator.Client> in
            let client = try Configurator.client(
                mrenclave: configurator.mrenclave,
                attestationMessage: attestationMessage,
                currentDate: Date()
            )
            return firstly {
                webSocket.send(data: Data(client.initialRequest()))
                return webSocket.waitForResponse()
            }.map(on: scheduler) { handshakeResponse -> Configurator.Client in
                try client.completeHandshake(handshakeResponse)
                return client
            }
        }.map(on: scheduler) { client -> SgxWebsocketConnection<Configurator> in
            return SgxWebsocketConnectionImpl<Configurator>(
                webSocket: webSocket,
                configurator: configurator,
                client: client,
                auth: auth,
                scheduler: scheduler
            )
        }.recover(on: scheduler) { error -> Promise<SgxWebsocketConnection<Configurator>> in
            Logger.warn("\(type(of: configurator).loggingName): Disconnecting socket after failed handshake: \(error)")
            webSocket.disconnect()
            throw error
        }
    }

    private static func buildSocket(
        configurator: Configurator,
        auth: RemoteAttestation.Auth,
        websocketFactory: WebSocketFactory,
        scheduler: Scheduler
    ) throws -> WebSocketPromise {
        let authHeaderValue = try OWSHttpHeaders.authHeaderValue(username: auth.username, password: auth.password)
        let request = WebSocketRequest(
            signalService: Configurator.signalServiceType,
            urlPath: Configurator.websocketUrlPath(mrenclaveString: configurator.mrenclave.dataValue.hexadecimalString),
            urlQueryItems: nil,
            extraHeaders: [OWSHttpHeaders.authHeaderKey: authHeaderValue]
        )
        guard let webSocketPromise = websocketFactory.webSocketPromise(request: request, callbackScheduler: scheduler) else {
            throw OWSAssertionError("We should always be able to get a web socket from this API.")
        }
        return webSocketPromise
    }

    public override var mrEnclave: MrEnclave { return configurator.mrenclave }

    public override var client: Configurator.Client { return _client }

    public override var auth: RemoteAttestation.Auth { return _auth }

    public override func sendRequestAndReadResponse(
        _ request: Configurator.Request
    ) -> Promise<Configurator.Response> {
        firstly(on: scheduler) { () -> Promise<Data> in
            try self.encryptAndSendRequest(request.serializedData())
            return self.webSocket.waitForResponse()
        }.map(on: scheduler) { encryptedResponse in
            let data = try self.decryptResponse(encryptedResponse)
            return try Configurator.Response(serializedData: data)
        }
    }

    public override func sendRequestAndReadAllResponses(
        _ request: Configurator.Request
    ) -> Promise<[Configurator.Response]> {
        firstly(on: scheduler) { () -> Promise<[Data]> in
            try self.encryptAndSendRequest(request.serializedData())
            return self.webSocket.waitForAllResponses()
        }.map(on: scheduler) { encryptedResponses in
            try encryptedResponses.map {
                let data = try self.decryptResponse($0)
                return try Configurator.Response(serializedData: data)
            }
        }
    }

    private func encryptAndSendRequest(_ request: Data) throws {
        let encryptedRequest = Data(try client.establishedSend(request))
        webSocket.send(data: encryptedRequest)
    }

    private func decryptResponse(_ encryptedResponse: Data) throws -> Data {
        return Data(try client.establishedRecv(encryptedResponse))
    }

    public override func disconnect() {
        webSocket.disconnect()
    }
}

#if TESTABLE_BUILD

public class MockSgxWebsocketConnection<Configurator: SgxWebsocketConfigurator>: SgxWebsocketConnection<Configurator> {

    internal override init() {
        super.init()
    }

    public var mockEnclave: MrEnclave!

    public override var mrEnclave: MrEnclave { return mockEnclave }

    public var mockClient: Configurator.Client!

    public override var client: Configurator.Client { return mockClient }

    public var mockAuth: RemoteAttestation.Auth!

    public override var auth: RemoteAttestation.Auth { return mockAuth }

    public var onSendRequestAndReadResponse: ((Configurator.Request) -> Promise<Configurator.Response>)?

    public override func sendRequestAndReadResponse(
        _ request: Configurator.Request
    ) -> Promise<Configurator.Response> {
        onSendRequestAndReadResponse!(request)
    }

    public var onSendRequestAndReadAllResponses: ((Configurator.Request) -> Promise<[Configurator.Response]>)?

    public override func sendRequestAndReadAllResponses(
        _ request: Configurator.Request
    ) -> Promise<[Configurator.Response]> {
        onSendRequestAndReadAllResponses!(request)
    }

    public var onDisconnect: (() -> Void)?

    public override func disconnect() {
        onDisconnect?()
    }
}

#endif
