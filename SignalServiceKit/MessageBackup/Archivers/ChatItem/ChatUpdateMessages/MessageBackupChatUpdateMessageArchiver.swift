//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

final class MessageBackupChatUpdateMessageArchiver: MessageBackupInteractionArchiver {
    typealias ArchiveChatUpdateMessageResult = MessageBackup.ArchiveInteractionResult<Details>
    typealias RestoreChatUpdateMessageResult = MessageBackup.RestoreInteractionResult<Void>

    static var archiverType: MessageBackup.ChatItemArchiverType { .chatUpdateMessage }

    private let expirationTimerChatUpdateArchiver: MessageBackupExpirationTimerChatUpdateArchiver
    private let groupCallArchiver: MessageBackupGroupCallArchiver
    private let groupUpdateMessageArchiver: MessageBackupGroupUpdateMessageArchiver
    private let individualCallArchiver: MessageBackupIndividualCallArchiver
    private let profileChangeChatUpdateArchiver: MessageBackupProfileChangeChatUpdateArchiver
    private let sessionSwitchoverChatUpdateArchiver: MessageBackupSessionSwitchoverChatUpdateArchiver
    private let simpleChatUpdateArchiver: MessageBackupSimpleChatUpdateArchiver
    private let threadMergeChatUpdateArchiver: MessageBackupThreadMergeChatUpdateArchiver

    init(
        callRecordStore: any CallRecordStore,
        contactManager: any MessageBackup.Shims.ContactManager,
        groupCallRecordManager: any GroupCallRecordManager,
        groupUpdateHelper: any GroupUpdateInfoMessageInserterBackupHelper,
        groupUpdateItemBuilder: any GroupUpdateItemBuilder,
        individualCallRecordManager: any IndividualCallRecordManager,
        interactionStore: any InteractionStore
    ) {
        expirationTimerChatUpdateArchiver = MessageBackupExpirationTimerChatUpdateArchiver(
            contactManager: contactManager,
            interactionStore: interactionStore
        )
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
        profileChangeChatUpdateArchiver = MessageBackupProfileChangeChatUpdateArchiver(
            interactionStore: interactionStore
        )
        sessionSwitchoverChatUpdateArchiver = MessageBackupSessionSwitchoverChatUpdateArchiver(
            interactionStore: interactionStore
        )
        simpleChatUpdateArchiver = MessageBackupSimpleChatUpdateArchiver(
            interactionStore: interactionStore
        )
        threadMergeChatUpdateArchiver = MessageBackupThreadMergeChatUpdateArchiver(
            interactionStore: interactionStore
        )
    }

    // MARK: -

    func archiveInteraction(
        _ interaction: TSInteraction,
        thread: TSThread,
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
                    thread: thread,
                    context: context,
                    tx: tx
                )
            case .profileUpdate:
                return profileChangeChatUpdateArchiver.archive(
                    infoMessage: infoMessage,
                    thread: thread,
                    context: context,
                    tx: tx
                )
            case .typeDisappearingMessagesUpdate:
                return expirationTimerChatUpdateArchiver.archiveExpirationTimerChatUpdate(
                    infoMessage: infoMessage,
                    thread: thread,
                    context: context,
                    tx: tx
                )
            case .threadMerge:
                return threadMergeChatUpdateArchiver.archive(
                    infoMessage: infoMessage,
                    thread: thread,
                    context: context,
                    tx: tx
                )
            case .sessionSwitchover:
                return sessionSwitchoverChatUpdateArchiver.archive(
                    infoMessage: infoMessage,
                    thread: thread,
                    context: context,
                    tx: tx
                )
            }
        } else if let errorMessage = interaction as? TSErrorMessage {
            /// All `TSErrorMessage`s map to simple chat updates.
            return simpleChatUpdateArchiver.archiveSimpleChatUpdate(
                errorMessage: errorMessage,
                thread: thread,
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
            return expirationTimerChatUpdateArchiver.restoreExpirationTimerChatUpdate(
                expirationTimerUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
                tx: tx
            )
        case .profileChange(let profileChangeUpdateProto):
            return profileChangeChatUpdateArchiver.restoreProfileChangeChatUpdate(
                profileChangeUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
                tx: tx
            )
        case .threadMerge(let threadMergeUpdateProto):
            return threadMergeChatUpdateArchiver.restoreThreadMergeChatUpdate(
                threadMergeUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
                tx: tx
            )
        case .sessionSwitchover(let sessionSwitchoverUpdateProto):
            return sessionSwitchoverChatUpdateArchiver.restoreSessionSwitchoverChatUpdate(
                sessionSwitchoverUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
                tx: tx
            )
        case .learnedProfileChange(let learnedProfileChangeProto):
            return .messageFailure([.restoreFrameError(.unimplemented, chatItem.id)])
        }
    }
}
