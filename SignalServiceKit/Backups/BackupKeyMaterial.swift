//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

public protocol BackupKeyMaterial {
    var credentialType: BackupAuthCredentialType { get }
    var backupKey: BackupKey { get }

    func serialize() -> Data
    func deriveEcKey(aci: Aci) -> PrivateKey
    func deriveBackupId(aci: Aci) -> Data
}

extension BackupKeyMaterial {
    public func deriveEcKey(aci: Aci) -> PrivateKey {
        backupKey.deriveEcKey(aci: aci)
    }

    public func deriveBackupId(aci: Aci) -> Data {
        backupKey.deriveBackupId(aci: aci)
    }

    public func serialize() -> Data { backupKey.serialize() }
}

public enum BackupKeyMaterialError: Error {
    case missingMessageBackupKey
    case missingOrInvalidMRBK
    /// Encountered an error using libsignal methods to derive keys.
    case derivationError(Error)
}
