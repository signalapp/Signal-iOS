//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public class BackupArchiveDistributionListRecipientArchiver: BackupArchiveProtoStreamWriter {
    typealias RecipientId = BackupArchive.RecipientId
    typealias RecipientAppId = BackupArchive.RecipientArchivingContext.Address

    typealias ArchiveMultiFrameResult = BackupArchive.ArchiveMultiFrameResult<RecipientAppId>
    private typealias ArchiveFrameError = BackupArchive.ArchiveFrameError<RecipientAppId>

    typealias RestoreFrameResult = BackupArchive.RestoreFrameResult<RecipientId>
    private typealias RestoreFrameError = BackupArchive.RestoreFrameError<RecipientId>

    private let privateStoryThreadDeletionManager: any PrivateStoryThreadDeletionManager
    private let storyStore: BackupArchiveStoryStore
    private let threadStore: BackupArchiveThreadStore

    init(
        privateStoryThreadDeletionManager: any PrivateStoryThreadDeletionManager,
        storyStore: BackupArchiveStoryStore,
        threadStore: BackupArchiveThreadStore,
    ) {
        self.privateStoryThreadDeletionManager = privateStoryThreadDeletionManager
        self.storyStore = storyStore
        self.threadStore = threadStore
    }

    func archiveAllDistributionListRecipients(
        stream: BackupArchiveProtoOutputStream,
        context: BackupArchive.RecipientArchivingContext,
    ) throws(CancellationError) -> ArchiveMultiFrameResult {
        var errors = [ArchiveFrameError]()

        do {
            // enumerate deleted threads
            for item in privateStoryThreadDeletionManager.allDeletedIdentifiers(tx: context.tx) {
                try Task.checkCancellation()
                autoreleasepool {
                    context.bencher.processFrame { frameBencher in
                        self.archiveDeletedStoryList(
                            rawDistributionId: item,
                            stream: stream,
                            frameBencher: frameBencher,
                            context: context,
                            errors: &errors,
                        )
                    }
                }
            }
            try context.bencher.wrapEnumeration(
                threadStore.enumerateStoryThreads(tx:block:),
                tx: context.tx,
            ) { storyThread, frameBencher in
                try Task.checkCancellation()
                autoreleasepool {
                    self.archiveStoryThread(
                        storyThread,
                        stream: stream,
                        frameBencher: frameBencher,
                        context: context,
                        errors: &errors,
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
        stream: BackupArchiveProtoOutputStream,
        frameBencher: BackupArchive.Bencher.FrameBencher,
        context: BackupArchive.RecipientArchivingContext,
        errors: inout [ArchiveFrameError],
    ) {
        guard let distributionId = BackupArchive.DistributionId(storyThread: storyThread) else {
            // This optionality is a result of the UUID initializer being failable.
            // This shouldn't be encountered in practice since the uniqueId is always generated from
            // a UUID (or 'My Story' identifier).  But if this is encountered, report an error and skip
            // this d-list with a generic 'missing identifier' message.
            errors.append(.archiveFrameError(
                .distributionListMissingDistributionId,
                // Spoof a random id since we don't have one but error mechanisms require it.
                .distributionList(.init(UUID())),
            ))
            return
        }

        let distributionListAppId: RecipientAppId = .distributionList(distributionId)

        let recipientDbRowIds: [SignalRecipient.RowId]
        do {
            recipientDbRowIds = try storyStore.fetchRecipientIds(for: storyThread, context: context)
        } catch {
            errors.append(.archiveFrameError(.unableToFetchDistributionListRecipients, distributionListAppId))
            return
        }

        let memberRecipientIds: [UInt64] = recipientDbRowIds.compactMap { recipientDbRowId -> UInt64? in
            guard let recipientId = context.recipientId(forRecipientDbRowId: recipientDbRowId) else {
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

        Self.writeFrameToStream(
            stream,
            objectId: distributionListAppId,
            frameBencher: frameBencher,
        ) {
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
        stream: BackupArchiveProtoOutputStream,
        frameBencher: BackupArchive.Bencher.FrameBencher,
        context: BackupArchive.RecipientArchivingContext,
        errors: inout [ArchiveFrameError],
    ) {
        guard let distributionUUID = UUID(data: rawDistributionId) else {
            // This optionality is a result of the UUID initializer being failable.
            // This shouldn't be encountered in practice since the uniqueId is always generated from
            // a UUID (or 'My Story' identifier).  But if this is encountered, report an error and skip
            // this d-list with a generic 'missing identifier' message.
            errors.append(.archiveFrameError(
                .distributionListMissingDistributionId,
                // Spoof a random id since we don't have one but error mechanisms require it.
                .distributionList(.init(UUID())),
            ))
            return
        }
        let distributionId = BackupArchive.DistributionId(distributionUUID)
        let distributionListAppId: RecipientAppId = .distributionList(distributionId)

        guard
            let deletionTimestamp = privateStoryThreadDeletionManager.deletedAtTimestamp(
                forDistributionListIdentifier: rawDistributionId,
                tx: context.tx,
            )
        else {
            errors.append(.archiveFrameError(.distributionListMissingDeletionTimestamp, distributionListAppId))
            return
        }

        guard BackupArchive.Timestamps.isValid(deletionTimestamp) else {
            errors.append(.archiveFrameError(.distributionListInvalidTimestamp, distributionListAppId))
            return
        }

        let recipientId = context.assignRecipientId(to: distributionListAppId)

        var distributionList = BackupProto_DistributionListItem()
        distributionList.distributionID = distributionId.value.data
        distributionList.item = .deletionTimestamp(deletionTimestamp)

        Self.writeFrameToStream(
            stream,
            objectId: distributionListAppId,
            frameBencher: frameBencher,
        ) {
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
        context: BackupArchive.RecipientRestoringContext,
    ) -> RestoreFrameResult {
        func restoreFrameError(
            _ error: RestoreFrameError.ErrorType,
            line: UInt = #line,
        ) -> RestoreFrameResult {
            return .failure([.restoreFrameError(error, recipient.recipientId, line: line)])
        }

        guard
            let distributionId =
            BackupArchive.DistributionId(distributionListItem: distributionListItemProto)
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
                    tx: context.tx,
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
                context: context,
            )
        case nil:
            result = .unrecognizedEnum(BackupArchive.UnrecognizedEnumError(
                enumType: BackupProto_DistributionListItem.OneOf_Item.self,
            ))
        }

        context[recipient.recipientId] = .distributionList(distributionId)
        return result
    }

    private func buildDistributionList(
        from distributionListProto: BackupProto_DistributionList,
        distributionId: BackupArchive.DistributionId,
        recipientId: BackupArchive.RecipientId,
        context: BackupArchive.RecipientRestoringContext,
    ) -> RestoreFrameResult {
        var partialErrors = [BackupArchive.RestoreFrameError<RecipientId>]()

        let viewMode: TSThreadStoryViewMode
        let recipientDbRowIds: [SignalRecipient.RowId]

        switch distributionListProto.privacyMode {
        case .all:
            // Only My Story is allowed to use the `all` mode.
            // The way we represent this locally is a `blocklist` with 0 members.
            guard distributionId.isMyStoryId else {
                return .failure([.restoreFrameError(
                    .invalidProtoData(.customDistributionListPrivacyModeAllOrAllExcept),
                    recipientId,
                )])
            }
            viewMode = .blockList
            // Ignore any addresses in the proto, set to empty.
            recipientDbRowIds = []
        case .allExcept:
            // Only My Story is allowed to use the `allExcept` mode.
            // The way we represent this locally is a `blocklist`.
            guard distributionId.isMyStoryId else {
                return .failure([.restoreFrameError(
                    .invalidProtoData(.customDistributionListPrivacyModeAllOrAllExcept),
                    recipientId,
                )])
            }
            viewMode = .blockList
            // Note: if the addresses are empty (because the proto was empty or parsing failed).
            // this will end up behaving the same as `all`: an empty `blocklist`.
            recipientDbRowIds = readRecipientDbRowIds(
                from: distributionListProto,
                recipientId: recipientId,
                context: context,
                partialErrors: &partialErrors,
            )
        case .onlyWith:
            // All stories are allowed to use `onlyWith` aka `explicit`.
            viewMode = .explicit
            recipientDbRowIds = readRecipientDbRowIds(
                from: distributionListProto,
                recipientId: recipientId,
                context: context,
                partialErrors: &partialErrors,
            )
        case .unknown, .UNRECOGNIZED:
            // Fallback to an empty explicit list.
            viewMode = .explicit
            recipientDbRowIds = []
        }

        let storyThread: TSPrivateStoryThread

        // MyStory is created during warmCaches(), so it should be present at this point.
        // But to guard against any future changes, call getOrCreateMyStory() to ensure
        // it is present before updating with the incoming data.
        if distributionId.isMyStoryId {
            do {
                storyThread = try storyStore.createMyStory(
                    name: distributionListProto.name,
                    allowReplies: distributionListProto.allowReplies,
                    viewMode: viewMode,
                    context: context,
                )
            } catch let error {
                return .failure([.restoreFrameError(.databaseInsertionFailed(error), recipientId)])
            }
        } else {
            storyThread = TSPrivateStoryThread(
                uniqueId: distributionId.value.uuidString,
                name: distributionListProto.name,
                allowsReplies: distributionListProto.allowReplies,
                viewMode: viewMode,
            )
            do {
                try storyStore.insert(storyThread, context: context)
            } catch let error {
                return .failure([.restoreFrameError(.databaseInsertionFailed(error), recipientId)])
            }
        }

        for recipientDbRowId in recipientDbRowIds {
            do {
                try storyStore.insertRecipientId(recipientDbRowId, forStoryThreadId: storyThread.sqliteRowId!, context: context)
            } catch let error {
                return .failure([.restoreFrameError(.databaseInsertionFailed(error), recipientId)])
            }
        }

        return .success
    }

    private func readRecipientDbRowIds(
        from distributionListProto: BackupProto_DistributionList,
        recipientId: BackupArchive.RecipientId,
        context: BackupArchive.RecipientRestoringContext,
        partialErrors: inout [BackupArchive.RestoreFrameError<RecipientId>],
    ) -> [SignalRecipient.RowId] {
        distributionListProto
            .memberRecipientIds
            .compactMap {
                if let result = context.recipientDbRowId(forBackupRecipientId: RecipientId(value: $0)) {
                    return result
                } else {
                    partialErrors.append(.restoreFrameError(
                        .invalidProtoData(.invalidDistributionListMember(protoClass: BackupProto_DistributionList.self)),
                        recipientId,
                    ))
                    return nil
                }
            }
    }
}
