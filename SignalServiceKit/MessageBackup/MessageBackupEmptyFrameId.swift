//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension MessageBackup {
    /// An identifier for an empty ``BackupProto_Frame``.
    ///
    /// Uses a singleton pattern, as frames do not contain their own ID and
    /// consequently all empty frames are equivalent.
    struct EmptyFrameId: MessageBackupLoggableId {
        static let shared = EmptyFrameId()

        private init() {}

        // MARK: MessageBackupLoggableId

        var typeLogString: String { "MessageBackupFrame" }
        var idLogString: String { "Empty" }
    }
}
