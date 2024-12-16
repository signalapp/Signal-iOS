//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension MessageBackup {
    public struct LocalRecipientId: MessageBackupLoggableId {
        public var typeLogString: String { "Local Recipient" }
        public var idLogString: String { "" }
    }

    public typealias ArchiveLocalRecipientResult = ArchiveSingleFrameResult<RecipientId, LocalRecipientId>
    public typealias RestoreLocalRecipientResult = RestoreFrameResult<RecipientId>
}

/// Archiver for the ``BackupProto_Self`` recipient, a.k.a. the local
/// user author/recipient.  Used as the recipient for the Note To Self chat.
public class MessageBackupLocalRecipientArchiver: MessageBackupProtoArchiver {
    private static let localRecipientId = MessageBackup.RecipientId(value: 1)

    private let profileManager: MessageBackup.Shims.ProfileManager
    public init(profileManager: MessageBackup.Shims.ProfileManager) {
        self.profileManager = profileManager
    }

    /// Archive the local recipient.
    public func archiveLocalRecipient(
        stream: MessageBackupProtoOutputStream
    ) -> MessageBackup.ArchiveLocalRecipientResult {
        let error = Self.writeFrameToStream(
            stream,
            objectId: MessageBackup.LocalRecipientId()
        ) {
            let selfRecipient = BackupProto_Self()

            var recipient = BackupProto_Recipient()
            recipient.id = Self.localRecipientId.value
            recipient.destination = .self_p(selfRecipient)

            var frame = BackupProto_Frame()
            frame.item = .recipient(recipient)
            return frame
        }

        if let error {
            return .failure(error)
        } else {
            return .success(Self.localRecipientId)
        }
    }

    /// Restore a single ``BackupProto/Recipient`` frame for the local recipient.
    public func restoreSelfRecipient(
        _ selfRecipientProto: BackupProto_Self,
        recipient: BackupProto_Recipient,
        context: MessageBackup.RecipientRestoringContext
    ) -> MessageBackup.RestoreLocalRecipientResult {
        context[recipient.recipientId] = .localAddress
        profileManager.addToWhitelist(context.localIdentifiers.aciAddress, tx: context.tx)
        return .success
    }
}
