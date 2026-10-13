//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

import Foundation
import LibSignalClient

class BackupArchiveManagerMock: BackupArchiveManager {
    func backupCdnInfo(
        backupKey: MessageRootBackupKey,
        backupAuth: BackupServiceAuth,
        logger: PrefixedLogger,
    ) async throws -> BackupCdnInfo {
        return BackupCdnInfo(
            fileInfo: AttachmentDownloads.CdnInfo(contentLength: 0, lastModified: Date()),
            metadataHeader: BackupNonce.MetadataHeader(data: Data()),
        )
    }

    func downloadEncryptedBackup(
        backupKey: MessageRootBackupKey,
        backupAuth: BackupServiceAuth,
        progress: OWSProgressSink?,
        logger: PrefixedLogger,
    ) async throws -> URL {
        return URL(string: "file://")!
    }

    func uploadEncryptedBackup(
        backupKey: MessageRootBackupKey,
        metadata: Upload.EncryptedBackupUploadMetadata,
        auth: ChatServiceAuth,
        progress: OWSProgressSink?,
        logger: PrefixedLogger,
    ) async throws -> Upload.Result<Upload.EncryptedBackupUploadMetadata> {
        return Upload.Result(
            cdnKey: "cdnKey",
            cdnNumber: 1,
            localUploadMetadata: metadata,
            beginTimestamp: 0,
            finishTimestamp: Date().ows_millisecondsSince1970,
        )
    }

    func exportEncryptedBackup(
        localIdentifiers: LocalIdentifiers,
        backupPurpose: BackupExportPurpose,
        progress: OWSProgressSink?,
        logger: PrefixedLogger,
    ) async throws -> Upload.EncryptedBackupUploadMetadata {
        let source = progress?.addSource(withLabel: "", unitCount: 1)
        source?.incrementCompletedUnitCount(by: 1)
        return Upload.EncryptedBackupUploadMetadata(
            exportStartDate: Date(),
            fileUrl: URL(string: "file://")!,
            digest: Data(),
            encryptedDataLength: 0,
            uncompressedDataLength: 0,
            remoteAttachmentByteSize: 0,
            localAttachmentByteSize: 0,
            nonceMetadata: nil,
        )
    }

    func exportPlaintextBackupForTests(
        localIdentifiers: LocalIdentifiers,
    ) async throws -> URL {
        return URL(string: "file://")!
    }

    func backupRestoreState(tx: DBReadTransaction) -> BackupRestoreState {
        return .none
    }

    func importEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        isPrimaryDevice: Bool,
        source: BackupImportSource,
        progress: OWSProgressSink?,
        logger: PrefixedLogger,
    ) async throws {
        let source = progress?.addSource(withLabel: "", unitCount: 1)
        source?.incrementCompletedUnitCount(by: 1)
    }

    func importPlaintextBackupForTests(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
    ) async throws {}

    func finalizeBackupImport(progress: OWSProgressSink?) async throws {
        let source = progress?.addSource(withLabel: "", unitCount: 1)
        source?.incrementCompletedUnitCount(by: 1)
    }

    func scheduleRestoreFromSVRBBeforeNextExport(tx: DBWriteTransaction) {
        // Do Nothing
    }
}

#endif
