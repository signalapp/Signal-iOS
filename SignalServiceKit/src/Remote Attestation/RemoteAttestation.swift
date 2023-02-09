//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public struct RemoteAttestation: Dependencies {
    let cookies: [HTTPCookie]
    let keys: Keys
    let requestId: Data
    let enclaveName: String
    let auth: Auth
}

// MARK: - KBS

public extension RemoteAttestation {
    static func performForKeyBackup(
        auth: Auth?,
        enclave: KeyBackupEnclave
    ) -> Promise<RemoteAttestation> {
        return performAttestation(
            for: .keyBackup,
            auth: auth,
            config: EnclaveConfig(
                enclaveName: enclave.name,
                mrenclave: enclave.mrenclave,
                host: TSConstants.keyBackupURL,
                censorshipCircumventionPrefix: TSConstants.keyBackupCensorshipPrefix
            )
        ).map { attestationResponse -> RemoteAttestation in
            return try parseAttestationResponse(
                params: attestationResponse.responseBody,
                clientEphemeralKeyPair: attestationResponse.clientEphemeralKeyPair,
                cookies: attestationResponse.cookies,
                enclaveName: attestationResponse.enclaveConfig.enclaveName,
                mrenclave: attestationResponse.enclaveConfig.mrenclave,
                auth: attestationResponse.auth
            )
        }
    }
}

// MARK: - CDS

public extension RemoteAttestation {
    struct CDSAttestation {
        /// An opaque, server-specified identifier to link an attestation to its corresponding envelope
        public typealias Id = String

        let cookies: [HTTPCookie]
        let auth: Auth
        let enclaveConfig: EnclaveConfig
        let remoteAttestations: [Id: RemoteAttestation]
    }

    static func performForCDS() -> Promise<CDSAttestation> {
        return performAttestation(
            for: .contactDiscovery,
            config: EnclaveConfig(
                enclaveName: TSConstants.contactDiscoveryEnclaveName,
                mrenclave: TSConstants.contactDiscoveryMrEnclave,
                host: TSConstants.contactDiscoverySGXURL,
                censorshipCircumventionPrefix: TSConstants.contactDiscoveryCensorshipPrefix
            )
        ).map { attestationResponse -> CDSAttestation in
            let attestationBody: [CDSAttestation.Id: [String: Any]] = try attestationResponse.responseBody.required(key: "attestations")

            // The client MUST reject server responses with more than 3 Remote Attestation Responses attached,
            // for security reasons.
            guard (1..<4).contains(attestationBody.count) else {
                throw ParamParser.ParseError.invalidFormat("attestations", description: "invalid attestation count: \(attestationBody.count)")
            }

            let attestations: [CDSAttestation.Id: RemoteAttestation] = try attestationBody.mapValues { attestationParams in
                let parser = ParamParser(dictionary: attestationParams)
                return try parseAttestationResponse(params: parser,
                                            clientEphemeralKeyPair: attestationResponse.clientEphemeralKeyPair,
                                            cookies: attestationResponse.cookies,
                                            enclaveName: attestationResponse.enclaveConfig.enclaveName,
                                            mrenclave: attestationResponse.enclaveConfig.mrenclave,
                                            auth: attestationResponse.auth)
            }

            let attestation = CDSAttestation(cookies: attestationResponse.cookies,
                                             auth: attestationResponse.auth,
                                             enclaveConfig: attestationResponse.enclaveConfig,
                                             remoteAttestations: attestations)
            owsAssertDebug(attestation.auth.username.strippedOrNil != nil)
            owsAssertDebug(attestation.auth.password.strippedOrNil != nil)
            owsAssertDebug(attestation.enclaveConfig.enclaveName.strippedOrNil != nil)
            owsAssertDebug(attestation.enclaveConfig.host.strippedOrNil != nil)
            return attestation
        }
    }
}

// MARK: - CSDI

extension RemoteAttestation {
    static func authForCDSI() -> Promise<Auth> {
        return Auth.fetch(forService: .cdsi)
    }
}

// MARK: - EnclaveConfig

public extension RemoteAttestation {
    struct EnclaveConfig {
        let enclaveName: String
        let mrenclave: MrEnclave
        let host: String
        let censorshipCircumventionPrefix: String
    }
}

// MARK: - Errors

public extension RemoteAttestation {
    enum Error: Swift.Error {
        case assertion(reason: String)
    }
}

private func attestationError(reason: String) -> RemoteAttestation.Error {
    owsFailDebug("Error: \(reason)")
    return .assertion(reason: reason)
}

// MARK: - Auth

public extension RemoteAttestation {
    struct Auth: Dependencies, Equatable, Codable {
        public let username: String
        public let password: String

        public init(authParams: Any) throws {
            guard let authParamsDict = authParams as? [String: Any] else {
                throw attestationError(reason: "Invalid auth response.")
            }

            guard let password = authParamsDict["password"] as? String, !password.isEmpty else {
                throw attestationError(reason: "missing or empty password")
            }

            guard let username = authParamsDict["username"] as? String, !username.isEmpty else {
                throw attestationError(reason: "missing or empty username")
            }

            self.init(username: username, password: password)
        }

        public init(username: String, password: String) {
            self.username = username
            self.password = password
        }
    }
}

fileprivate extension RemoteAttestation.Auth {
    static func fetch(forService service: RemoteAttestation.Service) -> Promise<RemoteAttestation.Auth> {
        guard tsAccountManager.isRegisteredAndReady else {
            return Promise(error: OWSGenericError("Not registered."))
        }

        if DebugFlags.internalLogging {
            Logger.info("service: \(service)")
        }

        let request = service.authRequest()

        return firstly {
            networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            if DebugFlags.internalLogging {
                let statusCode = response.responseStatusCode
                Logger.info("statusCode: \(statusCode)")
                for (header, headerValue) in response.responseHeaders {
                    Logger.info("Header: \(header) -> \(headerValue)")
                }

                #if TESTABLE_BUILD
                 HTTPUtils.logCurl(for: request as URLRequest)
                #endif
            }

            guard let json = response.responseBodyJson else {
                throw attestationError(reason: "Missing or invalid JSON")
            }

            return try RemoteAttestation.Auth(authParams: json)
        }.recover(on: DispatchQueue.global()) { error -> Promise<RemoteAttestation.Auth> in
            let statusCode = error.httpStatusCode ?? 0
            Logger.verbose("Remote attestation auth failure: \(statusCode)")
            throw error
        }
    }
}

// MARK: - Keys

public extension RemoteAttestation {
    struct Keys {
        public let clientEphemeralKeyPair: ECKeyPair
        public let serverEphemeralPublic: Data
        public let serverStaticPublic: Data
        public let clientKey: OWSAES256Key
        public let serverKey: OWSAES256Key

        init(clientEphemeralKeyPair: ECKeyPair, serverEphemeralPublic: Data, serverStaticPublic: Data) throws {
            if serverEphemeralPublic.isEmpty {
                throw attestationError(reason: "Invalid serverEphemeralPublic")
            }
            if serverStaticPublic.isEmpty {
                throw attestationError(reason: "Invalid serverStaticPublic")
            }

            self.clientEphemeralKeyPair = clientEphemeralKeyPair
            self.serverEphemeralPublic = serverEphemeralPublic
            self.serverStaticPublic = serverStaticPublic

            do {
                let clientPrivateKey = clientEphemeralKeyPair.identityKeyPair.privateKey
                let serverEphemeralPublicKey = try ECPublicKey(keyData: serverEphemeralPublic).key
                let serverStaticPublicKey = try ECPublicKey(keyData: serverStaticPublic).key

                let ephemeralToEphemeral = clientPrivateKey.keyAgreement(with: serverEphemeralPublicKey)
                let ephemeralToStatic = clientPrivateKey.keyAgreement(with: serverStaticPublicKey)

                let masterSecret = ephemeralToEphemeral + ephemeralToStatic
                let publicKeys = clientEphemeralKeyPair.publicKey + serverEphemeralPublic + serverStaticPublic

                let derivedMaterial = try hkdf(
                    outputLength: Int(kAES256_KeyByteLength) * 2,
                    inputKeyMaterial: masterSecret,
                    salt: publicKeys,
                    info: []
                )

                let clientKeyData = derivedMaterial[0..<Int(kAES256_KeyByteLength)]
                guard let clientKey = OWSAES256Key(data: Data(clientKeyData)) else {
                    owsFail("failed to create client key")
                }
                self.clientKey = clientKey

                let serverKeyData = derivedMaterial[Int(kAES256_KeyByteLength)...]
                guard let serverKey = OWSAES256Key(data: Data(serverKeyData)) else {
                    owsFail("failed to create server key")
                }
                self.serverKey = serverKey

            } catch {
                owsFailDebug("Error: failed to derive keys - \(error)")
                throw attestationError(reason: "failed to derive keys")
            }
        }
    }
}

// MARK: - Service

fileprivate extension RemoteAttestation {
    enum Service {
        case contactDiscovery
        case keyBackup
        case cdsi

        func authRequest() -> TSRequest {
            switch self {
            case .contactDiscovery: return OWSRequestFactory.remoteAttestationAuthRequestForContactDiscovery()
            case .keyBackup: return OWSRequestFactory.remoteAttestationAuthRequestForKeyBackup()
            case .cdsi: return OWSRequestFactory.remoteAttestationAuthRequestForCDSI()
            }
        }
    }
}

// MARK: - Requests

fileprivate extension RemoteAttestation {
    struct AttestationResponse {
        let responseBody: ParamParser
        let clientEphemeralKeyPair: ECKeyPair
        let cookies: [HTTPCookie]
        let enclaveConfig: EnclaveConfig
        let auth: Auth
    }

    static func performAttestation(
        for service: Service,
        auth: Auth? = nil,
        config: EnclaveConfig
    ) -> Promise<AttestationResponse> {
        firstly(on: DispatchQueue.global()) { () -> Promise<Auth> in
            if let auth = auth {
                return Promise.value(auth)
            } else {
                return Auth.fetch(forService: service)
            }
        }.then(on: DispatchQueue.global()) { (auth: Auth) -> Promise<AttestationResponse> in
            let clientEphemeralKeyPair = Curve25519.generateKeyPair()
            return firstly { () -> Promise<HTTPResponse> in
                let request = remoteAttestationRequest(enclaveName: config.enclaveName,
                                                       authUsername: auth.username,
                                                       authPassword: auth.password,
                                                       service: service,
                                                       clientEphemeralKeyPair: clientEphemeralKeyPair)
                let urlSession = Self.signalService.urlSessionForRemoteAttestation(
                    host: config.host,
                    censorshipCircumventionPrefix: config.censorshipCircumventionPrefix)
                guard let requestUrl = request.url else {
                    owsFailDebug("Missing requestUrl.")
                    throw OWSHTTPError.missingRequest
                }
                return firstly {
                    urlSession.promiseForTSRequest(request)
                }.recover(on: DispatchQueue.global()) { error -> Promise<HTTPResponse> in
                    // OWSUrlSession should only throw OWSHTTPError or OWSAssertionError.
                    if let httpError = error as? OWSHTTPError {
                        throw httpError
                    } else {
                        owsFailDebug("Unexpected error: \(error)")
                        throw OWSHTTPError.invalidRequest(requestUrl: requestUrl)
                    }
                }
            }.map(on: DispatchQueue.global()) { (response: HTTPResponse) in
                guard let json = response.responseBodyJson else {
                    throw attestationError(reason: "Missing or invalid JSON.")
                }
                guard let paramParser = ParamParser(responseObject: json) else {
                    throw attestationError(reason: "paramParser was unexpectedly nil")
                }
                let headerFields = response.responseHeaders
                let responseUrl = response.requestUrl
                let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: responseUrl)

                return AttestationResponse(responseBody: paramParser,
                                           clientEphemeralKeyPair: clientEphemeralKeyPair,
                                           cookies: cookies,
                                           enclaveConfig: config,
                                           auth: auth)
            }
        }
    }

    static func remoteAttestationRequest(enclaveName: String,
                                         authUsername: String,
                                         authPassword: String,
                                         service: Service,
                                         clientEphemeralKeyPair: ECKeyPair) -> TSRequest {

        let path = "v1/attestation/\(enclaveName)"
        var parameters: [String: Any] = [
            "clientPublic": clientEphemeralKeyPair.publicKey.base64EncodedString()
        ]

        // When making requests to CDS, we need to tell the service to use IASv4
        if case .contactDiscovery = service {
            parameters["iasVersion"] = 4
        }

        let request = TSRequest(url: URL(string: path)!,
                                method: "PUT",
                                parameters: parameters)

        request.authUsername = authUsername
        request.authPassword = authPassword

        // OWSURLSession disables default cookie handling for all requests.

        return request
    }

    static func parseAttestationResponse(params: ParamParser,
                                         clientEphemeralKeyPair: ECKeyPair,
                                         cookies: [HTTPCookie],
                                         enclaveName: String,
                                         mrenclave: MrEnclave,
                                         auth: Auth) throws -> RemoteAttestation {
        let serverEphemeralPublic = try params.requiredBase64EncodedData(key: "serverEphemeralPublic", byteCount: 32)
        let serverStaticPublic = try params.requiredBase64EncodedData(key: "serverStaticPublic", byteCount: 32)
        let encryptedRequestId = try params.requiredBase64EncodedData(key: "ciphertext")
        let encryptedRequestIv = try params.requiredBase64EncodedData(key: "iv", byteCount: 12)
        let encryptedRequestTag = try params.requiredBase64EncodedData(key: "tag", byteCount: 16)
        let quoteData = try params.requiredBase64EncodedData(key: "quote")
        let signatureBody: String = try params.required(key: "signatureBody")
        let signature = try params.requiredBase64EncodedData(key: "signature")
        let encodedCertificates: String = try params.required(key: "certificates")
        guard let certificates = encodedCertificates.removingPercentEncoding else {
            throw ParamParser.ParseError.invalidFormat("certificates", description: "invalidly encoded certificates")
        }

        let keys = try Keys(clientEphemeralKeyPair: clientEphemeralKeyPair,
                            serverEphemeralPublic: serverEphemeralPublic,
                            serverStaticPublic: serverStaticPublic)

        let quote = try RemoteAttestationQuote.parseQuote(from: quoteData)

        guard let requestId = Cryptography.decryptAESGCM(withInitializationVector: encryptedRequestIv,
                                                   ciphertext: encryptedRequestId,
                                                   additionalAuthenticatedData: nil,
                                                   authTag: encryptedRequestTag,
                                                   key: keys.serverKey) else {
                                                    throw attestationError(reason: "failed to decrypt requestId")
        }

        try verifyServerQuote(quote, keys: keys, mrenclave: mrenclave)

        try verifyIasSignature(certificates: certificates,
                               signatureBody: signatureBody,
                               signature: signature,
                               quoteData: quoteData)

        Logger.verbose("remote attestation complete")
        return RemoteAttestation(cookies: cookies, keys: keys, requestId: requestId, enclaveName: enclaveName, auth: auth)
    }
}

// MARK: - Signature Verification

fileprivate extension RemoteAttestation {
    static let kQuoteBodyComparisonLength = 432

    static func verifyIasSignature(certificates: String, signatureBody: String, signature: Data, quoteData: Data) throws {
        owsAssertDebug(!certificates.isEmpty)
        owsAssertDebug(!signatureBody.isEmpty)
        owsAssertDebug(!signature.isEmpty)
        owsAssertDebug(!quoteData.isEmpty)

        guard let certificatesData = certificates.data(using: .utf8) else {
            throw attestationError(reason: "certificates isn't utf8.")
        }
        guard let signatureBodyData = signatureBody.data(using: .utf8) else {
            throw attestationError(reason: "signatureBody isn't utf8.")
        }
        guard Ias.verify(signature: signature, of: signatureBodyData, withCertificatesPem: certificatesData, at: Date()) else {
            throw attestationError(reason: "could not verify signature.")
        }

        let signatureBodyEntity = try parseSignatureBodyEntity(signatureBody)

        // NOTE: This version is separate from and does _NOT_ match the quote version.
        guard signatureBodyEntity.hasValidVersion else {
            throw attestationError(reason: "signatureBodyEntity has unexpected version \(signatureBodyEntity.version)")
        }

        // Compare the first N bytes of the quote data with the signed quote body.
        guard signatureBodyEntity.isvEnclaveQuoteBody.count >= kQuoteBodyComparisonLength else {
            throw attestationError(reason: "isvEnclaveQuoteBody has unexpected length.")
        }

        guard quoteData.count >= kQuoteBodyComparisonLength else {
            throw attestationError(reason: "quoteData has unexpected length.")
        }

        let isvEnclaveQuoteBodyForComparison = signatureBodyEntity.isvEnclaveQuoteBody.prefix(kQuoteBodyComparisonLength)
        let quoteDataForComparison = quoteData.prefix(kQuoteBodyComparisonLength)
        guard isvEnclaveQuoteBodyForComparison.ows_constantTimeIsEqual(to: quoteDataForComparison) else {
            throw attestationError(reason: "isvEnclaveQuoteBody and quoteData do not match.")
        }

        guard signatureBodyEntity.hasValidStatus else {
            throw attestationError(reason: "invalid isvEnclaveQuoteStatus: \(signatureBodyEntity.isvEnclaveQuoteStatus)")
        }

        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"

        // Specify parsing locale
        // from: https://developer.apple.com/library/archive/qa/qa1480/_index.html
        // Q:  I'm using NSDateFormatter to parse an Internet-style date, but this fails for some users in some regions.
        // I've set a specific date format string; shouldn't that force NSDateFormatter to work independently of the user's
        // region settings? A: No. While setting a date format string will appear to work for most users, it's not the right
        // solution to this problem. There are many places where format strings behave in unexpected ways. [...]
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        guard let timestampDate = dateFormatter.date(from: signatureBodyEntity.timestamp) else {
            throw attestationError(reason: "Could not parse signature body timestamp: \(signatureBodyEntity.timestamp)")
        }

        // Only accept signatures from the last 24 hours.
        let timestampDatePlus1Day = timestampDate.addingTimeInterval(kDayInterval)
        if Date().isAfter(timestampDatePlus1Day) {
            if DebugFlags.internalLogging {
                Logger.info("signatureBody: \(signatureBody)")
                Logger.info("signature: \(signature)")
            }
            if TSConstants.isUsingProductionService {
                throw attestationError(reason: "Signature is expired: \(signatureBodyEntity.timestamp)")
            }
        }
    }

    struct SignatureBodyEntity: Codable {
        let timestamp: String
        let isvEnclaveQuoteBody: Data
        let isvEnclaveQuoteStatus: String
        let version: Int
        let advisoryURL: String?
        let advisoryIDs: Set<String>?

        private static let allowedAdvisoryIDs = ["INTEL-SA-00334", "INTEL-SA-00615"]

        var hasValidStatus: Bool {
            switch isvEnclaveQuoteStatus {
            case "OK": return true
            case "SW_HARDENING_NEEDED": return (advisoryIDs ?? Set()).isSubset(of: Self.allowedAdvisoryIDs)
            default: return false
            }
        }

        var hasValidVersion: Bool { version == 4 }
    }

    static func parseSignatureBodyEntity(_ signatureBodyEntity: String) throws -> SignatureBodyEntity {
        owsAssertDebug(!signatureBodyEntity.isEmpty)

        guard let signatureBodyData = signatureBodyEntity.data(using: .utf8) else {
            throw attestationError(reason: "Invalid signature body entity.")
        }

        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .base64
        do {
            return try decoder.decode(SignatureBodyEntity.self, from: signatureBodyData)
        } catch {
            throw attestationError(reason: "could not parse signature body: \(error)")
        }
    }
}

// MARK: - Quote Verification

fileprivate extension RemoteAttestation {
    static func verifyServerQuote(_ quote: RemoteAttestationQuote, keys: Keys, mrenclave: MrEnclave) throws {
        let theirServerPublicStatic = quote.reportData.prefix(keys.serverStaticPublic.count)
        guard theirServerPublicStatic.count == keys.serverStaticPublic.count else {
            throw attestationError(reason: "reportData has unexpected length: \(quote.reportData.count)")
        }

        guard keys.serverStaticPublic.ows_constantTimeIsEqual(to: theirServerPublicStatic) else {
            throw attestationError(reason: "server public statics do not match.")
        }

        let ourMrEnclaveData = mrenclave.dataValue
        guard ourMrEnclaveData.ows_constantTimeIsEqual(to: quote.mrenclave) else {
            throw attestationError(reason: "mrenclave does not match.")
        }

        guard !quote.isDebugQuote() else {
            throw attestationError(reason: "quote has invalid isDebugQuote value.")
        }
    }
}
