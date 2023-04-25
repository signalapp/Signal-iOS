//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

struct SelfSignedIdentity {
    private static let temporaryIdentityKeychainIdentifier = "org.signal.temporaryIdentityKeychainIdentifier"

    static func create(name: String, validForDays: Int) throws -> SecIdentity {
        let (certificate, key) = try createSelfSignedCertificate(name: name, validForDays: validForDays)

        // If there's an existing identity by this name in the keychain,
        // delete it. There should only be one.
        try deleteSelfSignedIdentityFromKeychain()

        // Add the certificate to the keychain
        do {
            let addquery: [CFString: Any] = [
                kSecClass: kSecClassCertificate,
                kSecValueRef: certificate,
                kSecAttrLabel: temporaryIdentityKeychainIdentifier
            ]
            guard SecItemAdd(addquery as  CFDictionary, nil) == errSecSuccess else {
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
        let deviceTransferKey = DeviceTransferKey.generate(formattedAs: .keySpecific)
        let certificateData = deviceTransferKey.generateCertificate(name, days)

        // Convert to Security refs

        guard let certificate = SecCertificateCreateWithData(nil, Data(certificateData) as CFData) else {
            throw OWSAssertionError("Failed to initialize SecCertificate")
        }

        let keyData = Data(deviceTransferKey.privateKey)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 4096
        ]

        guard let privateKey = SecKeyCreateWithData(
            keyData as CFData,
            attributes as CFDictionary,
            nil
        ) else {
            throw OWSAssertionError("Failed to initialize SecKey")
        }

        return (certificate, privateKey)
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
