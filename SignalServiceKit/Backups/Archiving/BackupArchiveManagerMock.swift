//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

import Foundation
public import LibSignalClient

open class BackupArchiveManagerMock: BackupArchiveManager {
    public func backupCdnInfo(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth
    ) async throws -> AttachmentDownloads.CdnInfo {
        return AttachmentDownloads.CdnInfo(contentLength: 0, lastModified: Date())
    }

    public func downloadEncryptedBackup(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth
    ) async throws -> URL {
        return URL(string: "file://")!
    }

    public func uploadEncryptedBackup(
        metadata: Upload.EncryptedBackupUploadMetadata,
        registeredBackupIDToken: RegisteredBackupIDToken,
        auth: ChatServiceAuth,
        progress: OWSProgressSink?,
    ) async throws -> Upload.Result<Upload.EncryptedBackupUploadMetadata> {
        return Upload.Result(
            cdnKey: "cdnKey",
            cdnNumber: 1,
            localUploadMetadata: .init(
                fileUrl: URL(string: "file://")!,
                digest: Data(),
                encryptedDataLength: 0,
                plaintextDataLength: 0,
                attachmentByteSize: metadata.attachmentByteSize,
            ),
            beginTimestamp: 0,
            finishTimestamp: Date().ows_millisecondsSince1970
        )
    }

    public func exportEncryptedBackup(
        localIdentifiers: LocalIdentifiers,
        backupKey: BackupKey,
        backupPurpose: MessageBackupPurpose,
        progress: OWSProgressSink?
    ) async throws -> Upload.EncryptedBackupUploadMetadata {
        let source = await progress?.addSource(withLabel: "", unitCount: 1)
        source?.incrementCompletedUnitCount(by: 1)
        return Upload.EncryptedBackupUploadMetadata(
            fileUrl: URL(string: "file://")!,
            digest: Data(),
            encryptedDataLength: 0,
            plaintextDataLength: 0,
            attachmentByteSize: 0,
        )
    }

    public func exportPlaintextBackupForTests(
        localIdentifiers: LocalIdentifiers,
        progress: OWSProgressSink?
    ) async throws -> URL {
        let source = await progress?.addSource(withLabel: "", unitCount: 1)
        source?.incrementCompletedUnitCount(by: 1)
        return URL(string: "file://")!
    }

    public func backupRestoreState(tx: DBReadTransaction) -> BackupRestoreState {
        return .none
    }

    public func importEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        isPrimaryDevice: Bool,
        backupKey: BackupKey,
        backupPurpose: MessageBackupPurpose,
        progress: OWSProgressSink?
    ) async throws {
        let source = await progress?.addSource(withLabel: "", unitCount: 1)
        source?.incrementCompletedUnitCount(by: 1)
    }

    public func importPlaintextBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        isPrimaryDevice: Bool,
        backupPurpose: MessageBackupPurpose,
        progress: OWSProgressSink?
    ) async throws {
        let source = await progress?.addSource(withLabel: "", unitCount: 1)
        source?.incrementCompletedUnitCount(by: 1)
    }

    public func finalizeBackupImport(progress: OWSProgressSink?) async throws {
        let source = await progress?.addSource(withLabel: "", unitCount: 1)
        source?.incrementCompletedUnitCount(by: 1)
    }

    public func validateEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        backupKey: BackupKey,
        backupPurpose: MessageBackupPurpose
    ) async throws {}
}

#endif
