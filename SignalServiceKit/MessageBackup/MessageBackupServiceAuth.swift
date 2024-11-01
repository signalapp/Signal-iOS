//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct MessageBackupServiceAuth {
    private let authHeaders: [String: String]
    public let publicKey: PublicKey

    // Remember the type of auth this credential represents (message vs media).
    // This makes it easier to cache requested information correctly based on the type
    public let type: MessageBackupAuthCredentialType

    public init(backupKey: Data, privateKey: PrivateKey, authCredential: BackupAuthCredential, type: MessageBackupAuthCredentialType) throws {
        let backupServerPublicParams = try GenericServerPublicParams(contents: [UInt8](TSConstants.backupServerPublicParams))
        let presentation = authCredential.present(serverParams: backupServerPublicParams).serialize()
        let signedPresentation = privateKey.generateSignature(message: presentation)
        self.type = type

        self.publicKey = privateKey.publicKey
        self.authHeaders = [
            "X-Signal-ZK-Auth": Data(presentation).base64EncodedString(),
            "X-Signal-ZK-Auth-Signature": Data(signedPresentation).base64EncodedString()
        ]
    }

    public func apply(to request: TSRequest) {
        for header in authHeaders {
            request.addValue(header.1, forHTTPHeaderField: header.0)
        }
    }
}
