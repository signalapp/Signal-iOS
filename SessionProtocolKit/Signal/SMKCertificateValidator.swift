//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

public enum SMKCertificateError: Error {
    case invalidCertificate(description: String)
}

@objc public protocol SMKCertificateValidator: class {

    @objc func throwswrapped_validate(senderCertificate: SMKSenderCertificate, validationTime: UInt64) throws

    @objc func throwswrapped_validate(serverCertificate: SMKServerCertificate) throws
}

// See: https://github.com/signalapp/libsignal-metadata-java/blob/master/java/src/main/java/org/signal/libsignal/metadata/certificate/CertificateValidator.java
//public class CertificateValidator {
@objc public class SMKCertificateDefaultValidator: NSObject, SMKCertificateValidator {

//    @SuppressWarnings("MismatchedQueryAndUpdateOfCollection")
//    private static final Set<Integer> REVOKED = new HashSet<Integer>() {{
//
//    }};
    private static let kRevokedCertificateIds = Set<UInt32>()

//
//    private final ECPublicKey trustRoot;
    private let trustRoot: ECPublicKey

//    public CertificateValidator(ECPublicKey trustRoot) {
//    this.trustRoot = trustRoot;
//    }
    @objc public init(trustRoot: ECPublicKey ) {
        self.trustRoot = trustRoot
    }

//    public void validate(SenderCertificate certificate, long validationTime) throws InvalidCertificateException {
    @objc public func throwswrapped_validate(senderCertificate: SMKSenderCertificate, validationTime: UInt64) throws {
//    try {
//    ServerCertificate serverCertificate = certificate.getSigner();
//        let serverCertificate = senderCertificate.signer

//    validate(serverCertificate);
//        try throwswrapped_validate(serverCertificate: serverCertificate)

//    if (!Curve.verifySignature(serverCertificate.getKey(), certificate.getCertificate(), certificate.getSignature())) {
//    throw new InvalidCertificateException("Signature failed");
//    }
//        let certificateData = try senderCertificate.toProto().certificate
//        guard try Ed25519.verifySignature(senderCertificate.signatureData,
//                                          publicKey: serverCertificate.key.keyData,
//                                          data: certificateData) else {
//            Logger.error("Sender certificate signature verification failed.")
//            let error = SMKCertificateError.invalidCertificate(description: "Sender certificate signature verification failed.")
//            Logger.error("\(error)")
//            throw error
//        }

//    if (validationTime > certificate.getExpiration()) {
//    throw new InvalidCertificateException("Certificate is expired");
//    }
//        guard validationTime <= senderCertificate.expirationTimestamp else {
//            let error = SMKCertificateError.invalidCertificate(description: "Certficate is expired.")
//            Logger.error("\(error)")
//            throw error
//        }

//    } catch (InvalidKeyException e) {
//    throw new InvalidCertificateException(e);
//    }
    }

//    // VisibleForTesting
//    void validate(ServerCertificate certificate) throws InvalidCertificateException {
    @objc public func throwswrapped_validate(serverCertificate: SMKServerCertificate) throws {
//    try {
//    if (!Curve.verifySignature(trustRoot, certificate.getCertificate(), certificate.getSignature())) {
//    throw new InvalidCertificateException("Signature failed");
//    }
        let certificateBuilder = SMKProtoServerCertificateCertificate.builder(id: serverCertificate.keyId,
                                                                              key: serverCertificate.key.serialized)
        let certificateData = try certificateBuilder.build().serializedData()

//            let certificateData = try serverCertificate.toProto().certificate
        guard try Ed25519.verifySignature(serverCertificate.signatureData,
                                          publicKey: trustRoot.keyData,
                                          data: certificateData) else {
                                            let error = SMKCertificateError.invalidCertificate(description: "Server certificate signature verification failed.")
                                            Logger.error("\(error)")
                                            throw error
        }
//    if (REVOKED.contains(certificate.getKeyId())) {
//    throw new InvalidCertificateException("Server certificate has been revoked");
//    }
        guard !SMKCertificateDefaultValidator.kRevokedCertificateIds.contains(serverCertificate.keyId) else {
            let error = SMKCertificateError.invalidCertificate(description: "Revoked certificate.")
            Logger.error("\(error)")
            throw error
        }
//    } catch (InvalidKeyException e) {
//    throw new InvalidCertificateException(e);
//    }
    }
}
