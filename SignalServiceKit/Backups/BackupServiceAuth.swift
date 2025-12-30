//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct BackupServiceAuth {
    private let authHeaders: [String: String]
    public let publicKey: PublicKey

    // Remember the type of auth this credential represents (message vs media).
    // This makes it easier to cache requested information correctly based on the type
    public let type: BackupAuthCredentialType
    // Remember the level this credential represents (free vs paid).
    // This makes it easier for callers to tell what permissions are available,
    // as long as the credential remains valid.
    public let backupLevel: BackupLevel

    public init(
        privateKey: PrivateKey,
        authCredential: BackupAuthCredential,
        type: BackupAuthCredentialType,
    ) {
        let backupServerPublicParams = try! GenericServerPublicParams(contents: TSConstants.backupServerPublicParams)
        let presentation = authCredential.present(serverParams: backupServerPublicParams).serialize()
        let signedPresentation = privateKey.generateSignature(message: presentation)

        self.init(
            authHeaders: [
                "X-Signal-ZK-Auth": presentation.base64EncodedString(),
                "X-Signal-ZK-Auth-Signature": signedPresentation.base64EncodedString(),
            ],
            publicKey: privateKey.publicKey,
            type: type,
            backupLevel: authCredential.backupLevel,
        )
    }

    private init(
        authHeaders: [String: String],
        publicKey: PublicKey,
        type: BackupAuthCredentialType,
        backupLevel: BackupLevel,
    ) {
        self.authHeaders = authHeaders
        self.publicKey = publicKey
        self.type = type
        self.backupLevel = backupLevel
    }

    public func apply(to httpHeaders: inout HttpHeaders) {
        for (headerKey, headerValue) in authHeaders {
            httpHeaders.addHeader(headerKey, value: headerValue, overwriteOnConflict: true)
        }
    }

#if TESTABLE_BUILD

    static func mock(
        type: BackupAuthCredentialType = .messages,
        backupLevel: BackupLevel = .free,
    ) -> Self {
        return .init(
            authHeaders: [:],
            publicKey: PrivateKey.generate().publicKey,
            type: type,
            backupLevel: backupLevel,
        )
    }

#endif
}
