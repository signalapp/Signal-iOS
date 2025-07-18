//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum BackupRestoreState: Int, Codable {
    /// Has never restored from a backup in this database's history
    case none = 0
    /// Finished restoring a backup but still has post-restore steps to complete.
    case unfinalized = 100
    /// Backup restore is complete, nothing else to do.
    case finalized = 200
}

public protocol BackupArchiveManager {

    // MARK: - Interact with remotes

    /// Fetch the CDN info for the current backup
    func backupCdnInfo(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth
    ) async throws -> AttachmentDownloads.CdnInfo

    /// Download the encrypted backup for the current user to a local file.
    func downloadEncryptedBackup(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth
    ) async throws -> URL

    /// Upload the local encrypted backup identified by the given metadata for
    /// the current user.
    func uploadEncryptedBackup(
        metadata: Upload.EncryptedBackupUploadMetadata,
        registeredBackupIDToken: RegisteredBackupIDToken,
        auth: ChatServiceAuth,
        progress: OWSProgressSink?,
    ) async throws -> Upload.Result<Upload.EncryptedBackupUploadMetadata>

    // MARK: - Export

    /// Export an encrypted backup binary to a local file.
    /// - SeeAlso `uploadEncryptedBackup`
    func exportEncryptedBackup(
        localIdentifiers: LocalIdentifiers,
        backupKey: BackupKey,
        backupPurpose: MessageBackupPurpose,
        progress: OWSProgressSink?
    ) async throws -> Upload.EncryptedBackupUploadMetadata

#if TESTABLE_BUILD
    /// Export a plaintext backup binary at the returned file URL, for use in
    /// integration tests.
    func exportPlaintextBackupForTests(
        localIdentifiers: LocalIdentifiers,
        progress: OWSProgressSink?
    ) async throws -> URL
#endif

    // MARK: - Import

    /// Returns whether this device has ever successfully restored from a backup
    /// and committed the contents to the database.
    func backupRestoreState(tx: DBReadTransaction) -> BackupRestoreState

    /// Import a backup from the encrypted binary file at the given local URL.
    /// - SeeAlso ``downloadEncryptedBackup(localIdentifiers:auth:)``
    func importEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        isPrimaryDevice: Bool,
        backupKey: BackupKey,
        backupPurpose: MessageBackupPurpose,
        progress: OWSProgressSink?
    ) async throws

    /// Import a backup from the plaintext binary file at the given local URL.
    func importPlaintextBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        isPrimaryDevice: Bool,
        backupPurpose: MessageBackupPurpose,
        progress: OWSProgressSink?
    ) async throws

    /// Call this if ``backupRestoreState(tx:)`` returns ``BackupRestoreState/unfinalized``.
    /// ``importEncryptedBackup(fileUrl:localIdentifiers:isPrimaryDevice:backupKey:backupPurpose:progress:)``
    /// and ``importPlaintextBackup(fileUrl:localIdentifiers:isPrimaryDevice:backupPurpose:progress:)`` will
    /// finalize on their own; however if this process is interrupted (by e.g. cancellation or app termination) callers MUST NOT import again
    /// but MUST call this method to finish the in-progress import finalization steps. This method is idempotent; import is not.
    func finalizeBackupImport(progress: OWSProgressSink?) async throws

    // MARK: -

    /// Validate the encrypted backup file located at the given local URL.
    func validateEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        backupKey: BackupKey,
        backupPurpose: MessageBackupPurpose
    ) async throws
}
