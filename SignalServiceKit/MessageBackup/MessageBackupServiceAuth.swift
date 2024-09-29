//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct MessageBackupServiceAuth {
    private let authHeaders: [String: String]
    public let publicKey: PublicKey

    public init(backupKey: Data, privateKey: PrivateKey, authCredential: BackupAuthCredential) throws {
        let backupServerPublicParams = try GenericServerPublicParams(contents: [UInt8](TSConstants.backupServerPublicParams))
        let presentation = authCredential.present(serverParams: backupServerPublicParams).serialize()
        let signedPresentation = privateKey.generateSignature(message: presentation)

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
