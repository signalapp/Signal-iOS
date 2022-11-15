//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

struct CDSRegisteredContact: Hashable {
    let signalUuid: UUID
    let e164PhoneNumber: String
}

/// Fetches contact info from the ContactDiscoveryService
/// Intended to be used by ContactDiscoveryTaskQueue. You probably don't want to use this directly.
class SGXContactDiscoveryOperation: ContactDiscovering {
    static let batchSize = 2048

    private let e164sToLookup: Set<String>
    required init(e164sToLookup: Set<String>) {
        self.e164sToLookup = e164sToLookup
        Logger.debug("with e164sToLookup.count: \(e164sToLookup.count)")
    }

    func perform(on queue: DispatchQueue) -> Promise<Set<DiscoveredContactInfo>> {
        firstly { () -> Promise<[Set<CDSRegisteredContact>]> in
            // First, build a bunch of batch Promises
            let batchOperationPromises = Array(e164sToLookup)
                .chunked(by: Self.batchSize)
                .map { makeContactDiscoveryRequest(e164sToLookup: Array($0)) }

            // Then, wait for them all to be fulfilled before joining the subsets together
            return Promise.when(fulfilled: batchOperationPromises)

        }.map(on: queue) { (setArray) -> Set<DiscoveredContactInfo> in
            setArray.reduce(into: Set()) { (builder, cdsContactSubset) in
                builder.formUnion(cdsContactSubset.map {
                    DiscoveredContactInfo(e164: $0.e164PhoneNumber, uuid: $0.signalUuid)
                })
            }
        }.recover(on: queue) { error -> Promise<Set<DiscoveredContactInfo>> in
            throw Self.prepareExternalError(from: error)
        }
    }

    // Below, we have a bunch of then blocks being performed on a global concurrent queue
    // It might be worthwhile to audit and see if we can move these onto the queue passed into `perform(on:)`

    private func makeContactDiscoveryRequest(e164sToLookup: [String]) -> Promise<Set<CDSRegisteredContact>> {
        firstly { () -> Promise<RemoteAttestation.CDSAttestation> in
            RemoteAttestation.performForCDS()

        }.then(on: .global()) { (attestation: RemoteAttestation.CDSAttestation) -> Promise<(RemoteAttestation.CDSAttestation, ContactDiscoveryService.IntersectionResponse)> in
            let service = ContactDiscoveryService()
            let query = try self.buildIntersectionQuery(e164sToLookup: e164sToLookup,
                                                        remoteAttestations: attestation.remoteAttestations)
            return service.getRegisteredSignalUsers(
                query: query,
                cookies: attestation.cookies,
                authUsername: attestation.auth.username,
                authPassword: attestation.auth.password,
                enclaveName: attestation.enclaveConfig.enclaveName,
                host: attestation.enclaveConfig.host,
                censorshipCircumventionPrefix: attestation.enclaveConfig.censorshipCircumventionPrefix
            ).map {(attestation, $0)}

        }.map(on: .global()) { attestation, response -> Set<CDSRegisteredContact> in
            let allEnclaveAttestations = attestation.remoteAttestations
            let respondingEnclaveAttestation = allEnclaveAttestations.first(where: { $1.requestId == response.requestId })

            guard let responseAttestion = respondingEnclaveAttestation?.value else {
                throw ContactDiscoveryError.assertionError(description: "Invalid responding enclave for requestId: \(response.requestId)")
            }
            guard let plaintext = Cryptography.decryptAESGCM(
                withInitializationVector: response.iv,
                ciphertext: response.data,
                additionalAuthenticatedData: nil,
                authTag: response.mac,
                key: responseAttestion.keys.serverKey) else {
                throw ContactDiscoveryError.assertionError(description: "decryption failed")
            }

            // 16 bytes per UUID
            let contactCount = UInt(e164sToLookup.count)
            guard plaintext.count == contactCount * 16 else {
                throw ContactDiscoveryError.assertionError(description: "failed check: invalid byte count")
            }
            let dataParser = OWSDataParser(data: plaintext)
            let uuidsData = try dataParser.nextData(length: contactCount * 16, name: "uuids")

            guard dataParser.isEmpty else {
                throw ContactDiscoveryError.assertionError(description: "failed check: dataParse.isEmpty")
            }

            let uuids = type(of: self).uuidArray(from: uuidsData)

            guard uuids.count == contactCount else {
                throw ContactDiscoveryError.assertionError(description: "failed check: uuids.count == contactCount")
            }

            let unregisteredUuid = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

            var registeredContacts: Set<CDSRegisteredContact> = Set()

            for (index, e164PhoneNumber) in e164sToLookup.enumerated() {
                let uuid = uuids[index]
                guard uuid != unregisteredUuid else {
                    Logger.verbose("not a signal user: \(e164PhoneNumber)")
                    continue
                }

                Logger.verbose("Signal user. e164: \(e164PhoneNumber), uuid: \(uuid)")
                registeredContacts.insert(CDSRegisteredContact(signalUuid: uuid,
                                                               e164PhoneNumber: e164PhoneNumber))
            }

            return registeredContacts
        }
    }

    func buildIntersectionQuery(e164sToLookup: [String], remoteAttestations: [RemoteAttestation.CDSAttestation.Id: RemoteAttestation]) throws -> ContactDiscoveryService.IntersectionQuery {
        let noncePlainTextData = Randomness.generateRandomBytes(32)
        let addressPlainTextData = try ContactDiscoveryE164Collection(e164sToLookup).encodedValues
        let queryData = Data.join([noncePlainTextData, addressPlainTextData])

        let key = OWSAES256Key.generateRandom()
        guard let encryptionResult = Cryptography.encryptAESGCM(plainTextData: queryData,
                                                                initializationVectorLength: kAESGCM256_DefaultIVLength,
                                                                additionalAuthenticatedData: nil,
                                                                key: key) else {
                                                                    throw ContactDiscoveryError.assertionError(description: "Encryption failure")
        }
        assert(encryptionResult.ciphertext.count == e164sToLookup.count * 8 + 32)

        let queryEnvelopes: [RemoteAttestation.CDSAttestation.Id: ContactDiscoveryService.IntersectionQuery.EnclaveEnvelope] = try remoteAttestations.mapValues { remoteAttestation in
            guard let perEnclaveKey = Cryptography.encryptAESGCM(plainTextData: key.keyData,
                                                                 initializationVectorLength: kAESGCM256_DefaultIVLength,
                                                                 additionalAuthenticatedData: remoteAttestation.requestId,
                                                                 key: remoteAttestation.keys.clientKey) else {
                                                                    throw ContactDiscoveryError.assertionError(description: "failed to encrypt perEnclaveKey")
            }

            return ContactDiscoveryService.IntersectionQuery.EnclaveEnvelope(requestId: remoteAttestation.requestId,
                                                                             data: perEnclaveKey.ciphertext,
                                                                             iv: perEnclaveKey.initializationVector,
                                                                             mac: perEnclaveKey.authTag)
        }

        guard let commitment = Cryptography.computeSHA256Digest(queryData) else {
            throw ContactDiscoveryError.assertionError(description: "commitment was unexpectedly nil")
        }

        return ContactDiscoveryService.IntersectionQuery(addressCount: UInt(e164sToLookup.count),
                                                         commitment: commitment,
                                                         data: encryptionResult.ciphertext,
                                                         iv: encryptionResult.initializationVector,
                                                         mac: encryptionResult.authTag,
                                                         envelopes: queryEnvelopes)
    }

    class func uuidArray(from data: Data) -> [UUID] {
        return data.withUnsafeBytes {
            [uuid_t]($0.bindMemory(to: uuid_t.self))
                .map { UUID(uuid: $0) }
        }
    }

    /// Parse the error and, if appropriate, construct an error appropriate to return upwards
    /// May return the provided error unchanged.
    class func prepareExternalError(from error: Error) -> Error {
        // Network connectivity failures should never be re-wrapped
        if error.isNetworkConnectivityFailure {
            return error
        }

        let retryAfterDate = error.httpRetryAfterDate

        if let statusCode = error.httpStatusCode {
            switch statusCode {
            case 401:
                return ContactDiscoveryError(
                    kind: .unauthorized,
                    debugDescription: "User is unauthorized",
                    retryable: false,
                    retryAfterDate: retryAfterDate)
            case 404:
                return ContactDiscoveryError(
                    kind: .unexpectedResponse,
                    debugDescription: "Unknown enclaveID",
                    retryable: false,
                    retryAfterDate: retryAfterDate)
            case 408:
                return ContactDiscoveryError(
                    kind: .timeout,
                    debugDescription: "Server rejected due to a timeout",
                    retryable: true,
                    retryAfterDate: retryAfterDate)
            case 409:
                // Conflict on a discovery request indicates that the requestId specified by the client
                // has been dropped due to a delay or high request rate since the preceding corresponding
                // attestation request. The client should not retry the request automatically
                return ContactDiscoveryError(
                    kind: .genericClientError,
                    debugDescription: "RequestID conflict",
                    retryable: false,
                    retryAfterDate: retryAfterDate)
            case 429:
                return ContactDiscoveryError(
                    kind: .rateLimit,
                    debugDescription: "Rate limit",
                    retryable: true,
                    retryAfterDate: retryAfterDate)
            case 400..<500:
                return ContactDiscoveryError(
                    kind: .genericClientError,
                    debugDescription: "Client error (\(statusCode)): \(error.userErrorDescription)",
                    retryable: false,
                    retryAfterDate: retryAfterDate)
            case 500..<600:
                return ContactDiscoveryError(
                    kind: .genericServerError,
                    debugDescription: "Server error (\(statusCode)): \(error.userErrorDescription)",
                    retryable: true,
                    retryAfterDate: retryAfterDate)
            default:
                return ContactDiscoveryError(
                    kind: .generic,
                    debugDescription: "Unknown error (\(statusCode)): \(error.userErrorDescription)",
                    retryable: false,
                    retryAfterDate: retryAfterDate)
            }

        } else {
            return error
        }
    }
}
