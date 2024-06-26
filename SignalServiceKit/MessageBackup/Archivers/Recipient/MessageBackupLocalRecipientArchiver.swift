//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension MessageBackup {

    public struct LocalRecipientId: MessageBackupLoggableId {
        public var typeLogString: String { "Local Recipient" }
        public var idLogString: String { "" }
    }

    public enum ArchiveLocalRecipientResult {
        case success(RecipientId)
        case failure(ArchiveFrameError<LocalRecipientId>)
    }
}

/**
 * Archiver for the ``BackupProto.SelfRecipient`` recipient, a.k.a. the local user author/recipient.
 * Used as the recipient for the Note To Self chat.
 */
public protocol MessageBackupLocalRecipientArchiver: MessageBackupProtoArchiver {

    typealias RecipientId = MessageBackup.RecipientId

    /// Archive the local recipient.
    func archiveLocalRecipient(stream: MessageBackupProtoOutputStream) -> MessageBackup.ArchiveLocalRecipientResult

    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<RecipientId>

    /// Restore a single ``BackupProto.Recipient`` frame for the local recipient.
    ///
    /// - Returns: ``RestoreFrameResult.success`` if the frame was read without error.
    /// How to handle ``RestoreFrameResult.failure`` is up to the caller,
    /// but typically an error will be shown to the user, but the restore will be allowed to proceed.
    func restore(
        _ recipient: BackupProto.Recipient,
        context: MessageBackup.RecipientRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult

    /// Determines whether the given recipient is the local recipient.
    static func canRestore(_ recipient: BackupProto.Recipient) -> Bool
}

public class MessageBackupLocalRecipientArchiverImpl: MessageBackupLocalRecipientArchiver {

    private static let localRecipientId = RecipientId(value: 1)

    public func archiveLocalRecipient(stream: MessageBackupProtoOutputStream) -> MessageBackup.ArchiveLocalRecipientResult {
        let error = Self.writeFrameToStream(
            stream,
            objectId: MessageBackup.LocalRecipientId()
        ) {
            let selfRecipient = BackupProto.SelfRecipient()

            var recipient = BackupProto.Recipient(id: Self.localRecipientId.value)
            recipient.destination = .selfRecipient(selfRecipient)

            var frame = BackupProto.Frame()
            frame.item = .recipient(recipient)
            return frame
        }

        if let error {
            return .failure(error)
        } else {
            return .success(Self.localRecipientId)
        }
    }

    public static func canRestore(_ recipient: BackupProto.Recipient) -> Bool {
        switch recipient.destination {
        case .selfRecipient:
            return true
        case nil, .contact, .group, .distributionList, .releaseNotes:
            return false
        }
    }

    public func restore(
        _ recipient: BackupProto.Recipient,
        context: MessageBackup.RecipientRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult {
        switch recipient.destination {
        case .selfRecipient:
            break
        case nil, .contact, .group, .distributionList, .releaseNotes:
            return .failure([.restoreFrameError(
                .developerError(OWSAssertionError("Non self recipient sent to local recipient archiver")),
                recipient.recipientId
            )])
        }

        context[recipient.recipientId] = .localAddress
        return .success
    }
}
