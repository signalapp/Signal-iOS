//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class MessageBackupManagerMock: MessageBackupManager {
    public func createBackup(localIdentifiers: LocalIdentifiers) async throws -> URL { return URL(string: "file://")! }

    public func importBackup(localIdentifiers: LocalIdentifiers, fileUrl: URL) async throws { }
}

#endif
