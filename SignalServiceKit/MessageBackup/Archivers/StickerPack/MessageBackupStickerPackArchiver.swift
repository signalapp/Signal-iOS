//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public extension MessageBackup {
    /// An identifier for a ``BackupProto.StickerPack`` backup frame.
    struct StickerPackId: MessageBackupLoggableId {
        let value: Data

        init(_ value: Data) {
            self.value = value
        }

        // MARK: MessageBackupLoggableId

        public var typeLogString: String { "BackupProto.StickPack" }
        public var idLogString: String {
            /// Since sticker pack IDs are a cross-client identifier, we don't
            /// want to log them directly.
            return "\(value.hashValue)"
        }
    }
}

public protocol MessageBackupStickerPackArchiver: MessageBackupProtoArchiver {

}
