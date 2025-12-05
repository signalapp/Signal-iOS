//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

import Foundation
public import LibSignalClient

open class BackupArchiveManagerMock: BackupArchiveManager {
    public func backupCdnInfo(
        backupKey: MessageRootBackupKey,
        backupAuth: BackupServiceAuth,
    ) async throws -> BackupCdnInfo {
        return BackupCdnInfo(
            fileInfo: AttachmentDownloads.CdnInfo(contentLength: 0, lastModified: Date()),
            metadataHeader: BackupNonce.MetadataHeader(data: Data())
        )
    }

    public func downloadEncryptedBackup(
        backupKey: MessageRootBackupKey,
        backupAuth: BackupServiceAuth,
        progress: OWSProgressSink?
    ) async throws -> URL {
        return URL(string: "file://")!
    }

    public func uploadEncryptedBackup(
        backupKey: MessageRootBackupKey,
        metadata: Upload.EncryptedBackupUploadMetadata,
        auth: ChatServiceAuth,
        progress: OWSProgressSink?,
    ) async throws -> Upload.Result<Upload.EncryptedBackupUploadMetadata> {
        return Upload.Result(
            cdnKey: "cdnKey",
            cdnNumber: 1,
            localUploadMetadata: metadata,
            beginTimestamp: 0,
            finishTimestamp: Date().ows_millisecondsSince1970
        )
    }

    public func exportEncryptedBackup(
        localIdentifiers: LocalIdentifiers,
        backupPurpose: BackupExportPurpose,
        progress: OWSProgressSink?
    ) async throws -> Upload.EncryptedBackupUploadMetadata {
        let source = await progress?.addSource(withLabel: "", unitCount: 1)
        source?.incrementCompletedUnitCount(by: 1)
        return Upload.EncryptedBackupUploadMetadata(
            exportStartTimestamp: Date(),
            fileUrl: URL(string: "file://")!,
            digest: Data(),
            encryptedDataLength: 0,
            plaintextDataLength: 0,
            attachmentByteSize: 0,
            nonceMetadata: nil,
        )
    }

    public func exportPlaintextBackupForTests(
        localIdentifiers: LocalIdentifiers,
    ) async throws -> URL {
        return URL(string: "file://")!
    }

    public func backupRestoreState(tx: DBReadTransaction) -> BackupRestoreState {
        return .none
    }

    public func importEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        isPrimaryDevice: Bool,
        source: BackupImportSource,
        progress: OWSProgressSink?
    ) async throws {
        let source = await progress?.addSource(withLabel: "", unitCount: 1)
        source?.incrementCompletedUnitCount(by: 1)
    }

    public func importPlaintextBackupForTests(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
    ) async throws {}

    public func finalizeBackupImport(progress: OWSProgressSink?) async throws {
        let source = await progress?.addSource(withLabel: "", unitCount: 1)
        source?.incrementCompletedUnitCount(by: 1)
    }

    public func scheduleRestoreFromSVRBBeforeNextExport(tx: DBWriteTransaction) {
        // Do Nothing
    }
}

#endif
