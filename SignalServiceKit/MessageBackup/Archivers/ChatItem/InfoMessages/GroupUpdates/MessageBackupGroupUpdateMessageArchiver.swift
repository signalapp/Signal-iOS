//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

internal class MessageBackupGroupUpdateMessageArchiver: MessageBackupInteractionArchiver {

    typealias PersistableGroupUpdateItem = TSInfoMessage.PersistableGroupUpdateItem

    private let groupUpdateBuilder: GroupUpdateItemBuilder
    private let groupUpdateHelper: GroupUpdateInfoMessageInserterBackupHelper
    private let interactionStore: InteractionStore

    public init(
        groupUpdateBuilder: GroupUpdateItemBuilder,
        groupUpdateHelper: GroupUpdateInfoMessageInserterBackupHelper,
        interactionStore: InteractionStore
    ) {
        self.groupUpdateBuilder = groupUpdateBuilder
        self.groupUpdateHelper = groupUpdateHelper
        self.interactionStore = interactionStore
    }

    static let archiverType = MessageBackup.InteractionArchiverType.groupUpdateInfoMessage

    func archiveInteraction(
        _ interaction: TSInteraction,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> MessageBackup.ArchiveInteractionResult<Details> {
        guard let infoMessage = interaction as? TSInfoMessage else {
            // Should be impossible.
            return .completeFailure(.fatalArchiveError(.developerError(
                OWSAssertionError("Invalid interaction type")
            )))
        }
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
            return .skippableGroupUpdate(.legacyRawString)
        case .newGroup(let groupModel, let updateMetadata):
            groupUpdateItems = groupUpdateBuilder.precomputedUpdateItemsForNewGroup(
                newGroupModel: groupModel.groupModel,
                newDisappearingMessageToken: groupModel.dmToken,
                localIdentifiers: context.recipientContext.localIdentifiers,
                groupUpdateSource: updateMetadata.source,
                tx: tx
            )
        case .modelDiff(let old, let new, let updateMetadata):
            groupUpdateItems = groupUpdateBuilder.precomputedUpdateItemsByDiffingModels(
                oldGroupModel: old.groupModel,
                newGroupModel: new.groupModel,
                oldDisappearingMessageToken: old.dmToken,
                newDisappearingMessageToken: new.dmToken,
                localIdentifiers: context.recipientContext.localIdentifiers,
                groupUpdateSource: updateMetadata.source,
                tx: tx
            )
        case .precomputed(let persistableGroupUpdateItemsWrapper):
            groupUpdateItems = persistableGroupUpdateItemsWrapper.updateItems
        }

        var partialErrors = [MessageBackupChatItemArchiver.ArchiveMultiFrameResult.ArchiveFrameError]()

        let contentsResult = Self.archiveGroupUpdates(
            groupUpdates: groupUpdateItems,
            interactionId: infoMessage.uniqueInteractionId,
            localIdentifiers: context.recipientContext.localIdentifiers,
            partialErrors: &partialErrors
        )
        let groupChange: BackupProto.GroupChangeChatUpdate
        switch contentsResult.bubbleUp(Details.self, partialErrors: &partialErrors) {
        case .continue(let groupUpdate):
            groupChange = groupUpdate
        case .bubbleUpError(let errorResult):
            return errorResult
        }

        var chatUpdate = BackupProto.ChatUpdateMessage()
        chatUpdate.update = .groupChange(groupChange)

        let directionlessDetails = BackupProto.ChatItem.DirectionlessMessageDetails()

        let details = Details(
            author: context.recipientContext.localRecipientId,
            directionalDetails: .directionless(directionlessDetails),
            expireStartDate: nil,
            expiresInMs: nil,
            isSealedSender: false,
            chatItemType: .updateMessage(chatUpdate)
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
        partialErrors: inout [MessageBackupChatItemArchiver.ArchiveMultiFrameResult.ArchiveFrameError]
    ) -> MessageBackup.ArchiveInteractionResult<BackupProto.GroupChangeChatUpdate> {
        var updates = [BackupProto.GroupChangeChatUpdate.Update]()

        var skipCount = 0
        var latestSkipError: MessageBackup.SkippableGroupUpdate?
        for groupUpdate in groupUpdates {
            let result = MessageBackupGroupUpdateSwiftToProtoConverter
                .archiveGroupUpdate(
                    groupUpdate: groupUpdate,
                    localUserAci: localIdentifiers.aci,
                    interactionId: interactionId
                )
            switch result.bubbleUp(
                BackupProto.GroupChangeChatUpdate.self,
                partialErrors: &partialErrors
            ) {
            case .continue(let update):
                updates.append(update)
            case .bubbleUpError(let errorResult):
                switch errorResult {
                case .skippableGroupUpdate(let skipError):
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
                return .skippableGroupUpdate(latestSkipError)
            }
            return .messageFailure(partialErrors + [.archiveFrameError(.emptyGroupUpdate, interactionId)])
        }

        var groupChangeChatUpdate = BackupProto.GroupChangeChatUpdate()
        groupChangeChatUpdate.updates = updates

        if partialErrors.isEmpty {
            return .success(groupChangeChatUpdate)
        } else {
            return .partialFailure(groupChangeChatUpdate, partialErrors)
        }
    }

    func restoreChatItem(
        _ chatItem: BackupProto.ChatItem,
        thread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> MessageBackup.RestoreInteractionResult<Void> {
        let groupThread: TSGroupThread
        switch thread {
        case .contact:
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.groupUpdateMessageInNonGroupChat),
                chatItem.id
            )])
        case .groupV2(let tSGroupThread):
            groupThread = tSGroupThread
        }

        let groupUpdate: BackupProto.GroupChangeChatUpdate
        switch chatItem.item {
        case .updateMessage(let chatUpdateMessage):
            switch chatUpdateMessage.update {
            case .groupChange(let groupChangeChatUpdate):
                groupUpdate = groupChangeChatUpdate
            default:
                return .messageFailure([.restoreFrameError(
                    .developerError(OWSAssertionError("Got non group change update message in GroupUpdate archiver!")),
                    chatItem.id
                )])
            }
        default:
            return .messageFailure([.restoreFrameError(
                .developerError(OWSAssertionError("Got non update message in GroupUpdate archiver!")),
                chatItem.id
            )])
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
            tx: tx
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
        let infoMessage = TSInfoMessage.newGroupUpdateInfoMessage(
            timestamp: chatItem.dateSent,
            spamReportingMetadata: .unreportable,
            groupThread: groupThread,
            updateItems: persistableUpdates
        )
        interactionStore.insertInteraction(infoMessage, tx: tx)

        if partialErrors.isEmpty {
            return .success(())
        } else {
            return .partialRestore((), partialErrors)
        }
    }
}
