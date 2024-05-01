//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class MessageBackupManagerMock: MessageBackupManager {
    public func validateBackup(localIdentifiers: LocalIdentifiers, fileUrl: URL) async throws { }

    public func uploadBackup(metadata: Upload.BackupUploadMetadata, localIdentifiers: LocalIdentifiers, auth: ChatServiceAuth) async throws -> Upload.Result<Upload.BackupUploadMetadata> {
        return Upload.Result(
            cdnKey: "cdnKey",
            cdnNumber: 1,
            localUploadMetadata: .init(
                fileUrl: URL(string: "file://")!,
                digest: Data(),
                encryptedDataLength: 0,
                plaintextDataLength: 0),
            beginTimestamp: Date.distantPast.ows_millisecondsSince1970,
            finishTimestamp: Date().ows_millisecondsSince1970
        )
    }

    public func downloadBackup(localIdentifiers: LocalIdentifiers, auth: ChatServiceAuth) async throws -> URL {
        return URL(string: "file://")!
    }

    public func createBackup(localIdentifiers: LocalIdentifiers) async throws -> Upload.BackupUploadMetadata {
        return .init(
            fileUrl: URL(string: "file://")!,
            digest: Data(),
            encryptedDataLength: 0,
            plaintextDataLength: 0
        )
    }

    public func importBackup(localIdentifiers: LocalIdentifiers, fileUrl: URL) async throws { }
}

#endif
