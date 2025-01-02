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
    ) throws(CancellationError) -> ArchiveMultiFrameResult {
        var errors = [ArchiveFrameError]()

        do {
            // enumerate deleted threads
            for item in privateStoryThreadDeletionManager.allDeletedIdentifiers(tx: context.tx) {
                try Task.checkCancellation()
                autoreleasepool {
                    self.archiveDeletedStoryList(
                        rawDistributionId: item,
                        stream: stream,
                        context: context,
                        errors: &errors
                    )
                }
            }
            try threadStore.enumerateStoryThreads(context: context) { storyThread in
                try Task.checkCancellation()
                autoreleasepool {
                    self.archiveStoryThread(
                        storyThread,
                        stream: stream,
                        context: context,
                        errors: &errors
                    )
                }

                return true
            }
        } catch let error as CancellationError {
            throw error
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
        guard let distributionId = MessageBackup.DistributionId(storyThread: storyThread) else {
            // This optionality is a result of the UUID initializer being failable.
            // This shouldn't be encountered in practice since the uniqueId is always generated from
            // a UUID (or 'My Story' identifier).  But if this is encountered, report an error and skip
            // this d-list with a generic 'missing identifier' message.
            errors.append(.archiveFrameError(
                .distributionListMissingDistributionId,
                // Spoof a random id since we don't have one but error mechanisms require it.
                .distributionList(.init(UUID()))
            ))
            return
        }

        let distributionListAppId: RecipientAppId = .distributionList(distributionId)

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
        let privacyMode: BackupProto_DistributionList.PrivacyMode
        switch storyThread.storyViewMode {
        case .disabled:
            // Skip deleted distribution lists
            return
        case .default:
            errors.append(.archiveFrameError(.distributionListHasDefaultViewMode, distributionListAppId))
            return
        case .explicit:
            // My story and private stories are both allowed to be explicit lists.
            // These lists can be empty.
            privacyMode = .onlyWith
        case .blockList:
            // ONLY My Story is allowed to be a blocklist.
            guard distributionId.isMyStoryId else {
                errors.append(.archiveFrameError(.customDistributionListBlocklistViewMode, distributionListAppId))
                return
            }
            // A blocklist with empty members is used to represent "all signal connections".
            // A blocklist with 1+ members is a blocklist like you'd expect.
            if memberRecipientIds.isEmpty {
                privacyMode = .all
            } else {
                privacyMode = .allExcept
            }
        }

        var distributionList = BackupProto_DistributionList()
        // Empty name specifically expected for My Story, and `storyThread.name`
        // will return the localized "My Story" string.
        distributionList.name = storyThread.isMyStory ? "" : storyThread.name
        distributionList.allowReplies = storyThread.allowsReplies
        distributionList.privacyMode = privacyMode
        distributionList.memberRecipientIds = memberRecipientIds

        var distributionListItem = BackupProto_DistributionListItem()
        distributionListItem.distributionID = distributionId.value.data
        distributionListItem.item = .distributionList(distributionList)

        let recipientId = context.assignRecipientId(to: distributionListAppId)

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
        rawDistributionId: Data,
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.RecipientArchivingContext,
        errors: inout [ArchiveFrameError]
    ) {
        guard let distributionUUID = UUID(data: rawDistributionId) else {
            // This optionality is a result of the UUID initializer being failable.
            // This shouldn't be encountered in practice since the uniqueId is always generated from
            // a UUID (or 'My Story' identifier).  But if this is encountered, report an error and skip
            // this d-list with a generic 'missing identifier' message.
            errors.append(.archiveFrameError(
                .distributionListMissingDistributionId,
                // Spoof a random id since we don't have one but error mechanisms require it.
                .distributionList(.init(UUID()))
            ))
            return
        }
        let distributionId = MessageBackup.DistributionId(distributionUUID)
        let distributionListAppId: RecipientAppId = .distributionList(distributionId)

        guard let deletionTimestamp = privateStoryThreadDeletionManager.deletedAtTimestamp(
            forDistributionListIdentifier: rawDistributionId,
            tx: context.tx
        ) else {
            errors.append(.archiveFrameError(.distributionListMissingDeletionTimestamp, distributionListAppId))
            return
        }

        let recipientId = context.assignRecipientId(to: distributionListAppId)

        var distributionList = BackupProto_DistributionListItem()
        distributionList.distributionID = distributionId.value.data
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

        guard
            let distributionId =
                MessageBackup.DistributionId(distributionListItem: distributionListItemProto)
        else {
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
                    forDistributionListIdentifier: distributionId.value.data,
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

        context[recipient.recipientId] = .distributionList(distributionId)
        return result
    }

    private func buildDistributionList(
        from distributionListProto: BackupProto_DistributionList,
        distributionId: MessageBackup.DistributionId,
        recipientId: MessageBackup.RecipientId,
        context: MessageBackup.RecipientRestoringContext
    ) -> RestoreFrameResult {
        var partialErrors = [MessageBackup.RestoreFrameError<RecipientId>]()

        let viewMode: TSThreadStoryViewMode
        let addresses: [MessageBackup.ContactAddress]

        switch distributionListProto.privacyMode {
        case .all:
            // Only My Story is allowed to use the `all` mode.
            // The way we represent this locally is a `blocklist` with 0 members.
            guard distributionId.isMyStoryId else {
                return .failure([.restoreFrameError(
                    .invalidProtoData(.customDistributionListPrivacyModeAllOrAllExcept),
                    recipientId
                )])
            }
            viewMode = .blockList
            // Ignore any addresses in the proto, set to empty.
            addresses = []

        case .allExcept:
            // Only My Story is allowed to use the `allExcept` mode.
            // The way we represent this locally is a `blocklist`.
            guard distributionId.isMyStoryId else {
                return .failure([.restoreFrameError(
                    .invalidProtoData(.customDistributionListPrivacyModeAllOrAllExcept),
                    recipientId
                )])
            }
            viewMode = .blockList
            // Note: if the addresses are empty (because the proto was empty or parsing failed).
            // this will end up behaving the same as `all`: an empty `blocklist`.
            addresses = readAddresses(
                from: distributionListProto,
                recipientId: recipientId,
                context: context,
                partialErrors: &partialErrors
            )
        case .onlyWith:
            // All stories are allowed to use `onlyWith` aka `explicit`.
            viewMode = .explicit
            addresses = readAddresses(
                from: distributionListProto,
                recipientId: recipientId,
                context: context,
                partialErrors: &partialErrors
            )
        case .unknown, .UNRECOGNIZED:
            return .failure([.restoreFrameError(
                .invalidProtoData(.invalidDistributionListPrivacyMode),
                recipientId
            )])
        }

        // MyStory is created during warmCaches(), so it should be present at this point.
        // But to guard against any future changes, call getOrCreateMyStory() to ensure
        // it is present before updating with the incoming data.
        if distributionId.isMyStoryId {
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
                uniqueId: distributionId.value.uuidString,
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

    private func readAddresses(
        from distributionListProto: BackupProto_DistributionList,
        recipientId: MessageBackup.RecipientId,
        context: MessageBackup.RecipientRestoringContext,
        partialErrors: inout [MessageBackup.RestoreFrameError<RecipientId>]
    ) -> [MessageBackup.ContactAddress] {
        distributionListProto
            .memberRecipientIds
            .compactMap {
                switch context[RecipientId(value: $0)] {
                case .contact(let contactAddress):
                    return contactAddress
                case .distributionList, .group, .localAddress, .releaseNotesChannel, .callLink, .none:
                    partialErrors.append(.restoreFrameError(
                        .invalidProtoData(.invalidDistributionListMember(protoClass: BackupProto_DistributionList.self)),
                        recipientId
                    ))
                    return nil
                }
            }
    }
}
