//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum MessageBackupKeyMaterialError: Error {
    case missingMasterKey
    case missingMediaRootBackupKey
    /// Encountered an error using libsignal methods to derive keys.
    case derivationError(Error)
}

public enum MediaTierEncryptionType: CaseIterable {
    case attachment
    case thumbnail
}

public struct MediaTierEncryptionMetadata: Equatable {
    let type: MediaTierEncryptionType
    let mediaId: Data
    let hmacKey: Data
    let aesKey: Data

    public var encryptionKey: Data {
        return aesKey + hmacKey
    }
}

extension BackupKey {
    public func asMessageBackupKey(for aci: Aci) throws -> MessageBackupKey {
        try MessageBackupKey(backupKey: self, backupId: self.deriveBackupId(aci: aci))
    }
}

public protocol MessageBackupKeyMaterial {
    func backupKey(
        type: MessageBackupAuthCredentialType,
        tx: DBReadTransaction
    ) throws(MessageBackupKeyMaterialError) -> BackupKey

    func mediaEncryptionMetadata(
        mediaName: String,
        type: MediaTierEncryptionType,
        tx: any DBReadTransaction
    ) throws(MessageBackupKeyMaterialError) -> MediaTierEncryptionMetadata
}
