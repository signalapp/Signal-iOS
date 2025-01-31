//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

final class MessageBackupChatUpdateMessageArchiver: MessageBackupProtoArchiver {
    typealias Details = MessageBackup.InteractionArchiveDetails
    typealias ArchiveChatUpdateMessageResult = MessageBackup.ArchiveInteractionResult<Details>
    typealias RestoreChatUpdateMessageResult = MessageBackup.RestoreInteractionResult<Void>

    private let expirationTimerChatUpdateArchiver: MessageBackupExpirationTimerChatUpdateArchiver
    private let groupCallArchiver: MessageBackupGroupCallArchiver
    private let groupUpdateMessageArchiver: MessageBackupGroupUpdateMessageArchiver
    private let individualCallArchiver: MessageBackupIndividualCallArchiver
    private let learnedProfileChatUpdateArchiver: MessageBackupLearnedProfileChatUpdateArchiver
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
        interactionStore: MessageBackupInteractionStore
    ) {
        groupUpdateMessageArchiver = MessageBackupGroupUpdateMessageArchiver(
            groupUpdateBuilder: groupUpdateItemBuilder,
            groupUpdateHelper: groupUpdateHelper,
            interactionStore: interactionStore
        )
        expirationTimerChatUpdateArchiver = MessageBackupExpirationTimerChatUpdateArchiver(
            contactManager: contactManager,
            groupUpdateArchiver: groupUpdateMessageArchiver,
            interactionStore: interactionStore
        )
        groupCallArchiver = MessageBackupGroupCallArchiver(
            callRecordStore: callRecordStore,
            groupCallRecordManager: groupCallRecordManager,
            interactionStore: interactionStore
        )
        individualCallArchiver = MessageBackupIndividualCallArchiver(
            callRecordStore: callRecordStore,
            individualCallRecordManager: individualCallRecordManager,
            interactionStore: interactionStore
        )
        learnedProfileChatUpdateArchiver = MessageBackupLearnedProfileChatUpdateArchiver(
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

    func archiveIndividualCall(
        _ individualCallInteraction: TSCall,
        threadInfo: MessageBackup.ChatArchivingContext.CachedThreadInfo,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveChatUpdateMessageResult {
        return individualCallArchiver.archiveIndividualCall(
            individualCallInteraction,
            threadInfo: threadInfo,
            context: context
        )
    }

    func archiveGroupCall(
        _ groupCallInteraction: OWSGroupCallMessage,
        threadInfo: MessageBackup.ChatArchivingContext.CachedThreadInfo,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveChatUpdateMessageResult {
        return groupCallArchiver.archiveGroupCall(
            groupCallInteraction,
            threadInfo: threadInfo,
            context: context
        )
    }

    func archiveErrorMessage(
        _ errorMessage: TSErrorMessage,
        threadInfo: MessageBackup.ChatArchivingContext.CachedThreadInfo,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveChatUpdateMessageResult {
        /// All `TSErrorMessage`s map to simple chat updates.
        return simpleChatUpdateArchiver.archiveSimpleChatUpdate(
            errorMessage: errorMessage,
            threadInfo: threadInfo,
            context: context
        )
    }

    func archiveInfoMessage(
        _ infoMessage: TSInfoMessage,
        threadInfo: MessageBackup.ChatArchivingContext.CachedThreadInfo,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveChatUpdateMessageResult {
        switch infoMessage.groupUpdateMetadata(
            localIdentifiers: context.recipientContext.localIdentifiers
        ) {
        case .legacyRawString:
            // These will be dropped by the group update message archiver.
            fallthrough
        case .precomputed, .modelDiff, .newGroup:
            return groupUpdateMessageArchiver.archiveGroupUpdate(
                infoMessage: infoMessage,
                threadInfo: threadInfo,
                context: context
            )
        case .nonGroupUpdate:
            break
        }

        switch infoMessage.messageType {
        case .typeGroupUpdate:
            return .skippableInteraction(.skippableGroupUpdate(.missingUpdateMetadata))
        case .userNotRegistered:
            return .skippableInteraction(.legacyInfoMessage(.userNotRegistered))
        case .typeUnsupportedMessage:
            return .skippableInteraction(.legacyInfoMessage(.typeUnsupportedMessage))
        case .typeGroupQuit:
            return .skippableInteraction(.legacyInfoMessage(.typeGroupQuit))
        case .addToContactsOffer:
            return .skippableInteraction(.legacyInfoMessage(.addToContactsOffer))
        case .addUserToProfileWhitelistOffer:
            return .skippableInteraction(.legacyInfoMessage(.addUserToProfileWhitelistOffer))
        case .addGroupToProfileWhitelistOffer:
            return .skippableInteraction(.legacyInfoMessage(.addGroupToProfileWhitelistOffer))
        case .syncedThread:
            return .skippableInteraction(.legacyInfoMessage(.syncedThread))
        case .recipientHidden:
            /// This info message type is handled specially.
            return .skippableInteraction(.contactHiddenInfoMessage)
        case
                .verificationStateChange,
                .typeLocalUserEndedSession,
                .typeRemoteUserEndedSession,
                .unknownProtocolVersion,
                .userJoinedSignal,
                .phoneNumberChange,
                .paymentsActivationRequest,
                .paymentsActivated,
                .reportedSpam,
                .blockedOtherUser,
                .blockedGroup,
                .unblockedOtherUser,
                .unblockedGroup,
                .acceptedMessageRequest:
            /// These info message types map to simple chat updates.
            return simpleChatUpdateArchiver.archiveSimpleChatUpdate(
                infoMessage: infoMessage,
                threadInfo: threadInfo,
                context: context
            )
        case .profileUpdate:
            return profileChangeChatUpdateArchiver.archive(
                infoMessage: infoMessage,
                threadInfo: threadInfo,
                context: context
            )
        case .typeDisappearingMessagesUpdate:
            return expirationTimerChatUpdateArchiver.archiveExpirationTimerChatUpdate(
                infoMessage: infoMessage,
                threadInfo: threadInfo,
                context: context
            )
        case .threadMerge:
            return threadMergeChatUpdateArchiver.archiveThreadMergeChatUpdate(
                infoMessage: infoMessage,
                threadInfo: threadInfo,
                context: context
            )
        case .sessionSwitchover:
            return sessionSwitchoverChatUpdateArchiver.archiveSessionSwitchoverChatUpdate(
                infoMessage: infoMessage,
                threadInfo: threadInfo,
                context: context
            )
        case .learnedProfileName:
            return learnedProfileChatUpdateArchiver.archiveLearnedProfileChatUpdate(
                infoMessage: infoMessage,
                threadInfo: threadInfo,
                context: context
            )
        }
    }

    // MARK: -

    func restoreChatItem(
        _ chatItem: BackupProto_ChatItem,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreChatUpdateMessageResult {
        let chatUpdateMessage: BackupProto_ChatUpdateMessage
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
            return .unrecognizedEnum(MessageBackup.UnrecognizedEnumError(
                enumType: BackupProto_ChatUpdateMessage.OneOf_Update.self
            ))
        case .groupChange(let groupChangeChatUpdateProto):
            return groupUpdateMessageArchiver.restoreGroupUpdate(
                groupChangeChatUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context
            )
        case .individualCall(let individualCallProto):
            return individualCallArchiver.restoreIndividualCall(
                individualCallProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context
            )
        case .groupCall(let groupCallProto):
            return groupCallArchiver.restoreGroupCall(
                groupCallProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context
            )
        case .simpleUpdate(let simpleChatUpdateProto):
            return simpleChatUpdateArchiver.restoreSimpleChatUpdate(
                simpleChatUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context
            )
        case .expirationTimerChange(let expirationTimerUpdateProto):
            return expirationTimerChatUpdateArchiver.restoreExpirationTimerChatUpdate(
                expirationTimerUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context
            )
        case .profileChange(let profileChangeUpdateProto):
            return profileChangeChatUpdateArchiver.restoreProfileChangeChatUpdate(
                profileChangeUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context
            )
        case .threadMerge(let threadMergeUpdateProto):
            return threadMergeChatUpdateArchiver.restoreThreadMergeChatUpdate(
                threadMergeUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context
            )
        case .sessionSwitchover(let sessionSwitchoverUpdateProto):
            return sessionSwitchoverChatUpdateArchiver.restoreSessionSwitchoverChatUpdate(
                sessionSwitchoverUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context
            )
        case .learnedProfileChange(let learnedProfileChangeProto):
            return learnedProfileChatUpdateArchiver.restoreLearnedProfileChatUpdate(
                learnedProfileChangeProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context
            )
        }
    }
}
