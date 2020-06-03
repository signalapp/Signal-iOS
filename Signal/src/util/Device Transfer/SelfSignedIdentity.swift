//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import CommonCrypto
import openssl

struct SelfSignedIdentity {
    private static let temporaryIdentityKeychainIdentifier = "org.signal.temporaryIdentityKeychainIdentifier"

    static func create(name: String, validForDays: Int) throws -> SecIdentity {
        let (certifcate, key) = try createSelfSignedCertificate(name: name, validForDays: validForDays)

        // If there's an existing identity by this name in the keychain,
        // delete it. There should only be one.
        try deleteSelfSignedIdentityFromKeychain()

        // Add the certificate to the keychain
        do {
            let addquery: [CFString: Any] = [
                kSecClass: kSecClassCertificate,
                kSecValueRef: certifcate,
                kSecAttrLabel: temporaryIdentityKeychainIdentifier
            ]
            guard SecItemAdd(addquery as CFDictionary, nil) == errSecSuccess else {
                throw OWSAssertionError("failed to add certificate to keychain")
            }
        }

        // Add the private key to the keychain
        do {
            let addquery: [CFString: Any] = [
                kSecClass: kSecClassKey,
                kSecAttrKeyClass: kSecAttrKeyClassPrivate,
                kSecValueRef: key,
                kSecAttrLabel: temporaryIdentityKeychainIdentifier
            ]
            guard SecItemAdd(addquery as CFDictionary, nil) == errSecSuccess else {
                throw OWSAssertionError("failed to add private key to keychain")
            }
        }

        // Fetch the composed identity from the keychain
        let identity: SecIdentity = try {
            let copyQuery: [CFString: Any] = [
                kSecClass: kSecClassIdentity,
                kSecReturnRef: true,
                kSecAttrLabel: temporaryIdentityKeychainIdentifier
            ]

            var typeRef: CFTypeRef?
            guard SecItemCopyMatching(copyQuery as CFDictionary, &typeRef) == errSecSuccess else {
                throw OWSAssertionError("failed to fetch identity from keychain")
            }

            return (typeRef as! SecIdentity)
        }()

        // We don't actually want to persist the identity, but it needs to go
        // through the keychain in order to create it. We can delete it once
        // we've got the ref.
        try deleteSelfSignedIdentityFromKeychain()

        return identity
    }

    private static func deleteSelfSignedIdentityFromKeychain() throws {
        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecAttrLabel: temporaryIdentityKeychainIdentifier
        ]
        let status = SecItemDelete(deleteQuery as CFDictionary)
        guard [errSecSuccess, errSecItemNotFound].contains(status) else {
            throw OWSAssertionError("failed to delete existing identity")
        }
    }

    private static func createSelfSignedCertificate(name: String, validForDays days: Int = 365) throws -> (SecCertificate, SecKey) {
        guard let x509 = X509_new() else {
            throw OWSAssertionError("failed to allocate a new X509")
        }

        // Keys

        guard let pkey = EVP_PKEY_new() else {
            throw OWSAssertionError("failed to allocate a new EVP_PKEY")
        }

        guard let rsa = RSA_generate_key(4096, UInt(RSA_F4), nil, nil) else {
            throw OWSAssertionError("failed to generate RSA keypair")
        }

        guard EVP_PKEY_assign(pkey, EVP_PKEY_RSA, rsa) > 0 else {
            throw OWSAssertionError("failed to assign RSA keypair into EVP_PKEY")
        }

        guard X509_set_pubkey(x509, pkey) > 0 else {
            throw OWSAssertionError("failed to set X509 pubkey")
        }

        // Version

        guard X509_set_version(x509, 2) > 0 else {
            throw OWSAssertionError("failed to set X509 version")
        }

        // Serial Number

        guard let serialNumber = ASN1_INTEGER_new() else {
            throw OWSAssertionError("failed to allocate a new ASN1_INTEGER")
        }

        guard generateRandomSerial(serialNumber) > 0 else {
            throw OWSAssertionError("failed to create random serial")
        }

        guard X509_set_serialNumber(x509, serialNumber) > 0 else {
            throw OWSAssertionError("failed to set X509 serialNumber")
        }

        // Expiration

        guard X509_gmtime_adj(x509.pointee.cert_info.pointee.validity.pointee.notBefore, 0) != nil else {
            throw OWSAssertionError("failed to set X509 not before")
        }
        guard X509_gmtime_adj(x509.pointee.cert_info.pointee.validity.pointee.notAfter, Int(kDayInterval) * days) != nil else {
            throw OWSAssertionError("failed to set X509 not after")
        }

        // Subject & Issuer

        guard let issuerName = X509_get_subject_name(x509) else {
            throw OWSAssertionError("failed to get X509 subject")
        }

        guard X509_NAME_add_entry_by_txt(issuerName, "C", MBSTRING_ASC, "US", -1, -1, 0) > 0 else {
            throw OWSAssertionError("failed to set X509 country")
        }

        guard X509_NAME_add_entry_by_txt(issuerName, "ST", MBSTRING_ASC, "California", -1, -1, 0) > 0 else {
            throw OWSAssertionError("failed to set X509 state")
        }

        guard X509_NAME_add_entry_by_txt(issuerName, "L", MBSTRING_ASC, "San Francisco", -1, -1, 0) > 0 else {
            throw OWSAssertionError("failed to set X509 location")
        }

        guard X509_NAME_add_entry_by_txt(issuerName, "O", MBSTRING_ASC, "Signal Foundation", -1, -1, 0) > 0 else {
            throw OWSAssertionError("failed to set X509 organizattion")
        }

        guard X509_NAME_add_entry_by_txt(issuerName, "CN", MBSTRING_ASC, name, -1, -1, 0) > 0 else {
            throw OWSAssertionError("failed to set X509 common name")
        }

        // It's self signed so set the issuer name to be the same as the subject.
        guard X509_set_issuer_name(x509, issuerName) > 0 else {
            throw OWSAssertionError("failed to set X509 issuer")
        }

        // Sign

        guard X509_sign(x509, pkey, EVP_sha256()) > 0 else {
            throw OWSAssertionError("Failed to sign certificate")
        }

        // Convert to Security refs

        let certificate: SecCertificate = try {
            var optionalBytes: UnsafeMutablePointer<UInt8>?
            let byteCount = i2d_X509(x509, &optionalBytes)
            guard byteCount > 0, let bytes = optionalBytes else {
                throw OWSAssertionError("Failed to get certificate DER data")
            }

            let data = Data(bytes: bytes, count: Int(byteCount))

            guard let certificate = SecCertificateCreateWithData(nil, data as CFData) else {
                throw OWSAssertionError("Failed to initialize SecCertificate")
            }

            return certificate
        }()

        let privateKey: SecKey = try {
            var optionalBytes: UnsafeMutablePointer<UInt8>?
            let byteCount = i2d_PrivateKey(pkey, &optionalBytes)
            guard byteCount > 0, let bytes = optionalBytes else {
                throw OWSAssertionError("Failed to get private key DER data")
            }

            let data = Data(bytes: bytes, count: Int(byteCount))

            guard let privateKey = SecKeyCreateWithData(
                data as CFData,
                [
                    kSecAttrKeyType: kSecAttrKeyTypeRSA,
                    kSecAttrKeyClass: kSecAttrKeyClassPrivate,
                    kSecAttrKeySizeInBits: 4096
                ] as CFDictionary,
                nil
            ) else {
                throw OWSAssertionError("Failed to intiialize SecKey")
            }

            return privateKey
        }()

        return (certificate, privateKey)
    }

    private static func generateRandomSerial(_ ai: UnsafeMutablePointer<ASN1_INTEGER>) -> Int {
        guard let bn = BN_new() else { return -1 }

        defer { BN_free(bn) }

        guard BN_pseudo_rand(bn, 64, 0, 0) > 0 else { return -1 }

        guard BN_to_ASN1_INTEGER(bn, ai) != nil else { return -1 }

        return 1
    }
}

extension SecIdentity {
    func computeCertificateHash() throws -> Data {
        var optionalCertificate: SecCertificate?
        guard SecIdentityCopyCertificate(self, &optionalCertificate) == errSecSuccess, let certificate = optionalCertificate else {
            throw OWSAssertionError("failed to copy certificate from identity")
        }

        let certificateData = SecCertificateCopyData(certificate) as Data

        guard let hash = Cryptography.computeSHA256Digest(certificateData) else {
            throw OWSAssertionError("failed to compute certificate hash")
        }

        return hash
    }
}
