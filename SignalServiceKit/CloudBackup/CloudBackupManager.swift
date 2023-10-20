//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol CloudBackupManager {

    /// Outputs file url the backup proto is located at.
    func createBackup() async throws -> URL

    func importBackup(fileUrl: URL) async throws
}
