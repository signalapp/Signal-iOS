//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension MessageBackup {
    /// An identifier for the ``BackupProtoAccountData`` backup frame.
    ///
    /// Uses a singleton pattern, as there is only ever one account data frame
    /// in a backup.
    struct AccountDataId: MessageBackupLoggableId {
        static let localUser = AccountDataId()

        private init() {}

        // MARK: MessageBackupLoggableId

        public var typeLogString: String { "BackupProtoAccountData" }
        public var idLogString: String { "localUser" }
    }
}

public protocol MessageBackupAccountDataArchiver: MessageBackupProtoArchiver {

}
