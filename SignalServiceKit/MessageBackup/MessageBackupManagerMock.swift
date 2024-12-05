//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

#if TESTABLE_BUILD

open class MessageBackupManagerMock: MessageBackupManager {
    public func downloadEncryptedBackup(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth
    ) async throws -> URL {
        return URL(string: "file://")!
    }

    public func uploadEncryptedBackup(
        metadata: Upload.EncryptedBackupUploadMetadata,
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth
    ) async throws -> Upload.Result<Upload.EncryptedBackupUploadMetadata> {
        return Upload.Result(
            cdnKey: "cdnKey",
            cdnNumber: 1,
            localUploadMetadata: .init(
                fileUrl: URL(string: "file://")!,
                digest: Data(),
                encryptedDataLength: 0,
                plaintextDataLength: 0),
            beginTimestamp: 0,
            finishTimestamp: Date().ows_millisecondsSince1970
        )
    }

    public func exportEncryptedBackup(
        localIdentifiers: LocalIdentifiers,
        backupKey: BackupKey,
        backupPurpose: MessageBackupPurpose
    ) async throws -> ProgressReportingTask<Upload.EncryptedBackupUploadMetadata, Error> {
        return ProgressReportingTask(
            task: Task {
                return Upload.EncryptedBackupUploadMetadata(
                    fileUrl: URL(string: "file://")!,
                    digest: Data(),
                    encryptedDataLength: 0,
                    plaintextDataLength: 0
                )
            },
            progress: Progress(totalUnitCount: 0)
        )
    }

    public func exportPlaintextBackup(
        localIdentifiers: LocalIdentifiers,
        backupPurpose: MessageBackupPurpose
    ) async throws -> ProgressReportingTask<URL, Error> {
        return ProgressReportingTask(task: Task { URL(string: "file://")! }, progress: Progress(totalUnitCount: 0))
    }

    public func importEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        backupKey: BackupKey
    ) async throws -> ProgressReportingTask<Void, Error> {
        return ProgressReportingTask(task: Task {}, progress: Progress(totalUnitCount: 0))
    }
    public func importPlaintextBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers
    ) async throws -> ProgressReportingTask<Void, Error> {
        return ProgressReportingTask(task: Task {}, progress: Progress(totalUnitCount: 0))
    }
    public func validateEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        backupKey: BackupKey,
        backupPurpose: MessageBackupPurpose
    ) async throws {}
}

#endif
