//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit
import SignalClient

class HSMContactDiscoveryOperation: ContactDiscovering, CDSHWebSocketDelegate, Dependencies {
    static let batchSize = 5000
    private let e164sToLookup: Set<String>

    private var websocket: CDSHWebSocket!
    private var socketClosePromise: Promise<CDSHResult>?
    private var socketCloseFuture: Future<CDSHResult>?

    private var resultData = Data()

    required init(e164sToLookup: Set<String>) {
        self.e164sToLookup = e164sToLookup
        Logger.debug("with e164sToLookup.count: \(e164sToLookup.count)")
    }

    func perform(on queue: DispatchQueue) -> Promise<Set<DiscoveredContactInfo>> {
        firstly {
            self.fetchAuthentication(on: queue)

        }.then(on: queue) { (username, password) -> Promise<Void> in
            let (promise, future) = Promise<CDSHResult>.pending()
            self.socketClosePromise = promise
            self.socketCloseFuture = future

            self.websocket = try CDSHWebSocket(callbackQueue: queue, username: username, password: password)
            self.websocket.delegate = self
            return self.websocket.bootstrapPromise()

        }.then(on: queue) { _ -> Promise<CDSHResult> in
            try self.sendRequestBody()
            if let resultPromise = self.socketClosePromise {
                return resultPromise
            } else {
                throw ContactDiscoveryError.assertionError(description: "Missing socket promise")
            }

        }.map(on: queue) { result in
            switch result {
            case .completed:
                return try self.parseResults()

            case .unauthenticated:
                throw ContactDiscoveryError(
                    kind: .unauthorized,
                    debugDescription: "User is unauthorized",
                    retryable: false,
                    retryAfterDate: self.parseRetryAfterDate())

            case .rateLimited:
                throw ContactDiscoveryError(
                    kind: .rateLimit,
                    debugDescription: "Rate limit",
                    retryable: true,
                    retryAfterDate: self.parseRetryAfterDate())

            case .invalidArgument:
                throw ContactDiscoveryError(
                    kind: .genericClientError,
                    debugDescription: "Bad argument",
                    retryable: false,
                    retryAfterDate: self.parseRetryAfterDate())

            case .serverError:
                throw ContactDiscoveryError(
                    kind: .genericServerError,
                    debugDescription: "Server error",
                    retryable: true,
                    retryAfterDate: self.parseRetryAfterDate())

            case .unknown(let networkError?) where networkError.isNetworkConnectivityFailure:
                // Anything network related should be returned directly
                throw networkError

            case .unknown(let error):
                throw ContactDiscoveryError(
                    kind: .generic,
                    debugDescription: "Unknown error: \(error?.userErrorDescription ?? "nil")",
                    retryable: false,
                    retryAfterDate: self.parseRetryAfterDate())
            }
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

    private func parseRetryAfterDate() -> Date {
        // TODO: Currently unspecified for v1. Let's default to 30s for now
        Date(timeIntervalSinceNow: 30)
    }

    // MARK: - Delegate

    func socketDidReceiveData(_ socket: CDSHWebSocket, data: Data) {
        resultData.append(data)
    }

    func socketDidClose(_ socket: CDSHWebSocket, result: CDSHResult) {
        socketCloseFuture?.resolve(result)
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
