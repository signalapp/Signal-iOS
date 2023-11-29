//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/**
 * Archives all ``BackupProtoRecipient`` frames, fanning out to per-recipient-type
 * ``CloudBackupRecipientDestinationArchiver`` concrete classes to do the actual frame creation and writing.
 */
public protocol CloudBackupRecipientArchiver: CloudBackupProtoArchiver {

    typealias RecipientId = CloudBackup.RecipientId

    typealias ArchiveFramesResult = CloudBackup.ArchiveFramesResult<RecipientId>

    /// Archive all recipients.
    ///
    /// - Returns: ``ArchiveFramesResult.success`` if all frames were written without error, or either
    /// partial or complete failure otherwise.
    /// How to handle ``ArchiveFramesResult.partialSuccess`` is up to the caller,
    /// but typically an error will be shown to the user, but the backup will be allowed to proceed.
    /// ``ArchiveFramesResult.completeFailure``, on the other hand, will stop the entire backup,
    /// and should be used if some critical or category-wide failure occurs.
    func archiveRecipients(
        stream: CloudBackupProtoOutputStream,
        context: CloudBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveFramesResult

    typealias RestoreFrameResult = CloudBackup.RestoreFrameResult<RecipientId>

    /// Restore a single ``BackupProtoRecipient`` frame.
    ///
    /// - Returns: ``RestoreFrameResult.success`` if all frames were read without error.
    /// How to handle ``RestoreFrameResult.failure`` is up to the caller,
    /// but typically an error will be shown to the user, but the restore will be allowed to proceed.
    func restore(
        _ recipient: BackupProtoRecipient,
        context: CloudBackup.RecipientRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult
}

internal class CloudBackupRecipientArchiverImpl: CloudBackupRecipientArchiver {

    private let blockingManager: CloudBackup.Shims.BlockingManager
    private let groupsV2: GroupsV2
    private let profileManager: CloudBackup.Shims.ProfileManager
    private let recipientHidingManager: RecipientHidingManager
    private let signalRecipientFetcher: CloudBackup.Shims.SignalRecipientFetcher
    private let storyFinder: CloudBackup.Shims.StoryFinder
    private let tsAccountManager: TSAccountManager
    private let tsThreadFetcher: CloudBackup.Shims.TSThreadFetcher

    public init(
        blockingManager: CloudBackup.Shims.BlockingManager,
        groupsV2: GroupsV2,
        profileManager: CloudBackup.Shims.ProfileManager,
        recipientHidingManager: RecipientHidingManager,
        signalRecipientFetcher: CloudBackup.Shims.SignalRecipientFetcher,
        storyFinder: CloudBackup.Shims.StoryFinder,
        tsAccountManager: TSAccountManager,
        tsThreadFetcher: CloudBackup.Shims.TSThreadFetcher
    ) {
        self.blockingManager = blockingManager
        self.groupsV2 = groupsV2
        self.profileManager = profileManager
        self.recipientHidingManager = recipientHidingManager
        self.signalRecipientFetcher = signalRecipientFetcher
        self.storyFinder = storyFinder
        self.tsAccountManager = tsAccountManager
        self.tsThreadFetcher = tsThreadFetcher
    }

    private lazy var destinationArchivers: [CloudBackupRecipientDestinationArchiver] = [
        CloudBackupContactRecipientArchiver(
            blockingManager: blockingManager,
            profileManager: profileManager,
            recipientHidingManager: recipientHidingManager,
            signalRecipientFetcher: signalRecipientFetcher,
            storyFinder: storyFinder,
            tsAccountManager: tsAccountManager
        ),
        CloudBackupGroupRecipientArchiver(
            groupsV2: groupsV2,
            profileManager: profileManager,
            storyFinder: storyFinder,
            tsThreadFetcher: tsThreadFetcher
        ),
        CloudBackupNoteToSelfRecipientArchiver()
        // TODO: add missing archivers:
        // * story distribution list (BackupDistributionList)
        // * release notes thread (BackupReleaseNotes)
    ]

    func archiveRecipients(
        stream: CloudBackupProtoOutputStream,
        context: CloudBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveFramesResult {
        var partialErrors = [ArchiveFramesResult.Error]()
        for archiver in destinationArchivers {
            let archiverResults = archiver.archiveRecipients(
                stream: stream,
                context: context,
                tx: tx
            )
            switch archiverResults {
            case .success:
                continue
            case .completeFailure(let error):
                return .completeFailure(error)
            case .partialSuccess(let newErrors):
                partialErrors.append(contentsOf: newErrors)
            }
        }
        return partialErrors.isEmpty ? .success : .partialSuccess(partialErrors)
    }

    func restore(
        _ recipient: BackupProtoRecipient,
        context: CloudBackup.RecipientRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult {
        for archiver in destinationArchivers {
            guard type(of: archiver).canRestore(recipient) else {
                continue
            }
            return archiver.restore(recipient, context: context, tx: tx)
        }
        return .failure(recipient.recipientId, .unknownFrameType)
    }
}
