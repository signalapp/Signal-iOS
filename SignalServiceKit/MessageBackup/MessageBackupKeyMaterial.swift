//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

enum MessageBackupKeyMaterialError: Error {
    case invalidKeyInfo
    case missingMasterKey
    case notRegistered
    case invalidEncryptionKey
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
    let iv: Data

    public var encryptionKey: Data {
        return aesKey + hmacKey
    }
}

public protocol MessageBackupKeyMaterial {

    /// Backup ID material derived from a combination of the backup key and the
    /// local ACI.  This ID is used both as the salt for the backup encryption and
    /// to create the anonymous credentials for interacting with server stored backups
    func backupID(
        localAci: Aci,
        mode: MessageBackup.EncryptionMode,
        tx: DBReadTransaction
    ) throws -> Data

    /// Private key derived from the BackupKey + ACI that is used for signing backup auth presentations.
    /// Always implicitly uses ``MessageBackup/EncryptionMode/remote``.
    func backupPrivateKey(localAci: Aci, tx: DBReadTransaction) throws -> PrivateKey

    /// LibSignal.BackupAuthCredentialRequestContext derived from the ACI and BackupKey and used primarily
    /// for building backup credentials.
    /// Always implicitly uses ``MessageBackup/EncryptionMode/remote``.
    func backupAuthRequestContext(localAci: Aci, tx: DBReadTransaction) throws -> BackupAuthCredentialRequestContext

    func messageBackupKey(
        localAci: Aci,
        mode: MessageBackup.EncryptionMode,
        tx: DBReadTransaction
    ) throws -> MessageBackupKey

    /// Always implicitly uses ``MessageBackup/EncryptionMode/remote``.
    func mediaEncryptionMetadata(
        mediaName: String,
        type: MediaTierEncryptionType,
        tx: any DBReadTransaction
    ) throws -> MediaTierEncryptionMetadata

    func mediaId(
        mediaName: String,
        type: MediaTierEncryptionType,
        backupKey: SVR.DerivedKeyData
    ) throws -> Data

    /// Builds an encrypting StreamTransform object derived from the backup master key and the backupID
    func createEncryptingStreamTransform(
        localAci: Aci,
        mode: MessageBackup.EncryptionMode,
        tx: DBReadTransaction
    ) throws -> EncryptingStreamTransform

    func createDecryptingStreamTransform(
        localAci: Aci,
        mode: MessageBackup.EncryptionMode,
        tx: DBReadTransaction
    ) throws -> DecryptingStreamTransform

    func createHmacGeneratingStreamTransform(
        localAci: Aci,
        mode: MessageBackup.EncryptionMode,
        tx: DBReadTransaction
    ) throws -> HmacStreamTransform

    func createHmacValidatingStreamTransform(
        localAci: Aci,
        mode: MessageBackup.EncryptionMode,
        tx: DBReadTransaction
    ) throws -> HmacStreamTransform
}
