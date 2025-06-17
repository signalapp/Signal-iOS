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

    public init(backupKey: Data, privateKey: PrivateKey, authCredential: BackupAuthCredential, type: BackupAuthCredentialType) throws {
        let backupServerPublicParams = try GenericServerPublicParams(contents: TSConstants.backupServerPublicParams)
        let presentation = authCredential.present(serverParams: backupServerPublicParams).serialize()
        let signedPresentation = privateKey.generateSignature(message: presentation)
        self.type = type
        self.backupLevel = authCredential.backupLevel

        self.publicKey = privateKey.publicKey
        self.authHeaders = [
            "X-Signal-ZK-Auth": presentation.base64EncodedString(),
            "X-Signal-ZK-Auth-Signature": signedPresentation.base64EncodedString()
        ]
    }

    public func apply(to httpHeaders: inout HttpHeaders) {
        for (headerKey, headerValue) in authHeaders {
            httpHeaders.addHeader(headerKey, value: headerValue, overwriteOnConflict: true)
        }
    }
}
