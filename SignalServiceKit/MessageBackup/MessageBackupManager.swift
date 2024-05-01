//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol MessageBackupManager {

    func validateBackup(localIdentifiers: LocalIdentifiers, fileUrl: URL) async throws

    /// Outputs file url the backup proto is located at.
    func createBackup(localIdentifiers: LocalIdentifiers) async throws -> Upload.BackupUploadMetadata

    func uploadBackup(metadata: Upload.BackupUploadMetadata, localIdentifiers: LocalIdentifiers, auth: ChatServiceAuth) async throws -> Upload.Result<Upload.BackupUploadMetadata>

    func downloadBackup(localIdentifiers: LocalIdentifiers, auth: ChatServiceAuth) async throws -> URL

    func importBackup(localIdentifiers: LocalIdentifiers, fileUrl: URL) async throws
}
