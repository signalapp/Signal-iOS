//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

final class BackupArchiveGroupUpdateMessageArchiver {
    typealias Details = BackupArchive.InteractionArchiveDetails
    typealias ArchiveChatUpdateMessageResult = BackupArchive.ArchiveInteractionResult<Details>
    typealias RestoreChatUpdateMessageResult = BackupArchive.RestoreInteractionResult<Void>

    private typealias ArchiveFrameError = BackupArchive.ArchiveFrameError<BackupArchive.InteractionUniqueId>
    private typealias PersistableGroupUpdateItem = TSInfoMessage.PersistableGroupUpdateItem

    private let groupUpdateBuilder: GroupUpdateItemBuilder
    private let interactionStore: BackupArchiveInteractionStore

    init(
        groupUpdateBuilder: GroupUpdateItemBuilder,
        interactionStore: BackupArchiveInteractionStore,
    ) {
        self.groupUpdateBuilder = groupUpdateBuilder
        self.interactionStore = interactionStore
    }

    func archiveGroupUpdate(
        infoMessage: TSInfoMessage,
        threadInfo: BackupArchive.ChatArchivingContext.CachedThreadInfo,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveChatUpdateMessageResult {
        let groupUpdateItems: [TSInfoMessage.PersistableGroupUpdateItem]
        switch infoMessage.groupUpdateMetadata(
            localIdentifiers: context.recipientContext.localIdentifiers,
        ) {
        case .nonGroupUpdate:
            // Should be impossible.
            return .completeFailure(.fatalArchiveError(.developerError(
                OWSAssertionError("Invalid interaction type"),
            )))
        case .legacyRawString:
            return .skippableInteraction(.skippableGroupUpdate(.legacyRawString))
        case .newGroup(let groupModel, let source):
            groupUpdateItems = groupUpdateBuilder.precomputedUpdateItemsForNewGroup(
                newGroupModel: groupModel.groupModel,
                newDisappearingMessageToken: groupModel.dmToken,
                localIdentifiers: context.recipientContext.localIdentifiers,
                groupUpdateSource: source,
                tx: context.tx,
            )
        case .modelDiff(let old, let new, let source):
            groupUpdateItems = groupUpdateBuilder.precomputedUpdateItemsByDiffingModels(
                oldGroupModel: old.groupModel,
                newGroupModel: new.groupModel,
                oldDisappearingMessageToken: old.dmToken,
                newDisappearingMessageToken: new.dmToken,
                localIdentifiers: context.recipientContext.localIdentifiers,
                groupUpdateSource: source,
                tx: context.tx,
            )
        case .precomputed(let persistableGroupUpdateItemsWrapper):
            groupUpdateItems = persistableGroupUpdateItemsWrapper.updateItems
        }
        return archiveGroupUpdateItems(
            groupUpdateItems,
            for: infoMessage,
            threadInfo: threadInfo,
            context: context,
        )
    }

    func archiveGroupUpdateItems(
        _ groupUpdateItems: [TSInfoMessage.PersistableGroupUpdateItem],
        for interaction: TSInteraction,
        threadInfo: BackupArchive.ChatArchivingContext.CachedThreadInfo,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveChatUpdateMessageResult {
        var partialErrors = [ArchiveFrameError]()

        let contentsResult = Self.archiveGroupUpdates(
            groupUpdates: groupUpdateItems,
            interactionId: interaction.uniqueInteractionId,
            localIdentifiers: context.recipientContext.localIdentifiers,
            partialErrors: &partialErrors,
        )
        let groupChange: BackupProto_GroupChangeChatUpdate
        switch contentsResult.bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let groupUpdate):
            groupChange = groupUpdate
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        var chatUpdate = BackupProto_ChatUpdateMessage()
        chatUpdate.update = .groupChange(groupChange)

        let directionlessDetails = BackupProto_ChatItem.DirectionlessMessageDetails()

        let detailsResult = Details.validateAndBuild(
            interactionUniqueId: interaction.uniqueInteractionId,
            author: .localUser,
            directionalDetails: .directionless(directionlessDetails),
            dateCreated: interaction.timestamp,
            expireStartDate: nil,
            expiresInMs: nil,
            isSealedSender: false,
            chatItemType: .updateMessage(chatUpdate),
            isSmsPreviouslyRestoredFromBackup: false,
            threadInfo: threadInfo,
            pinMessageDetails: nil,
            context: context.recipientContext,
        )

        let details: Details
        switch detailsResult.bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let _details):
            details = _details
        case .bubbleUpError(let error):
            return error
        }

        if partialErrors.isEmpty {
            return .success(details)
        } else {
            return .partialFailure(details, partialErrors)
        }
    }

    private static func archiveGroupUpdates(
        groupUpdates: [TSInfoMessage.PersistableGroupUpdateItem],
        interactionId: BackupArchive.InteractionUniqueId,
        localIdentifiers: LocalIdentifiers,
        partialErrors: inout [ArchiveFrameError],
    ) -> BackupArchive.ArchiveInteractionResult<BackupProto_GroupChangeChatUpdate> {
        var updates = [BackupProto_GroupChangeChatUpdate.Update]()

        var skipCount = 0
        var latestSkipError: BackupArchive.SkippableInteraction.SkippableGroupUpdate?
        for groupUpdate in groupUpdates {
            let result = BackupArchiveGroupUpdateSwiftToProtoConverter
                .archiveGroupUpdate(
                    groupUpdate: groupUpdate,
                    localUserAci: localIdentifiers.aci,
                    interactionId: interactionId,
                )
            switch result.bubbleUp(
                BackupProto_GroupChangeChatUpdate.self,
                partialErrors: &partialErrors,
            ) {
            case .continue(let update):
                updates.append(update)
            case .bubbleUpError(let errorResult):
                switch errorResult {
                case .skippableInteraction(.skippableGroupUpdate(let skipError)):
                    // Don't stop when we encounter a skippable update.
                    skipCount += 1
                    latestSkipError = skipError
                default:
                    return errorResult
                }
            }
        }

        guard updates.isEmpty.negated else {
            if groupUpdates.count == skipCount, let latestSkipError {
                // Its ok; we just skipped everything.
                return .skippableInteraction(.skippableGroupUpdate(latestSkipError))
            }
            return .messageFailure(partialErrors + [.archiveFrameError(.emptyGroupUpdate, interactionId)])
        }

        var groupChangeChatUpdate = BackupProto_GroupChangeChatUpdate()
        groupChangeChatUpdate.updates = updates

        if partialErrors.isEmpty {
            return .success(groupChangeChatUpdate)
        } else {
            return .partialFailure(groupChangeChatUpdate, partialErrors)
        }
    }

    func restoreGroupUpdate(
        _ groupUpdate: BackupProto_GroupChangeChatUpdate,
        chatItem: BackupProto_ChatItem,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreChatUpdateMessageResult {
        let groupThread: TSGroupThread
        switch chatThread.threadType {
        case .contact:
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.groupUpdateMessageInNonGroupChat),
                chatItem.id,
            )])
        case .groupV2(let _groupThread):
            groupThread = _groupThread
        }

        var partialErrors = [BackupArchive.RestoreFrameError<BackupArchive.ChatItemId>]()

        let result = BackupArchiveGroupUpdateProtoToSwiftConverter
            .restoreGroupUpdates(
                groupUpdates: groupUpdate.updates,
                localUserAci: context.recipientContext.localIdentifiers.aci,
                partialErrors: &partialErrors,
                chatItemId: chatItem.id,
            )
        var persistableUpdates: [PersistableGroupUpdateItem]
        switch result.bubbleUp(Void.self, partialErrors: &partialErrors) {
        case .continue(let component):
            persistableUpdates = component
        case .bubbleUpError(let error):
            return error
        }

        guard persistableUpdates.isEmpty.negated else {
            // We can't have an empty array of updates!
            return .messageFailure(partialErrors + [.restoreFrameError(
                .invalidProtoData(.emptyGroupUpdates),
                chatItem.id,
            )])
        }

        guard persistableUpdates.isEmpty.negated else {
            // If we got an empty array, that means it got collapsed!
            // Ok to skip, as any updates should be applied to the
            // previous db entry.
            return .success(())
        }

        // serverGuid is intentionally dropped here. In most cases,
        // this token will be too old to be useful, so don't worry
        // about restoring it.
        let infoMessage: TSInfoMessage = .makeForGroupUpdate(
            timestamp: chatItem.dateSent,
            spamReportingMetadata: .unreportable,
            groupThread: groupThread,
            updateItems: persistableUpdates,
        )

        do {
            try interactionStore.insert(
                infoMessage,
                in: chatThread,
                chatId: chatItem.typedChatId,
                context: context,
            )
        } catch let error {
            return .messageFailure(partialErrors + [.restoreFrameError(.databaseInsertionFailed(error), chatItem.id)])
        }

        if partialErrors.isEmpty {
            return .success(())
        } else {
            return .partialRestore((), partialErrors)
        }
    }
}
