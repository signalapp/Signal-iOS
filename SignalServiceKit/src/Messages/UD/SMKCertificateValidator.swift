//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import Curve25519Kit
import SignalCoreKit
import SignalClient

public enum SMKCertificateError: Error {
    case invalidCertificate(description: String)
}

public protocol SMKCertificateValidator {
    func throwswrapped_validate(senderCertificate: SenderCertificate, validationTime: UInt64) throws
    func throwswrapped_validate(serverCertificate: ServerCertificate) throws
}

// See: https://github.com/signalapp/libsignal-metadata-java/blob/master/java/src/main/java/org/signal/libsignal/metadata/certificate/CertificateValidator.java
//public class CertificateValidator {
@objc public class SMKCertificateDefaultValidator: NSObject, SMKCertificateValidator {

//    @SuppressWarnings("MismatchedQueryAndUpdateOfCollection")
//    private static final Set<Integer> REVOKED = new HashSet<Integer>() {{
//
//    }};
    private static let kRevokedCertificateIds = Set<UInt32>()

//    private final ECPublicKey trustRoot;
    private let trustRoot: ECPublicKey

//    public CertificateValidator(ECPublicKey trustRoot) {
//    this.trustRoot = trustRoot;
//    }
    @objc public init(trustRoot: ECPublicKey ) {
        self.trustRoot = trustRoot
    }

//    public void validate(SenderCertificate certificate, long validationTime) throws InvalidCertificateException {
    public func throwswrapped_validate(senderCertificate: SenderCertificate, validationTime: UInt64) throws {
//    try {
//    ServerCertificate serverCertificate = certificate.getSigner();
        let serverCertificate = senderCertificate.serverCertificate

//    validate(serverCertificate);
        try throwswrapped_validate(serverCertificate: serverCertificate)

//    if (!Curve.verifySignature(serverCertificate.getKey(), certificate.getCertificate(), certificate.getSignature())) {
//    throw new InvalidCertificateException("Signature failed");
//    }
        guard try serverCertificate.publicKey.verifySignature(message: senderCertificate.certificateBytes,
                                                              signature: senderCertificate.signatureBytes) else {
            Logger.error("Sender certificate signature verification failed.")
            let error = SMKCertificateError.invalidCertificate(description: "Sender certificate signature verification failed.")
            Logger.error("\(error)")
            throw error
        }

//    if (validationTime > certificate.getExpiration()) {
//    throw new InvalidCertificateException("Certificate is expired");
//    }
        guard validationTime <= senderCertificate.expiration else {
            let error = SMKCertificateError.invalidCertificate(description: "Certficate is expired.")
            Logger.error("\(error)")
            throw error
        }

//    } catch (InvalidKeyException e) {
//    throw new InvalidCertificateException(e);
//    }
    }

    // void validate(ServerCertificate certificate) throws InvalidCertificateException {
    public func throwswrapped_validate(serverCertificate: ServerCertificate) throws {
        // try {
        //   if (!Curve.verifySignature(trustRoot, certificate.getCertificate(), certificate.getSignature())) {
        //   throw new InvalidCertificateException("Signature failed");
        // }
        guard try trustRoot.key.verifySignature(message: serverCertificate.certificateBytes,
                                                signature: serverCertificate.signatureBytes) else {
            let error = SMKCertificateError.invalidCertificate(description: "Server certificate signature verification failed.")
            Logger.error("\(error)")
            throw error
        }

        // if (REVOKED.contains(certificate.getKeyId())) {
        //   throw new InvalidCertificateException("Server certificate has been revoked");
        // }
        guard !SMKCertificateDefaultValidator.kRevokedCertificateIds.contains(serverCertificate.keyId) else {
            let error = SMKCertificateError.invalidCertificate(description: "Revoked certificate.")
            Logger.error("\(error)")
            throw error
        }

        // } catch (InvalidKeyException e) {
        // throw new InvalidCertificateException(e);
        // }
    }
}
