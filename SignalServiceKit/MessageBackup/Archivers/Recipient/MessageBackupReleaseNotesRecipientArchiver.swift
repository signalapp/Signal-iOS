//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Responsible for the "release notes channel" recipient.
///
/// - Important
/// The Release Notes Channel has yet to be built on iOS, and consequently this
/// class is implemented with stubs.
public class MessageBackupReleaseNotesRecipientArchiver: MessageBackupProtoArchiver {
    typealias RecipientId = MessageBackup.RecipientId
    typealias RecipientAppId = MessageBackup.RecipientArchivingContext.Address

    typealias ArchiveMultiFrameResult = MessageBackup.ArchiveMultiFrameResult<RecipientAppId>
    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<RecipientId>

    private let logger: MessageBackupLogger = .shared

    public init() {}

    // MARK: -

    func archiveReleaseNotesRecipient(
        stream: any MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext,
        tx: any DBReadTransaction
    ) -> ArchiveMultiFrameResult {
        // TODO: [Backups] Implement archiving the Release Notes channel.
        logger.warn("No-op archive of a Release Notes recipient!")
        return .success
    }

    // MARK: -

    func restoreReleaseNotesRecipientProto(
        _ releaseNotesRecipientProto: BackupProto_ReleaseNotes,
        recipient: BackupProto_Recipient,
        context: MessageBackup.RecipientRestoringContext,
        tx: any DBWriteTransaction
    ) -> RestoreFrameResult {
        context[recipient.recipientId] = .releaseNotesChannel

        // TODO: [Backups] Implement restoring the Release Notes channel recipient.
        logger.warn("No-op restore of a Release Notes recipient!")
        return .success
    }
}
