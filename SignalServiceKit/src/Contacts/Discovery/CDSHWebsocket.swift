//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public enum CDSHResult {
    case completed

    case unauthenticated
    case rateLimited
    case invalidArgument
    case serverError
    case unknown(Error?)
}

public protocol CDSHWebSocketDelegate: AnyObject {
    func socketDidReceiveData(_ socket: CDSHWebSocket, data: Data)
    func socketDidClose(_ socket: CDSHWebSocket, result: CDSHResult)
}

public class CDSHWebSocket: Dependencies, SSKWebSocketDelegate {
    private let queue: DispatchQueue
    private let socket: SSKWebSocket
    private let enclaveClient: HsmEnclaveClient
    public weak var delegate: CDSHWebSocketDelegate?

    private enum State {
        case disconnected
        case connecting(Future<Void>)
        case connected
        case handshaking(Future<Data>)
        case established
        case finished
    }

    private var state: State = .disconnected {
        didSet {
            Logger.verbose("State transition: \(oldValue) -> \(state)")
        }
    }

    public init(callbackQueue: DispatchQueue, username: String, password: String) throws {
        let publicKeyString = TSConstants.contactDiscoveryPublicKey
        let publicKeyBytes = try Data(hexString: publicKeyString)
        let codeHashStrings = TSConstants.contactDiscoveryCodeHashes

        let codeHashes = try codeHashStrings.reduce(into: HsmCodeHashList()) { builder, hexString in
            try builder.append(Data(hexString: hexString))
        }

        let codeHashString = codeHashStrings.joined(separator: ",")
        let baseUrl = URL(string: TSConstants.contactDiscoveryHSMURL)!
        let websocketUrl = URL(
            string: "\(TSConstants.contactDiscoveryPublicKey)/\(codeHashString)",
            relativeTo: baseUrl)!

        let httpHeaders = OWSHttpHeaders()
        httpHeaders.addDefaultHeaders()
        try httpHeaders.addAuthHeader(username: username, password: password)

        var request = URLRequest(url: websocketUrl)
        request.add(httpHeaders: httpHeaders)

        let newSocket = Self.webSocketFactory.buildSocket(
            request: request,
            callbackQueue: callbackQueue)

        queue = callbackQueue
        enclaveClient = try HsmEnclaveClient(publicKey: publicKeyBytes, codeHashes: codeHashes)
        socket = newSocket!
        socket.delegate = self
    }

    // MARK: - Public API

    /// Perform initial websocket connection and HSM handshake
    public func bootstrapPromise() -> Promise<Void> {
        firstly(on: queue) {
            self.performConnection()
        }.then(on: queue) {
            self.performHandshake()
        }
    }

    /// Encrypts and sends the plaintext to the CDSH service
    /// Must have waited on `bootstrapPromise` before calling this method
    public func sendBytes(_ plaintext: Data) {
        queue.async {
            guard case .established = self.state else {
                owsFailDebug("Trying to send to invalid cdsh socket: \(self.state)")
                return
            }

            do {
                let ciphertext = try self.enclaveClient.establishedSend(plaintext)
                self.socket.write(data: Data(ciphertext))
            } catch {
                owsFailDebug("Failed to construct HSM request body: \(error)")
            }
        }
    }

    // MARK: - Private

    private func performConnection() -> Promise<Void> {
        firstly(on: queue) { () -> Promise<Void> in
            guard case .disconnected = self.state else {
                throw ContactDiscoveryError.assertionError(description: "Invalid state")
            }
            let (connectPromise, connectFuture) = Promise<Void>.pending()
            self.state = .connecting(connectFuture)
            self.socket.connect()
            return connectPromise

        }.done(on: queue) {
            self.state = .connected
        }
    }

    private func performHandshake() -> Promise<Void> {
        return firstly(on: queue) { () -> Promise<Data> in
            guard case .connected = self.state else {
                throw ContactDiscoveryError.assertionError(description: "Invalid state")
            }
            let (handshakePromise, handshakeFuture) = Promise<Data>.pending()
            self.state = .handshaking(handshakeFuture)

            let handshakeRequest = Data(self.enclaveClient.initialRequest())
            self.socket.write(data: handshakeRequest)
            return handshakePromise

        }.done(on: queue) { response in
            try self.enclaveClient.completeHandshake(response)
            self.state = .established
        }
    }

    // MARK: - WebSocketDelegate

    public func websocketDidConnect(socket: SSKWebSocket) {
        assertOnQueue(queue)
        Logger.info("\(socket) did connect")

        switch state {
        case .connecting(let future):
            future.resolve()
        default:
            owsFailDebug("Invalid state during connect: \(state)")
        }
    }

    public func websocketDidDisconnectOrFail(socket: SSKWebSocket, error: Error?) {
        assertOnQueue(queue)
        Logger.info("Socket did disconnect with error: \(String(describing: error))")

        let resultCode: CDSHResult
        if let error = error {
            switch webSocketFactory.statusCode(forError: error) {
            case 1000: resultCode = .completed
            case 4003: resultCode = .invalidArgument
            case 4008: resultCode = .rateLimited
            case 4013: resultCode = .serverError
            case 4016: resultCode = .unauthenticated
            default: resultCode = .unknown(error)
            }
        } else {
            // We should always expect an error code, even in the success case.
            // If we don't have one, it's an error
            resultCode = .unknown(error)
        }

        state = .finished
        delegate?.socketDidClose(self, result: resultCode)
    }

    public func websocket(
        _ socket: SSKWebSocket,
        didReceiveData data: Data
    ) {
        assertOnQueue(queue)
        Logger.info("\(socket) did receive: \(data.count) bytes")

        switch state {
        case .handshaking(let future):
            future.resolve(data)

        case .established:
            do {
                let decryptedBytes = try enclaveClient.establishedRecv(data)
                delegate?.socketDidReceiveData(self, data: Data(decryptedBytes))
            } catch {
                owsFailDebug("Failed to decrypt bytes: \(error)")
            }

        default:
            owsFailDebug("Invalid state handling response: \(state)")
        }
    }
}

private extension HsmCodeHashList {
    mutating func append(_ data: Data) throws {
        let byteArray = [UInt8](data)
        try append(byteArray)
    }
}

// TODO: This should just be in SignalCoreKit next to Data.data(fromHex:)
private extension Data {
    init(hexString: String) throws {
        self = try Data.data(fromHex: hexString) ?? {
            throw ContactDiscoveryError.assertionError(description: "Invalid hex string")
        }()
    }
}
