//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/**
 * Archives all ``BackupProto.Recipient`` frames, fanning out to per-recipient-type
 * ``MessageBackupRecipientDestinationArchiver`` concrete classes to do the actual frame creation and writing.
 */
public protocol MessageBackupRecipientArchiver: MessageBackupProtoArchiver {

    typealias RecipientId = MessageBackup.RecipientId
    typealias RecipientAppId = MessageBackup.RecipientArchivingContext.Address

    typealias ArchiveMultiFrameResult = MessageBackup.ArchiveMultiFrameResult<RecipientAppId>
    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<RecipientId>

    /// Archive all recipients.
    ///
    /// - Returns: ``ArchiveMultiFrameResult.success`` if all frames were written without error, or either
    /// partial or complete failure otherwise.
    /// How to handle ``ArchiveMultiFrameResult.partialSuccess`` is up to the caller,
    /// but typically an error will be shown to the user, but the backup will be allowed to proceed.
    /// ``ArchiveMultiFrameResult.completeFailure``, on the other hand, will stop the entire backup,
    /// and should be used if some critical or category-wide failure occurs.
    func archiveRecipients(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveMultiFrameResult

    /// Restore a single ``BackupProto.Recipient`` frame.
    ///
    /// - Returns: ``RestoreFrameResult.success`` if all frames were read without error.
    /// How to handle ``RestoreFrameResult.failure`` is up to the caller,
    /// but typically an error will be shown to the user, but the restore will be allowed to proceed.
    func restore(
        _ recipient: BackupProto.Recipient,
        context: MessageBackup.RecipientRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult
}

internal class MessageBackupRecipientArchiverImpl: MessageBackupRecipientArchiver {
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<RecipientAppId>

    private let blockingManager: any MessageBackup.Shims.BlockingManager
    private let disappearingMessageConfigStore: any DisappearingMessagesConfigurationStore
    private let groupsV2: GroupsV2
    private let profileManager: any MessageBackup.Shims.ProfileManager
    private let recipientDatabaseTable: any RecipientDatabaseTable
    private let recipientHidingManager: any RecipientHidingManager
    private let recipientManager: any SignalRecipientManager
    private let privateStoryThreadDeletionManager: any PrivateStoryThreadDeletionManager
    private let signalServiceAddressCache: SignalServiceAddressCache
    private let storyStore: any StoryStore
    private let threadStore: any ThreadStore
    private let tsAccountManager: any TSAccountManager
    private let usernameLookupManager: any UsernameLookupManager

    public init(
        blockingManager: any MessageBackup.Shims.BlockingManager,
        disappearingMessageConfigStore: DisappearingMessagesConfigurationStore,
        groupsV2: GroupsV2,
        profileManager: any MessageBackup.Shims.ProfileManager,
        recipientDatabaseTable: any RecipientDatabaseTable,
        recipientHidingManager: any RecipientHidingManager,
        recipientManager: any SignalRecipientManager,
        privateStoryThreadDeletionManager: any PrivateStoryThreadDeletionManager,
        signalServiceAddressCache: SignalServiceAddressCache,
        storyStore: any StoryStore,
        threadStore: any ThreadStore,
        tsAccountManager: any TSAccountManager,
        usernameLookupManager: any UsernameLookupManager
    ) {
        self.blockingManager = blockingManager
        self.disappearingMessageConfigStore = disappearingMessageConfigStore
        self.groupsV2 = groupsV2
        self.profileManager = profileManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientHidingManager = recipientHidingManager
        self.recipientManager = recipientManager
        self.privateStoryThreadDeletionManager = privateStoryThreadDeletionManager
        self.signalServiceAddressCache = signalServiceAddressCache
        self.storyStore = storyStore
        self.threadStore = threadStore
        self.tsAccountManager = tsAccountManager
        self.usernameLookupManager = usernameLookupManager
    }

    private lazy var destinationArchivers: [MessageBackupRecipientDestinationArchiver] = [
        MessageBackupContactRecipientArchiver(
            blockingManager: blockingManager,
            profileManager: profileManager,
            recipientDatabaseTable: recipientDatabaseTable,
            recipientHidingManager: recipientHidingManager,
            recipientManager: recipientManager,
            signalServiceAddressCache: signalServiceAddressCache,
            storyStore: storyStore,
            threadStore: threadStore,
            tsAccountManager: tsAccountManager,
            usernameLookupManager: usernameLookupManager
        ),
        MessageBackupGroupRecipientArchiver(
            disappearingMessageConfigStore: disappearingMessageConfigStore,
            groupsV2: groupsV2,
            profileManager: profileManager,
            storyStore: storyStore,
            threadStore: threadStore
        ),
        MessageBackupDistributionListRecipientArchiver(
            privateStoryThreadDeletionManager: privateStoryThreadDeletionManager,
            storyStore: storyStore,
            threadStore: threadStore
        ),
        MessageBackupReleaseNotesRecipientArchiver()
    ]

    func archiveRecipients(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveMultiFrameResult {
        var partialErrors = [ArchiveFrameError]()
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
        _ recipient: BackupProto.Recipient,
        context: MessageBackup.RecipientRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult {
        for archiver in destinationArchivers {
            guard type(of: archiver).canRestore(recipient) else {
                continue
            }
            return archiver.restore(recipient, context: context, tx: tx)
        }
        return .failure([.restoreFrameError(
            .invalidProtoData(.unrecognizedRecipientType),
            recipient.recipientId
        )])
    }
}
