//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

// There's no easy way to instantiate a LibSignalClient.BackupAuth
// for testing, so instead wrap the type in a private protocol/wrapper
// that _can_ be mocked in the test. Not that if we ever need to pass
// a BackupAuth back to a caller, this wrapper will have to be made
// public (and probably renamed).
private protocol BackupAuthProvider {
    var backupAuth: BackupAuth { get }
}

private struct BackupAuthWrapper: BackupAuthProvider {
    let backupAuth: BackupAuth
    init(_ backupAuth: BackupAuth) {
        self.backupAuth = backupAuth
    }
}

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

    public var backupAuth: BackupAuth { _backupAuth.backupAuth }
    private var _backupAuth: BackupAuthProvider

    public init(
        privateKey: PrivateKey,
        authCredential: BackupAuthCredential,
        type: BackupAuthCredentialType,
    ) {
        let backupServerPublicParams = TSConstants.backupServerPublicParams()
        let presentation = authCredential.present(serverParams: backupServerPublicParams).serialize()
        let signedPresentation = privateKey.generateSignature(message: presentation)

        let backupAuth = BackupAuth(
            credential: authCredential,
            serverKeys: backupServerPublicParams,
            signingKey: privateKey,
        )
        self.init(
            authHeaders: [
                "X-Signal-ZK-Auth": presentation.base64EncodedString(),
                "X-Signal-ZK-Auth-Signature": signedPresentation.base64EncodedString(),
            ],
            publicKey: privateKey.publicKey,
            type: type,
            backupLevel: authCredential.backupLevel,
            backupAuthProvider: BackupAuthWrapper(backupAuth),
        )
    }

    private init(
        authHeaders: [String: String],
        publicKey: PublicKey,
        type: BackupAuthCredentialType,
        backupLevel: BackupLevel,
        backupAuthProvider: any BackupAuthProvider,
    ) {
        self.authHeaders = authHeaders
        self.publicKey = publicKey
        self.type = type
        self.backupLevel = backupLevel
        self._backupAuth = backupAuthProvider
    }

    public func apply(to httpHeaders: inout HttpHeaders) {
        for (headerKey, headerValue) in authHeaders {
            httpHeaders.addHeader(headerKey, value: headerValue, overwriteOnConflict: true)
        }
    }

#if TESTABLE_BUILD

    private struct MockBackupAuthWrapper: BackupAuthProvider {
        var backupAuth: LibSignalClient.BackupAuth { fatalError("NotImplemented") }
    }

    static func mock(
        type: BackupAuthCredentialType = .messages,
        backupLevel: BackupLevel = .free,
    ) -> Self {
        return .init(
            authHeaders: [:],
            publicKey: PrivateKey.generate().publicKey,
            type: type,
            backupLevel: backupLevel,
            backupAuthProvider: MockBackupAuthWrapper(),
        )
    }

#endif
}
