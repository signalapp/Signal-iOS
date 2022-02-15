//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit
import SignalClient

class HSM1ContactDiscoveryOperation: ContactDiscovering, CDSHWebSocketDelegate, Dependencies {
    static let batchSize = 5000
    private let e164sToLookup: Set<String>

    private var websocket: CDSHWebSocket!
    private var socketClosePromise: Promise<Void>?
    private var socketCloseFuture: Future<Void>?

    private var resultData = Data()

    required init(e164sToLookup: Set<String>) {
        self.e164sToLookup = e164sToLookup
        Logger.debug("with e164sToLookup.count: \(e164sToLookup.count)")
    }

    func perform(on queue: DispatchQueue) -> Promise<Set<DiscoveredContactInfo>> {
        firstly {
            self.fetchAuthentication(on: queue)

        }.then(on: queue) { (username, password) -> Promise<Void> in
            let (promise, future) = Promise<Void>.pending()
            self.socketClosePromise = promise
            self.socketCloseFuture = future

            self.websocket = try CDSHWebSocket(callbackQueue: queue, username: username, password: password)
            self.websocket.delegate = self
            return self.websocket.bootstrapPromise()

        }.then(on: queue) { _ -> Promise<Void> in
            try self.sendRequestBody()
            return self.resultsPromise()

        }.map(on: queue) { _ in
            try self.parseResults()
        }
    }

    private func fetchAuthentication(on queue: DispatchQueue) -> Promise<(username: String, password: String)> {
        let request = OWSRequestFactory.hsmDirectoryAuthRequest()

        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: queue) { response in
            guard let json = response.responseBodyJson else {
                throw OWSAssertionError("Missing or invalid JSON.")
            }
            guard let parser = ParamParser(responseObject: json) else {
                throw OWSAssertionError("Missing or invalid response.")
            }
            let username: String = try parser.required(key: "username")
            let password: String = try parser.required(key: "password")
            return (username: username, password: password)
        }
    }

    private func sendRequestBody() throws {
        let batches = Array(self.e164sToLookup).chunked(by: Self.batchSize)

        try batches.enumerated().lazy.forEach { idx, batch in
            var builder = ContactDiscoveryMessageClientRequest.builder()
            let encodedE164s = try Self.encodePhoneNumbers(batch)
            builder.setNewE164List(encodedE164s)

            let lastBatchIdx = batches.count - 1
            builder.setMoreComing(idx != lastBatchIdx)

            var requestBody = Data()
            requestBody.append(1)
            requestBody.append(try builder.buildSerializedData())
            self.websocket.sendBytes(requestBody)
        }
    }

    private func resultsPromise() -> Promise<Void> {
        return socketClosePromise ?? .init()
    }

    private func parseResults() throws -> Set<DiscoveredContactInfo> {
        let clientResponse = try ContactDiscoveryMessageClientResponse(serializedData: self.resultData)
        guard let triples = clientResponse.e164PniAciTriples else { return Set() }

        return triples.chunked(by: 40).reduce(into: Set()) { builder, triple in
            guard triple.count == 40 else {
                owsFailDebug("Unexpected byte format")
                return
            }
            let e164Buffer = triple[0..<8]
            let aciBuffer = triple[24..<40]

//            For now, we don't need to parse PNIs. v1 CDSH won't vend them anyway
//            let pniBuffer = triple[8..<24]

            guard e164Buffer.contains(where: { $0 != 0 }) else { return }
            guard aciBuffer.contains(where: { $0 != 0 }) else { return }

            let (e164, parsedAci) = triple.withUnsafeBytes { buffer -> (String, UUID) in
                let bigEndianE164 = buffer.load(fromByteOffset: 0, as: UInt64.self)
                let hostE164 = UInt64(bigEndian: bigEndianE164)
                let aci = UUID(uuid: buffer.load(fromByteOffset: 24, as: uuid_t.self))
                return ("+\(hostE164)", aci)
            }
            builder.insert(DiscoveredContactInfo(e164: e164, uuid: parsedAci))
        }

    }

    // MARK: - Delegate

    func socketDidReceiveData(_ socket: CDSHWebSocket, data: Data) {
        Logger.info("\(data.count)")
        resultData.append(data)
    }

    func socketDidClose(_ socket: CDSHWebSocket, result: Int) {
        Logger.info("")
        socketCloseFuture?.resolve()
    }

    class func encodePhoneNumbers<T>(_ phoneNumbers: T) throws -> Data where T: Sequence, T.Element == String {
        var output = Data()

        for phoneNumber in phoneNumbers {
            guard phoneNumber.prefix(1) == "+" else {
                throw ContactDiscoveryError.assertionError(description: "unexpected id format")
            }

            let numericPortionIndex = phoneNumber.index(after: phoneNumber.startIndex)
            let numericPortion = phoneNumber.suffix(from: numericPortionIndex)

            guard let numericIdentifier = UInt64(numericPortion), numericIdentifier > 99 else {
                throw ContactDiscoveryError.assertionError(description: "unexpectedly short identifier")
            }

            var bigEndian: UInt64 = CFSwapInt64HostToBig(numericIdentifier)
            withUnsafePointer(to: &bigEndian) { pointer in
                output.append(UnsafeBufferPointer(start: pointer, count: 1))
            }
        }

        return output
    }

    class func uuidArray(from data: Data) -> [UUID] {
        return data.withUnsafeBytes {
            [uuid_t]($0.bindMemory(to: uuid_t.self))
        }.map {
            UUID(uuid: $0)
        }
    }
}

protocol CDSHWebSocketDelegate: AnyObject {
    func socketDidReceiveData(_ socket: CDSHWebSocket, data: Data)
    func socketDidClose(_ socket: CDSHWebSocket, result: Int)
}

public class CDSHWebSocket: Dependencies, SSKWebSocketDelegate {
    private let queue: DispatchQueue
    private let socket: SSKWebSocket
    private let enclaveClient: HsmEnclaveClient

    weak var delegate: CDSHWebSocketDelegate?

    enum State {
        case disconnected
        case connecting(Future<Void>)
        case connected
        case handshaking(Future<Data>)
        case established
        case finished
    }
    var state: State = .disconnected

    public init(callbackQueue: DispatchQueue, username: String, password: String) throws {
        queue = callbackQueue

        let publicKeyString = TSConstants.contactDiscoveryPublicKey
        let publicKeyBytes = try Data(hexString: publicKeyString)
        let codeHashStrings = TSConstants.contactDiscoveryCodeHashes

        let codeHashes = try codeHashStrings.reduce(into: HsmCodeHashList()) { builder, hexString in
            try builder.append(Data(hexString: hexString))
        }
        enclaveClient = try HsmEnclaveClient(publicKey: publicKeyBytes, codeHashes: codeHashes)


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

        socket = newSocket!
        socket.delegate = self
    }

    public func bootstrapPromise() -> Promise<Void> {
        firstly(on: queue) {
            self.performConnection()
        }.then(on: queue) {
            self.performHandshake()
        }
    }

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

    private func performConnection() -> Promise<Void> {
        firstly(on: queue) { () -> Promise<Void> in
            guard case .disconnected = self.state else {
                throw ContactDiscoveryError.assertionError(description: "Multiple attempts to connect")
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

            let handshakeRequest = try Data(self.enclaveClient.initialRequest())
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
        Logger.info("")
        assertOnQueue(queue)

        state = .finished
        delegate?.socketDidClose(self, result: 0)
    }

    public func websocket(
        _ socket: SSKWebSocket,
        didReceiveResponse response: SSKWebSocketResponse
    ) {
        assertOnQueue(queue)
        guard let data = response.unwrapData else {
            owsFailDebug("Expected raw data from websocket")
            return
        }
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
        let byteArray = Array<UInt8>(data)
        try append(byteArray)
    }
}

private extension Data {
    init(hexString: String) throws {
        self = try Data.data(fromHex: hexString) ?? {
            throw ContactDiscoveryError.assertionError(description: "Invalid hex string")
        }()
    }
}
