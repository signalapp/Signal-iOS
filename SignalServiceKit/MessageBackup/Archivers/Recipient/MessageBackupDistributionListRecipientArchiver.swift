//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public class MessageBackupDistributionListRecipientArchiver: MessageBackupProtoArchiver {
    typealias RecipientId = MessageBackup.RecipientId
    typealias RecipientAppId = MessageBackup.RecipientArchivingContext.Address

    typealias ArchiveMultiFrameResult = MessageBackup.ArchiveMultiFrameResult<RecipientAppId>
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<RecipientAppId>

    typealias RestoreFrameResult = MessageBackup.RestoreFrameResult<RecipientId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<RecipientId>

    private let privateStoryThreadDeletionManager: any PrivateStoryThreadDeletionManager
    private let storyStore: MessageBackupStoryStore
    private let threadStore: MessageBackupThreadStore

    init(
        privateStoryThreadDeletionManager: any PrivateStoryThreadDeletionManager,
        storyStore: MessageBackupStoryStore,
        threadStore: MessageBackupThreadStore
    ) {
        self.privateStoryThreadDeletionManager = privateStoryThreadDeletionManager
        self.storyStore = storyStore
        self.threadStore = threadStore
    }

    func archiveAllDistributionListRecipients(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext
    ) -> ArchiveMultiFrameResult {
        var errors = [ArchiveFrameError]()

        do {
            // enumerate deleted threads
            for item in privateStoryThreadDeletionManager.allDeletedIdentifiers(tx: context.tx) {
                self.archiveDeletedStoryList(
                    distributionId: item,
                    stream: stream,
                    context: context,
                    errors: &errors
                )
            }
            try threadStore.enumerateStoryThreads(context: context) { storyThread in
                self.archiveStoryThread(
                    storyThread,
                    stream: stream,
                    context: context,
                    errors: &errors
                )

                return true
            }
        } catch {
            // The enumeration of threads failed, not the processing of one single thread.
            return .completeFailure(.fatalArchiveError(.threadIteratorError(error)))
        }

        if errors.isEmpty {
            return .success
        } else {
            return .partialSuccess(errors)
        }
    }

    private func archiveStoryThread(
        _ storyThread: TSPrivateStoryThread,
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext,
        errors: inout [ArchiveFrameError]
    ) {
        // Skip deleted distribution lists
        guard storyThread.storyViewMode != .disabled else { return }

        guard let distributionId = storyThread.distributionListIdentifier else {
            // This optionality is a result of the UUID initializer being failable.
            // This shouldn't be encountered in practice since the uniqueId is always generated from
            // a UUID (or 'My Story' identifier).  But if this is encountered, report an error and skip
            // this d-list with a generic 'missing identifier' message.
            owsFailDebug("Missing distributionListIdentifier for story distribution list")
            return
        }

        let distributionListAppId: RecipientAppId = .distributionList(distributionId)
        let recipientId = context.assignRecipientId(to: distributionListAppId)

        let memberRecipientIds = storyThread.addresses.compactMap { address -> UInt64? in
            guard let contactAddress = address.asSingleServiceIdBackupAddress() else {
                errors.append(.archiveFrameError(.invalidDistributionListMemberAddress, distributionListAppId))
                return nil
            }
            guard let recipientId = context[.contact(contactAddress)] else {
                errors.append(.archiveFrameError(.referencedRecipientIdMissing(.distributionList(distributionId)), distributionListAppId))
                return nil
            }
            return recipientId.value
        }

        // Ensure that explicit/blocklist have valid member recipient addresses
        let privacyMode: BackupProto_DistributionList.PrivacyMode? = {
            switch storyThread.storyViewMode {
            case .disabled:
                return nil
            case .default:
                guard memberRecipientIds.count == 0 else {
                    errors.append(.archiveFrameError(.distributionListUnexpectedRecipients, distributionListAppId))
                    return nil
                }
                return .all
            case .explicit:
                guard memberRecipientIds.count > 0 else {
                    errors.append(.archiveFrameError(.distributionListMissingRecipients, distributionListAppId))
                    return nil
                }
                return .onlyWith
            case .blockList:
                return .allExcept
            }
        }()

        guard let privacyMode else {
            // Error should have been recorded above, so just return here
            return
        }

        var distributionList = BackupProto_DistributionList()
        // Empty name specifically expected for My Story, and `storyThread.name`
        // will return the localized "My Story" string.
        distributionList.name = storyThread.isMyStory ? "" : storyThread.name
        distributionList.allowReplies = storyThread.allowsReplies
        distributionList.privacyMode = privacyMode
        distributionList.memberRecipientIds = memberRecipientIds

        var distributionListItem = BackupProto_DistributionListItem()
        distributionListItem.distributionID = distributionId
        distributionListItem.item = .distributionList(distributionList)

        Self.writeFrameToStream(stream, objectId: distributionListAppId) {
            var recipient = BackupProto_Recipient()
            recipient.id = recipientId.value
            recipient.destination = .distributionList(distributionListItem)

            var frame = BackupProto_Frame()
            frame.item = .recipient(recipient)
            return frame
        }.map { errors.append($0) }
    }

    private func archiveDeletedStoryList(
        distributionId: Data,
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext,
        errors: inout [ArchiveFrameError]
    ) {
        let distributionListAppId: RecipientAppId = .distributionList(distributionId)

        guard let deletionTimestamp = privateStoryThreadDeletionManager.deletedAtTimestamp(
            forDistributionListIdentifier: distributionId,
            tx: context.tx
        ) else {
            errors.append(.archiveFrameError(.distributionListMissingDeletionTimestamp, distributionListAppId))
            return
        }

        let recipientId = context.assignRecipientId(to: distributionListAppId)

        var distributionList = BackupProto_DistributionListItem()
        distributionList.distributionID = distributionId
        distributionList.item = .deletionTimestamp(deletionTimestamp)

        Self.writeFrameToStream(stream, objectId: distributionListAppId) {
            var recipient = BackupProto_Recipient()
            recipient.id = recipientId.value
            recipient.destination = .distributionList(distributionList)

            var frame = BackupProto_Frame()
            frame.item = .recipient(recipient)
            return frame
        }.map { errors.append($0) }
    }

    func restoreDistributionListRecipientProto(
        _ distributionListItemProto: BackupProto_DistributionListItem,
        recipient: BackupProto_Recipient,
        context: MessageBackup.RecipientRestoringContext
    ) -> RestoreFrameResult {
        func restoreFrameError(
            _ error: RestoreFrameError.ErrorType,
            line: UInt = #line
        ) -> RestoreFrameResult {
            return .failure([.restoreFrameError(error, recipient.recipientId, line: line)])
        }

        guard let distributionId = UUID(data: distributionListItemProto.distributionID) else {
            return restoreFrameError(.invalidProtoData(.invalidDistributionListId))
        }

        let result: RestoreFrameResult
        switch distributionListItemProto.item {
        case .deletionTimestamp(let deletionTimestamp):
            // Restore deleted distribution lists identifiers. These are needed
            // to preserve the deleted distribution list entry in storage service
            // during a sync.  If these weren't backed up, there's a chance the deleted
            // list would be removed from storage service before the deletion would
            // be picked up by a linked device. Deleted lists that are too old will
            // be filtered by the `setDeletedAtTimestamp` method, so filtering isn't
            // necessary here.
            if deletionTimestamp > 0 {
                privateStoryThreadDeletionManager.recordDeletedAtTimestamp(
                    deletionTimestamp,
                    forDistributionListIdentifier: distributionId.data,
                    tx: context.tx
                )
                result = .success
            } else {
                result = restoreFrameError(.invalidProtoData(.invalidDistributionListDeletionTimestamp))
            }
        case .distributionList(let distributionListItemProto):
            result = buildDistributionList(
                from: distributionListItemProto,
                distributionId: distributionId,
                recipientId: recipient.recipientId,
                context: context
            )
        case nil:
            result = restoreFrameError(.invalidProtoData(.distributionListItemMissingItem))
        }

        context[recipient.recipientId] = .distributionList(distributionListItemProto.distributionID)
        return result
    }

    private func buildDistributionList(
        from distributionListProto: BackupProto_DistributionList,
        distributionId: UUID,
        recipientId: MessageBackup.RecipientId,
        context: MessageBackup.RecipientRestoringContext
    ) -> RestoreFrameResult {
        var error: RestoreFrameResult?

        let addresses = distributionListProto
            .memberRecipientIds
            .compactMap {
                switch context[RecipientId(value: $0)] {
                case .contact(let contactAddress):
                    return contactAddress
                case .distributionList, .group, .localAddress, .releaseNotesChannel, .none:
                    error = .failure([.restoreFrameError(
                        .invalidProtoData(.invalidDistributionListMember(protoClass: BackupProto_DistributionList.self)),
                        recipientId
                    )])
                    return nil
                }
            }

        if let error {
            return error
        }

        let viewMode: TSThreadStoryViewMode? = {
            switch distributionListProto.privacyMode {
            case .all:
                return .default
            case .allExcept:
                return .blockList
            case .onlyWith:
                return .explicit
            case .unknown, .UNRECOGNIZED:
                return nil
            }
        }()

        guard let viewMode else {
            return .failure([.restoreFrameError(
                .invalidProtoData(.invalidDistributionListPrivacyMode),
                recipientId
            )])
        }

        switch viewMode {
        case .explicit:
            guard addresses.count > 0 else {
                return .failure([.restoreFrameError(
                    .invalidProtoData(.invalidDistributionListPrivacyModeMissingRequiredMembers),
                    recipientId
                )])
            }
        case .default, .blockList, .disabled:
            break
        }

        // MyStory is created during warmCaches(), so it should be present at this point.
        // But to guard against any future changes, call getOrCreateMyStory() to ensure
        // it is present before updating with the incoming data.
        if TSPrivateStoryThread.myStoryUniqueId == distributionId.uuidString {
            do {
                try storyStore.createMyStory(
                    name: distributionListProto.name,
                    allowReplies: distributionListProto.allowReplies,
                    viewMode: viewMode,
                    addresses: addresses,
                    context: context
                )
            } catch let error {
                return .failure([.restoreFrameError(.databaseInsertionFailed(error), recipientId)])
            }
        } else {
            let storyThread = TSPrivateStoryThread(
                uniqueId: distributionId.uuidString,
                name: distributionListProto.name,
                allowsReplies: distributionListProto.allowReplies,
                addresses: addresses.map { $0.asInteropAddress() },
                viewMode: viewMode
            )
            do {
                try storyStore.insert(storyThread, context: context)
            } catch let error {
                return .failure([.restoreFrameError(.databaseInsertionFailed(error), recipientId)])
            }
        }

        return .success
    }
}
