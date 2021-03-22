//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalClient

extension RemoteAttestation {

    struct EnclaveConfig {
        let enclaveName: String
        let mrenclave: String
        let host: String
        let censorshipCircumventionPrefix: String
    }

    // MARK: -

    public static func performForKeyBackup(
        auth: RemoteAttestationAuth?,
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
            return try parseAttestation(params: attestationResponse.responseBody,
                                        clientEphemeralKeyPair: attestationResponse.clientEphemeralKeyPair,
                                        cookies: attestationResponse.cookies,
                                        enclaveName: attestationResponse.enclaveConfig.enclaveName,
                                        mrenclave: attestationResponse.enclaveConfig.mrenclave,
                                        auth: attestationResponse.auth)
        }
    }

    public struct CDSAttestation {
        /// An opaque, server-specified identifier to link an attestation to its corresponding envelope
        public typealias Id = String

        let cookies: [HTTPCookie]
        let auth: RemoteAttestationAuth
        let enclaveConfig: EnclaveConfig
        let remoteAttestations: [Id: RemoteAttestation]
    }

    public static func performForCDS() -> Promise<CDSAttestation> {
        return performAttestation(
            for: .contactDiscovery,
            config: EnclaveConfig(
                enclaveName: TSConstants.contactDiscoveryEnclaveName,
                mrenclave: TSConstants.contactDiscoveryMrEnclave,
                host: TSConstants.contactDiscoveryURL,
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
                return try parseAttestation(params: parser,
                                            clientEphemeralKeyPair: attestationResponse.clientEphemeralKeyPair,
                                            cookies: attestationResponse.cookies,
                                            enclaveName: attestationResponse.enclaveConfig.enclaveName,
                                            mrenclave: attestationResponse.enclaveConfig.mrenclave,
                                            auth: attestationResponse.auth)
            }

            return CDSAttestation(cookies: attestationResponse.cookies,
                                  auth: attestationResponse.auth,
                                  enclaveConfig: attestationResponse.enclaveConfig,
                                  remoteAttestations: attestations)
        }
    }

    // MARK: -

    private static func getAuth(for service: RemoteAttestationService) -> Promise<RemoteAttestationAuth> {
        return Promise { resolver in
            self.getAuthFor(service, success: resolver.fulfill, failure: resolver.reject)
        }
    }

    private struct AttestationResponse {
        let responseBody: ParamParser
        let clientEphemeralKeyPair: ECKeyPair
        let cookies: [HTTPCookie]
        let enclaveConfig: EnclaveConfig
        let auth: RemoteAttestationAuth
    }

    private static func performAttestation(
        for service: RemoteAttestationService,
        auth: RemoteAttestationAuth? = nil,
        config: EnclaveConfig
    ) -> Promise<AttestationResponse> {
        firstly(on: .global()) { () -> Promise<RemoteAttestationAuth> in
            if let auth = auth {
                return Promise.value(auth)
            } else {
                return getAuth(for: service)
            }
        }.then(on: .global()) { auth -> Promise<AttestationResponse> in
            let clientEphemeralKeyPair = Curve25519.generateKeyPair()

            let request = remoteAttestationRequest(enclaveName: config.enclaveName,
                                                   host: config.host,
                                                   censorshipCircumventionPrefix: config.censorshipCircumventionPrefix,
                                                   authUsername: auth.username,
                                                   authPassword: auth.password,
                                                   clientEphemeralKeyPair: clientEphemeralKeyPair)

            return self.networkManager.makePromise(request: request).map { task, body in
                guard let paramParser = ParamParser(responseObject: body) else {
                    throw OWSAssertionError("paramParser was unexpectedly nil")
                }
                guard let response = task.response as? HTTPURLResponse else {
                    throw OWSAssertionError("task.response was unexpectedly nil")
                }
                guard let headerFields = response.allHeaderFields as? [String: String] else {
                    throw OWSAssertionError("invalid response.allHeaderFields: \(response.allHeaderFields)")
                }
                guard let responseUrl = response.url else {
                    throw OWSAssertionError("responseUrl was unexpectedly nil")
                }
                let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: responseUrl)

                return AttestationResponse(responseBody: paramParser,
                                           clientEphemeralKeyPair: clientEphemeralKeyPair,
                                           cookies: cookies,
                                           enclaveConfig: config,
                                           auth: auth)
            }
        }
    }

    private static func remoteAttestationRequest(enclaveName: String,
                                                 host: String,
                                                 censorshipCircumventionPrefix: String,
                                                 authUsername: String,
                                                 authPassword: String,
                                                 clientEphemeralKeyPair: ECKeyPair) -> TSRequest {

        let path = "v1/attestation/\(enclaveName)"
        let request = TSRequest(url: URL(string: path)!,
                                method: "PUT",
                                parameters: [
                                    "clientPublic": clientEphemeralKeyPair.publicKey.base64EncodedString()
        ])

        request.authUsername = authUsername
        request.authPassword = authPassword
        request.customHost = host
        request.customCensorshipCircumventionPrefix = censorshipCircumventionPrefix

        // Don't bother with the default cookie store;
        // these cookies are ephemeral.
        //
        // NOTE: TSNetworkManager now separately disables default cookie handling for all requests.
        request.httpShouldHandleCookies = false

        return request
    }

    private static func parseAttestation(params: ParamParser,
                                         clientEphemeralKeyPair: ECKeyPair,
                                         cookies: [HTTPCookie],
                                         enclaveName: String,
                                         mrenclave: String,
                                         auth: RemoteAttestationAuth) throws -> RemoteAttestation {
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

        let keys = try RemoteAttestationKeys(clientEphemeralKeyPair: clientEphemeralKeyPair,
                                             serverEphemeralPublic: serverEphemeralPublic,
                                             serverStaticPublic: serverStaticPublic)

        let quote = try RemoteAttestationQuote.parseQuote(from: quoteData)

        guard let requestId = Cryptography.decryptAESGCM(withInitializationVector: encryptedRequestIv,
                                                   ciphertext: encryptedRequestId,
                                                   additionalAuthenticatedData: nil,
                                                   authTag: encryptedRequestTag,
                                                   key: keys.serverKey) else {
                                                    throw OWSAssertionError("failed to decrypt requestId")
        }

        guard verifyServerQuote(quote, keys: keys, mrenclave: mrenclave) else {
            throw OWSAssertionError("could not verify quote")
        }

        try verifyIasSignature(withCertificates: certificates,
                               signatureBody: signatureBody,
                               signature: signature,
                               quoteData: quoteData)

        Logger.verbose("remote attestation complete")
        return RemoteAttestation(cookies: cookies, keys: keys, requestId: requestId, enclaveName: enclaveName, auth: auth)
    }
}

extension RemoteAttestationError {
    public var reason: String? {
        return userInfo[RemoteAttestationErrorKey_Reason] as? String
    }

    fileprivate init(_ code: Code, reason: String) {
        owsFailDebug("Error: \(reason)")
        self.init(code, userInfo: [RemoteAttestationErrorKey_Reason: reason])
    }
}

@objc
public class RemoteAttestationKeys: NSObject {
    @objc
    public let clientEphemeralKeyPair: ECKeyPair

    @objc
    public let serverEphemeralPublic: Data

    @objc
    public let serverStaticPublic: Data

    @objc
    public let clientKey: OWSAES256Key

    @objc
    public let serverKey: OWSAES256Key

    @objc
    public init(clientEphemeralKeyPair: ECKeyPair, serverEphemeralPublic: Data, serverStaticPublic: Data) throws {
        if serverEphemeralPublic.isEmpty {
            throw RemoteAttestationError(.assertionError, reason: "Invalid serverEphemeralPublic")
        }
        if serverStaticPublic.isEmpty {
            throw RemoteAttestationError(.assertionError, reason: "Invalid serverStaticPublic")
        }

        self.clientEphemeralKeyPair = clientEphemeralKeyPair
        self.serverEphemeralPublic = serverEphemeralPublic
        self.serverStaticPublic = serverStaticPublic

        do {
            let clientPrivateKey = clientEphemeralKeyPair.identityKeyPair.privateKey
            let serverEphemeralPublicKey = try! ECPublicKey(keyData: serverEphemeralPublic).key
            let serverStaticPublicKey = try! ECPublicKey(keyData: serverStaticPublic).key

            let ephemeralToEphemeral = clientPrivateKey.keyAgreement(with: serverEphemeralPublicKey)
            let ephemeralToStatic = clientPrivateKey.keyAgreement(with: serverStaticPublicKey)

            let masterSecret = ephemeralToEphemeral + ephemeralToStatic
            let publicKeys = clientEphemeralKeyPair.publicKey + serverEphemeralPublic + serverStaticPublic

            let derivedMaterial = try hkdf(
                outputLength: Int(kAES256_KeyByteLength) * 2,
                version: 3,
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
            throw RemoteAttestationError(.assertionError, userInfo: [
                RemoteAttestationErrorKey_Reason: "failed to derive keys",
                NSUnderlyingErrorKey: error
            ])
        }
    }
}
