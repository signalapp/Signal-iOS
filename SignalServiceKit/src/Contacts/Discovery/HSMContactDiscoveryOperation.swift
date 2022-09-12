//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit
import LibSignalClient

class HSMContactDiscoveryOperation: ContactDiscovering, CDSHWebSocketDelegate, Dependencies {
    static let batchSize = 5000
    private let e164sToLookup: Set<String>

    private var websocket: CDSHWebSocket!
    private var socketClosePromise: Promise<CDSHResult>?
    private var socketCloseFuture: Future<CDSHResult>?

    private let format = Format.v1
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
                    debugDescription: "Unknown error: \((error as NSError?).debugDescription)",
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

        try batches.enumerated().forEach { idx, batch in
            var builder = ContactDiscoveryMessageClientRequest.builder()
            let encodedE164s = try ContactDiscoveryE164Collection(batch).encodedValues
            builder.setNewE164List(encodedE164s)

            let lastBatchIdx = batches.count - 1
            builder.setMoreComing(idx != lastBatchIdx)

            var requestBody = Data()
            switch format {
            case .v1:
                requestBody.append(1)
            case .v2:
                requestBody.append(2)
                throw ContactDiscoveryError.assertionError(description: "v2 unsupported")
            }
            requestBody.append(try builder.buildSerializedData())
            self.websocket.sendBytes(requestBody)
        }
    }

    private func parseResults() throws -> Set<DiscoveredContactInfo> {
        let clientResponse = try ContactDiscoveryMessageClientResponse(serializedData: self.resultData)
        guard let triples = clientResponse.e164PniAciTriples else { return Set() }

        return try triples.chunked(by: 40).reduce(into: Set()) { builder, tripleBytes in
            if let triple = try parseTriple(tripleBytes) {
                builder.insert(triple.discoveredContact)
            }
        }
    }

    struct Triple {
        let e164: String
        let pni: UUID?
        let aci: UUID

        var discoveredContact: DiscoveredContactInfo {
            DiscoveredContactInfo(e164: e164, uuid: aci)
        }
    }

    private func parseTriple(_ bytes: Data.SubSequence) throws -> Triple? {
        guard bytes.count == 40 else {
            owsFailDebug("Invalid triple bytes")
            return nil
        }

        switch format {
        case .v1:
            let e164Buffer = bytes.prefix(8)
            let aciBuffer = bytes.dropFirst(24).prefix(16)

            // Nil values indicate this wasn't found
            guard e164Buffer.contains(where: { $0 != 0 }) else { return nil }
            guard aciBuffer.contains(where: { $0 != 0 }) else { return nil }

            return bytes.withUnsafeBytes { buffer -> Triple in
                let bigEndianE164 = buffer.load(fromByteOffset: 0, as: UInt64.self)
                let hostE164 = UInt64(bigEndian: bigEndianE164)
                let e164String = "+\(hostE164)"
                let aci = UUID(uuid: buffer.load(fromByteOffset: 24, as: uuid_t.self))

                return Triple(e164: e164String, pni: nil, aci: aci)
            }

        case .v2:
            throw ContactDiscoveryError.assertionError(description: "v2 unsupported")
        }
    }

    private func parseRetryAfterDate() -> Date {
        switch format {
        case .v1:
            // TODO: Currently unspecified for v1. Let's default to 30s for now
            return Date(timeIntervalSinceNow: 30)
        case .v2:
            owsFailDebug("v2 unsupported")
            return Date(timeIntervalSinceNow: 30)
        }
    }

    // MARK: - Delegate

    func socketDidReceiveData(_ socket: CDSHWebSocket, data: Data) {
        resultData.append(data)
    }

    func socketDidClose(_ socket: CDSHWebSocket, result: CDSHResult) {
        socketCloseFuture?.resolve(result)
    }
}

private extension HSMContactDiscoveryOperation {
    enum Format {
        case v1
        case v2
    }
}
