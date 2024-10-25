//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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
        mode: MessageBackup.EncryptionMode
    ) async throws -> Upload.EncryptedBackupUploadMetadata {
        return Upload.EncryptedBackupUploadMetadata(
            fileUrl: URL(string: "file://")!,
            digest: Data(),
            encryptedDataLength: 0,
            plaintextDataLength: 0
        )
    }

    public func exportPlaintextBackup(localIdentifiers: LocalIdentifiers) async throws -> URL {
        return URL(string: "file://")!
    }

    public func importEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        mode: MessageBackup.EncryptionMode
    ) async throws {}
    public func importPlaintextBackup(fileUrl: URL, localIdentifiers: LocalIdentifiers) async throws {}
    public func validateEncryptedBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        mode: MessageBackup.EncryptionMode
    ) async throws {}
}

#endif
