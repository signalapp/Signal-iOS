//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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
 * Archiver for the ``BackupProtoSelfRecipient`` recipient, a.k.a. the local user author/recipient.
 * Used as the recipient for the Note To Self chat.
 */
public protocol MessageBackupLocalRecipientArchiver: MessageBackupProtoArchiver {

    typealias RecipientId = MessageBackup.RecipientId

    /// Archive the local recipient.
    func archiveLocalRecipient(stream: MessageBackupProtoOutputStream) -> MessageBackup.ArchiveLocalRecipientResult

    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<RecipientId>

    /// Restore a single ``BackupProtoRecipient`` frame for the local recipient.
    ///
    /// - Returns: ``RestoreFrameResult.success`` if the frame was read without error.
    /// How to handle ``RestoreFrameResult.failure`` is up to the caller,
    /// but typically an error will be shown to the user, but the restore will be allowed to proceed.
    func restore(
        _ recipient: BackupProtoRecipient,
        context: MessageBackup.RecipientRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult

    /// Determines whether the given recipient is the local recipient.
    static func canRestore(_ recipient: BackupProtoRecipient) -> Bool
}

public class MessageBackupLocalRecipientArchiverImpl: MessageBackupLocalRecipientArchiver {

    private static let localRecipientId = RecipientId(integerLiteral: 1)

    public func archiveLocalRecipient(stream: MessageBackupProtoOutputStream) -> MessageBackup.ArchiveLocalRecipientResult {
        let selfRecipientBuilder = BackupProtoSelfRecipient.builder()
        let recipientBuilder = BackupProtoRecipient.builder(
            id: Self.localRecipientId.value
        )

        let error = Self.writeFrameToStream(
            stream,
            objectId: MessageBackup.LocalRecipientId()
        ) { frameBuilder in
            let selfRecipientProto = try selfRecipientBuilder.build()
            recipientBuilder.setSelfRecipient(selfRecipientProto)
            let recipientProto = try recipientBuilder.build()
            frameBuilder.setRecipient(recipientProto)
            return try frameBuilder.build()
        }
        if let error {
            return .failure(error)
        } else {
            return .success(Self.localRecipientId)
        }
    }

    public static func canRestore(_ recipient: BackupProtoRecipient) -> Bool {
        return recipient.selfRecipient != nil
    }

    public func restore(
        _ recipient: BackupProtoRecipient,
        context: MessageBackup.RecipientRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult {
        guard recipient.selfRecipient != nil else {
            return .failure([.developerError(
                recipient.recipientId,
                OWSAssertionError("Non self recipient sent to local recipient archiver")
            )])
        }

        context[recipient.recipientId] = .localAddress

        return .success
    }
}
