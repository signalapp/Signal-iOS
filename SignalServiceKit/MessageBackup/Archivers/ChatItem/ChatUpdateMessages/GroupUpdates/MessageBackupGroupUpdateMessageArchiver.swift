//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

final class MessageBackupGroupUpdateMessageArchiver {
    typealias Details = MessageBackup.InteractionArchiveDetails
    typealias ArchiveChatUpdateMessageResult = MessageBackup.ArchiveInteractionResult<Details>
    typealias RestoreChatUpdateMessageResult = MessageBackup.RestoreInteractionResult<Void>

    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>
    private typealias PersistableGroupUpdateItem = TSInfoMessage.PersistableGroupUpdateItem

    private let groupUpdateBuilder: GroupUpdateItemBuilder
    private let groupUpdateHelper: GroupUpdateInfoMessageInserterBackupHelper
    private let interactionStore: MessageBackupInteractionStore

    public init(
        groupUpdateBuilder: GroupUpdateItemBuilder,
        groupUpdateHelper: GroupUpdateInfoMessageInserterBackupHelper,
        interactionStore: MessageBackupInteractionStore
    ) {
        self.groupUpdateBuilder = groupUpdateBuilder
        self.groupUpdateHelper = groupUpdateHelper
        self.interactionStore = interactionStore
    }

    func archiveGroupUpdate(
        infoMessage: TSInfoMessage,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveChatUpdateMessageResult {
        let groupUpdateItems: [TSInfoMessage.PersistableGroupUpdateItem]
        switch infoMessage.groupUpdateMetadata(
            localIdentifiers: context.recipientContext.localIdentifiers
        ) {
        case .nonGroupUpdate:
            // Should be impossible.
            return .completeFailure(.fatalArchiveError(.developerError(
                OWSAssertionError("Invalid interaction type")
            )))
        case .legacyRawString:
            return .skippableChatUpdate(.skippableGroupUpdate(.legacyRawString))
        case .newGroup(let groupModel, let updateMetadata):
            groupUpdateItems = groupUpdateBuilder.precomputedUpdateItemsForNewGroup(
                newGroupModel: groupModel.groupModel,
                newDisappearingMessageToken: groupModel.dmToken,
                localIdentifiers: context.recipientContext.localIdentifiers,
                groupUpdateSource: updateMetadata.source,
                tx: context.tx
            )
        case .modelDiff(let old, let new, let updateMetadata):
            groupUpdateItems = groupUpdateBuilder.precomputedUpdateItemsByDiffingModels(
                oldGroupModel: old.groupModel,
                newGroupModel: new.groupModel,
                oldDisappearingMessageToken: old.dmToken,
                newDisappearingMessageToken: new.dmToken,
                localIdentifiers: context.recipientContext.localIdentifiers,
                groupUpdateSource: updateMetadata.source,
                tx: context.tx
            )
        case .precomputed(let persistableGroupUpdateItemsWrapper):
            groupUpdateItems = persistableGroupUpdateItemsWrapper.updateItems
        }
        return archiveGroupUpdateItems(
            groupUpdateItems,
            for: infoMessage,
            context: context
        )
    }

    func archiveGroupUpdateItems(
        _ groupUpdateItems: [TSInfoMessage.PersistableGroupUpdateItem],
        for interaction: TSInteraction,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveChatUpdateMessageResult {
        var partialErrors = [ArchiveFrameError]()

        let contentsResult = Self.archiveGroupUpdates(
            groupUpdates: groupUpdateItems,
            interactionId: interaction.uniqueInteractionId,
            localIdentifiers: context.recipientContext.localIdentifiers,
            partialErrors: &partialErrors
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

        let details = Details(
            author: context.recipientContext.localRecipientId,
            directionalDetails: .directionless(directionlessDetails),
            dateCreated: interaction.timestamp,
            expireStartDate: nil,
            expiresInMs: nil,
            isSealedSender: false,
            chatItemType: .updateMessage(chatUpdate),
            isSmsPreviouslyRestoredFromBackup: false
        )

        if partialErrors.isEmpty {
            return .success(details)
        } else {
            return .partialFailure(details, partialErrors)
        }
    }

    private static func archiveGroupUpdates(
        groupUpdates: [TSInfoMessage.PersistableGroupUpdateItem],
        interactionId: MessageBackup.InteractionUniqueId,
        localIdentifiers: LocalIdentifiers,
        partialErrors: inout [ArchiveFrameError]
    ) -> MessageBackup.ArchiveInteractionResult<BackupProto_GroupChangeChatUpdate> {
        var updates = [BackupProto_GroupChangeChatUpdate.Update]()

        var skipCount = 0
        var latestSkipError: MessageBackup.SkippableChatUpdate.SkippableGroupUpdate?
        for groupUpdate in groupUpdates {
            let result = MessageBackupGroupUpdateSwiftToProtoConverter
                .archiveGroupUpdate(
                    groupUpdate: groupUpdate,
                    localUserAci: localIdentifiers.aci,
                    interactionId: interactionId
                )
            switch result.bubbleUp(
                BackupProto_GroupChangeChatUpdate.self,
                partialErrors: &partialErrors
            ) {
            case .continue(let update):
                updates.append(update)
            case .bubbleUpError(let errorResult):
                switch errorResult {
                case .skippableChatUpdate(.skippableGroupUpdate(let skipError)):
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
                return .skippableChatUpdate(.skippableGroupUpdate(latestSkipError))
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
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreChatUpdateMessageResult {
        let groupThread: TSGroupThread
        switch chatThread.threadType {
        case .contact:
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.groupUpdateMessageInNonGroupChat),
                chatItem.id
            )])
        case .groupV2(let _groupThread):
            groupThread = _groupThread
        }

        var partialErrors = [MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>]()

        let result = MessageBackupGroupUpdateProtoToSwiftConverter
            .restoreGroupUpdates(
                groupUpdates: groupUpdate.updates,
                localUserAci: context.recipientContext.localIdentifiers.aci,
                partialErrors: &partialErrors,
                chatItemId: chatItem.id
            )
        guard var persistableUpdates =
                result.unwrap(partialErrors: &partialErrors)
        else {
            return .messageFailure(partialErrors)
        }

        guard persistableUpdates.isEmpty.negated else {
            // We can't have an empty array of updates!
            return .messageFailure(partialErrors + [.restoreFrameError(
                .invalidProtoData(.emptyGroupUpdates),
                chatItem.id
            )])
        }

        // FIRST, try and do any collapsing. This might collapse
        // the passed in array of updates (modifying it), or
        // may update the most recent TSInfoMessage on disk, or both.
        groupUpdateHelper.collapseIfNeeded(
            updates: &persistableUpdates,
            localIdentifiers: context.recipientContext.localIdentifiers,
            groupThread: groupThread,
            tx: context.tx
        )

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
            updateItems: persistableUpdates
        )

        guard let directionalDetails = chatItem.directionalDetails else {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.chatItemMissingDirectionalDetails),
                chatItem.id
            )])
        }

        do {
            try interactionStore.insert(
                infoMessage,
                in: chatThread,
                chatId: chatItem.typedChatId,
                directionalDetails: directionalDetails,
                context: context
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
