//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

final class MessageBackupChatUpdateMessageArchiver: MessageBackupInteractionArchiver {
    typealias ArchiveChatUpdateMessageResult = MessageBackup.ArchiveInteractionResult<Details>
    typealias RestoreChatUpdateMessageResult = MessageBackup.RestoreInteractionResult<Void>

    static var archiverType: MessageBackup.ChatItemArchiverType { .chatUpdateMessage }

    private let groupCallArchiver: MessageBackupGroupCallArchiver
    private let groupUpdateMessageArchiver: MessageBackupGroupUpdateMessageArchiver
    private let individualCallArchiver: MessageBackupIndividualCallArchiver

    init(
        callRecordStore: any CallRecordStore,
        groupCallRecordManager: any GroupCallRecordManager,
        groupUpdateHelper: any GroupUpdateInfoMessageInserterBackupHelper,
        groupUpdateItemBuilder: any GroupUpdateItemBuilder,
        individualCallRecordManager: any IndividualCallRecordManager,
        interactionStore: any InteractionStore
    ) {
        groupCallArchiver = MessageBackupGroupCallArchiver(
            callRecordStore: callRecordStore,
            groupCallRecordManager: groupCallRecordManager,
            interactionStore: interactionStore
        )
        groupUpdateMessageArchiver = MessageBackupGroupUpdateMessageArchiver(
            groupUpdateBuilder: groupUpdateItemBuilder,
            groupUpdateHelper: groupUpdateHelper,
            interactionStore: interactionStore
        )
        individualCallArchiver = MessageBackupIndividualCallArchiver(
            callRecordStore: callRecordStore,
            individualCallRecordManager: individualCallRecordManager,
            interactionStore: interactionStore
        )
    }

    // MARK: -

    func archiveInteraction(
        _ interaction: TSInteraction,
        context: MessageBackup.ChatArchivingContext,
        tx: any DBReadTransaction
    ) -> ArchiveChatUpdateMessageResult {
        if let individualCallInteraction = interaction as? TSCall {
            return individualCallArchiver.archiveIndividualCall(
                individualCallInteraction,
                context: context,
                tx: tx
            )
        } else if let groupCallInteraction = interaction as? OWSGroupCallMessage {
            return groupCallArchiver.archiveGroupCall(
                groupCallInteraction,
                context: context,
                tx: tx
            )
        } else if let infoMessage = interaction as? TSInfoMessage {
            switch infoMessage.groupUpdateMetadata(
                localIdentifiers: context.recipientContext.localIdentifiers
            ) {
            case .legacyRawString:
                // These will be dropped by the group update message archiver.
                fallthrough
            case .precomputed, .modelDiff, .newGroup:
                return groupUpdateMessageArchiver.archiveGroupUpdate(
                    infoMessage: infoMessage,
                    context: context,
                    tx: tx
                )
            case .nonGroupUpdate:
                break
            }

            owsFail("Generic TSInfoMessage archive not yet implemented!")
        } else if let errorMessage = interaction as? TSErrorMessage {
            owsFail("Generic TSErrorMessage archive not yet implemented!")
        } else {
            return .completeFailure(.fatalArchiveError(
                .developerError(OWSAssertionError("Invalid interaction type!"))
            ))
        }
    }

    // MARK: -

    func restoreChatItem(
        _ chatItem: BackupProto.ChatItem,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: any DBWriteTransaction
    ) -> RestoreChatUpdateMessageResult {
        let chatUpdateMessage: BackupProto.ChatUpdateMessage
        do {
            switch chatItem.item {
            case .updateMessage(let updateMessage):
                chatUpdateMessage = updateMessage
            default:
                return .messageFailure([.restoreFrameError(
                    .developerError(OWSAssertionError("Non-chat update!")),
                    chatItem.id
                )])
            }
        }

        switch chatUpdateMessage.update {
        case nil:
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.emptyChatUpdateMessage),
                chatItem.id
            )])
        case .groupChange(let groupChangeChatUpdateProto):
            return groupUpdateMessageArchiver.restoreGroupUpdate(
                groupChangeChatUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
                tx: tx
            )
        case .individualCall(let individualCallProto):
            return individualCallArchiver.restoreIndividualCall(
                individualCallProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
                tx: tx
            )
        case .groupCall(let groupCallProto):
            return groupCallArchiver.restoreGroupCall(
                groupCallProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
                tx: tx
            )
        case .simpleUpdate(let simpleChatUpdateProto):
            owsFail("Not yet implemented!")
        case .expirationTimerChange(let expirationTimerUpdateProto):
            owsFail("Not yet implemented!")
        case .profileChange(let profileChangeUpdateProto):
            owsFail("Not yet implemented!")
        case .threadMerge(let threadMergeUpdateProto):
            owsFail("Not yet implemented!")
        case .sessionSwitchover(let sessionSwitchoverUpdateProto):
            owsFail("Not yet implemented!")
        case .learnedProfileChange(let learnedProfileChangeProto):
            owsFail("Not yet implemented!")
        }
    }
}
