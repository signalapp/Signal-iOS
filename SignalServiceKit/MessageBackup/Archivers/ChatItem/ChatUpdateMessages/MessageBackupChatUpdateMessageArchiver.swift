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
    private let simpleChatUpdateArchiver: MessageBackupSimpleChatUpdateArchiver

    init(
        callRecordStore: any CallRecordStore,
        groupCallRecordManager: any GroupCallRecordManager,
        groupUpdateHelper: any GroupUpdateInfoMessageInserterBackupHelper,
        groupUpdateItemBuilder: any GroupUpdateItemBuilder,
        individualCallRecordManager: any IndividualCallRecordManager,
        interactionStore: any InteractionStore,
        threadStore: any ThreadStore
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
        simpleChatUpdateArchiver = MessageBackupSimpleChatUpdateArchiver(
            interactionStore: interactionStore,
            threadStore: threadStore
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

            switch infoMessage.messageType {
            case .typeGroupUpdate:
                return .skippableChatUpdate(.skippableGroupUpdate(.missingUpdateMetadata))
            case .userNotRegistered:
                return .skippableChatUpdate(.legacyInfoMessage(.userNotRegistered))
            case .typeUnsupportedMessage:
                return .skippableChatUpdate(.legacyInfoMessage(.typeUnsupportedMessage))
            case .typeGroupQuit:
                return .skippableChatUpdate(.legacyInfoMessage(.typeGroupQuit))
            case .addToContactsOffer:
                return .skippableChatUpdate(.legacyInfoMessage(.addToContactsOffer))
            case .addUserToProfileWhitelistOffer:
                return .skippableChatUpdate(.legacyInfoMessage(.addUserToProfileWhitelistOffer))
            case .addGroupToProfileWhitelistOffer:
                return .skippableChatUpdate(.legacyInfoMessage(.addGroupToProfileWhitelistOffer))
            case .syncedThread:
                return .skippableChatUpdate(.legacyInfoMessage(.syncedThread))
            case .recipientHidden:
                /// This info message type is handled specially.
                return .skippableChatUpdate(.contactHiddenInfoMessage)
            case
                    .verificationStateChange,
                    .typeSessionDidEnd,
                    .unknownProtocolVersion,
                    .userJoinedSignal,
                    .phoneNumberChange,
                    .paymentsActivationRequest,
                    .paymentsActivated,
                    .reportedSpam:
                /// These info message types map to simple chat updates.
                return simpleChatUpdateArchiver.archiveSimpleChatUpdate(
                    infoMessage: infoMessage,
                    context: context,
                    tx: tx
                )
            case
                    .typeDisappearingMessagesUpdate,
                    .profileUpdate,
                    .threadMerge,
                    .sessionSwitchover:
                // TODO: [Backups] Add support for "non-simple" chat updates.
                return .notYetImplemented
            }
        } else if let errorMessage = interaction as? TSErrorMessage {
            /// All `TSErrorMessage`s map to simple chat updates.
            return simpleChatUpdateArchiver.archiveSimpleChatUpdate(
                errorMessage: errorMessage,
                context: context,
                tx: tx
            )
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
            return simpleChatUpdateArchiver.restoreSimpleChatUpdate(
                simpleChatUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
                tx: tx
            )
        case .expirationTimerChange(let expirationTimerUpdateProto):
            return .messageFailure([.restoreFrameError(.unimplemented, chatItem.id)])
        case .profileChange(let profileChangeUpdateProto):
            return .messageFailure([.restoreFrameError(.unimplemented, chatItem.id)])
        case .threadMerge(let threadMergeUpdateProto):
            return .messageFailure([.restoreFrameError(.unimplemented, chatItem.id)])
        case .sessionSwitchover(let sessionSwitchoverUpdateProto):
            return .messageFailure([.restoreFrameError(.unimplemented, chatItem.id)])
        case .learnedProfileChange(let learnedProfileChangeProto):
            return .messageFailure([.restoreFrameError(.unimplemented, chatItem.id)])
        }
    }
}
