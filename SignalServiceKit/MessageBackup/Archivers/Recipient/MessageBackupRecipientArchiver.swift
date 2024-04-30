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

    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<RecipientId>

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

    private let blockingManager: MessageBackup.Shims.BlockingManager
    private let disappearingMessageConfigStore: DisappearingMessagesConfigurationStore
    private let groupsV2: GroupsV2
    private let profileManager: MessageBackup.Shims.ProfileManager
    private let recipientDatabaseTable: any RecipientDatabaseTable
    private let recipientHidingManager: RecipientHidingManager
    private let recipientManager: any SignalRecipientManager
    private let signalServiceAddressCache: SignalServiceAddressCache
    private let storyStore: StoryStore
    private let threadStore: ThreadStore
    private let tsAccountManager: TSAccountManager
    private let usernameLookupManager: UsernameLookupManager

    public init(
        blockingManager: MessageBackup.Shims.BlockingManager,
        disappearingMessageConfigStore: DisappearingMessagesConfigurationStore,
        groupsV2: GroupsV2,
        profileManager: MessageBackup.Shims.ProfileManager,
        recipientDatabaseTable: any RecipientDatabaseTable,
        recipientHidingManager: RecipientHidingManager,
        recipientManager: any SignalRecipientManager,
        signalServiceAddressCache: SignalServiceAddressCache,
        storyStore: StoryStore,
        threadStore: ThreadStore,
        tsAccountManager: TSAccountManager,
        usernameLookupManager: UsernameLookupManager
    ) {
        self.blockingManager = blockingManager
        self.disappearingMessageConfigStore = disappearingMessageConfigStore
        self.groupsV2 = groupsV2
        self.profileManager = profileManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientHidingManager = recipientHidingManager
        self.recipientManager = recipientManager
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
            tsAccountManager: tsAccountManager,
            usernameLookupManager: usernameLookupManager
        ),
        MessageBackupGroupRecipientArchiver(
            disappearingMessageConfigStore: disappearingMessageConfigStore,
            groupsV2: groupsV2,
            profileManager: profileManager,
            storyStore: storyStore,
            threadStore: threadStore
        )
        // TODO: add missing archivers:
        // * story distribution list (BackupDistributionList)
        // * release notes thread (BackupReleaseNotes)
    ]

    func archiveRecipients(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveMultiFrameResult {
        var partialErrors = [ArchiveMultiFrameResult.ArchiveFrameError]()
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
