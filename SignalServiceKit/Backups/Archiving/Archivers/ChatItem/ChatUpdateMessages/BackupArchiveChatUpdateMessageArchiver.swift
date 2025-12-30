//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

final class BackupArchiveChatUpdateMessageArchiver: BackupArchiveProtoStreamWriter {
    typealias Details = BackupArchive.InteractionArchiveDetails
    typealias ArchiveChatUpdateMessageResult = BackupArchive.ArchiveInteractionResult<Details>
    typealias RestoreChatUpdateMessageResult = BackupArchive.RestoreInteractionResult<Void>

    private let expirationTimerChatUpdateArchiver: BackupArchiveExpirationTimerChatUpdateArchiver
    private let groupCallArchiver: BackupArchiveGroupCallArchiver
    private let groupUpdateMessageArchiver: BackupArchiveGroupUpdateMessageArchiver
    private let individualCallArchiver: BackupArchiveIndividualCallArchiver
    private let learnedProfileChatUpdateArchiver: BackupArchiveLearnedProfileChatUpdateArchiver
    private let profileChangeChatUpdateArchiver: BackupArchiveProfileChangeChatUpdateArchiver
    private let sessionSwitchoverChatUpdateArchiver: BackupArchiveSessionSwitchoverChatUpdateArchiver
    private let simpleChatUpdateArchiver: BackupArchiveSimpleChatUpdateArchiver
    private let threadMergeChatUpdateArchiver: BackupArchiveThreadMergeChatUpdateArchiver
    private let pollTerminatedChatUpdateArchiver: BackupArchivePollTerminateChatUpdateArchiver
    private let pinMessageChatUpdateArchiver: BackupArchivePinMessageChatUpdateArchiver

    init(
        callRecordStore: any CallRecordStore,
        contactManager: any BackupArchive.Shims.ContactManager,
        groupCallRecordManager: any GroupCallRecordManager,
        groupUpdateItemBuilder: any GroupUpdateItemBuilder,
        individualCallRecordManager: any IndividualCallRecordManager,
        interactionStore: BackupArchiveInteractionStore,
    ) {
        groupUpdateMessageArchiver = BackupArchiveGroupUpdateMessageArchiver(
            groupUpdateBuilder: groupUpdateItemBuilder,
            interactionStore: interactionStore,
        )
        expirationTimerChatUpdateArchiver = BackupArchiveExpirationTimerChatUpdateArchiver(
            contactManager: contactManager,
            groupUpdateArchiver: groupUpdateMessageArchiver,
            interactionStore: interactionStore,
        )
        groupCallArchiver = BackupArchiveGroupCallArchiver(
            callRecordStore: callRecordStore,
            groupCallRecordManager: groupCallRecordManager,
            interactionStore: interactionStore,
        )
        individualCallArchiver = BackupArchiveIndividualCallArchiver(
            callRecordStore: callRecordStore,
            individualCallRecordManager: individualCallRecordManager,
            interactionStore: interactionStore,
        )
        learnedProfileChatUpdateArchiver = BackupArchiveLearnedProfileChatUpdateArchiver(
            interactionStore: interactionStore,
        )
        profileChangeChatUpdateArchiver = BackupArchiveProfileChangeChatUpdateArchiver(
            interactionStore: interactionStore,
        )
        sessionSwitchoverChatUpdateArchiver = BackupArchiveSessionSwitchoverChatUpdateArchiver(
            interactionStore: interactionStore,
        )
        simpleChatUpdateArchiver = BackupArchiveSimpleChatUpdateArchiver(
            interactionStore: interactionStore,
        )
        threadMergeChatUpdateArchiver = BackupArchiveThreadMergeChatUpdateArchiver(
            interactionStore: interactionStore,
        )
        pollTerminatedChatUpdateArchiver = BackupArchivePollTerminateChatUpdateArchiver(
            interactionStore: interactionStore,
        )
        pinMessageChatUpdateArchiver = BackupArchivePinMessageChatUpdateArchiver(
            interactionStore: interactionStore,
        )
    }

    // MARK: -

    func archiveIndividualCall(
        _ individualCallInteraction: TSCall,
        threadInfo: BackupArchive.ChatArchivingContext.CachedThreadInfo,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveChatUpdateMessageResult {
        return individualCallArchiver.archiveIndividualCall(
            individualCallInteraction,
            threadInfo: threadInfo,
            context: context,
        )
    }

    func archiveGroupCall(
        _ groupCallInteraction: OWSGroupCallMessage,
        threadInfo: BackupArchive.ChatArchivingContext.CachedThreadInfo,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveChatUpdateMessageResult {
        return groupCallArchiver.archiveGroupCall(
            groupCallInteraction,
            threadInfo: threadInfo,
            context: context,
        )
    }

    func archiveErrorMessage(
        _ errorMessage: TSErrorMessage,
        threadInfo: BackupArchive.ChatArchivingContext.CachedThreadInfo,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveChatUpdateMessageResult {
        /// All `TSErrorMessage`s map to simple chat updates.
        return simpleChatUpdateArchiver.archiveSimpleChatUpdate(
            errorMessage: errorMessage,
            threadInfo: threadInfo,
            context: context,
        )
    }

    func archiveInfoMessage(
        _ infoMessage: TSInfoMessage,
        threadInfo: BackupArchive.ChatArchivingContext.CachedThreadInfo,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveChatUpdateMessageResult {
        switch infoMessage.groupUpdateMetadata(
            localIdentifiers: context.recipientContext.localIdentifiers,
        ) {
        case .legacyRawString:
            // These will be dropped by the group update message archiver.
            fallthrough
        case .precomputed, .modelDiff, .newGroup:
            return groupUpdateMessageArchiver.archiveGroupUpdate(
                infoMessage: infoMessage,
                threadInfo: threadInfo,
                context: context,
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
                context: context,
            )
        case .profileUpdate:
            return profileChangeChatUpdateArchiver.archive(
                infoMessage: infoMessage,
                threadInfo: threadInfo,
                context: context,
            )
        case .typeDisappearingMessagesUpdate:
            return expirationTimerChatUpdateArchiver.archiveExpirationTimerChatUpdate(
                infoMessage: infoMessage,
                threadInfo: threadInfo,
                context: context,
            )
        case .threadMerge:
            return threadMergeChatUpdateArchiver.archiveThreadMergeChatUpdate(
                infoMessage: infoMessage,
                threadInfo: threadInfo,
                context: context,
            )
        case .sessionSwitchover:
            return sessionSwitchoverChatUpdateArchiver.archiveSessionSwitchoverChatUpdate(
                infoMessage: infoMessage,
                threadInfo: threadInfo,
                context: context,
            )
        case .learnedProfileName:
            return learnedProfileChatUpdateArchiver.archiveLearnedProfileChatUpdate(
                infoMessage: infoMessage,
                threadInfo: threadInfo,
                context: context,
            )
        case .typeEndPoll:
            return pollTerminatedChatUpdateArchiver.archivePollTerminateChatUpdate(
                infoMessage: infoMessage,
                threadInfo: threadInfo,
                context: context,
            )
        case .typePinnedMessage:
            return pinMessageChatUpdateArchiver.archivePinMessageChatUpdate(
                infoMessage: infoMessage,
                threadInfo: threadInfo,
                context: context,
            )
        }
    }

    // MARK: -

    func restoreChatItem(
        _ chatItem: BackupProto_ChatItem,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreChatUpdateMessageResult {
        let chatUpdateMessage: BackupProto_ChatUpdateMessage
        do {
            switch chatItem.item {
            case .updateMessage(let updateMessage):
                chatUpdateMessage = updateMessage
            default:
                return .messageFailure([.restoreFrameError(
                    .developerError(OWSAssertionError("Non-chat update!")),
                    chatItem.id,
                )])
            }
        }

        switch chatUpdateMessage.update {
        case nil:
            return .unrecognizedEnum(BackupArchive.UnrecognizedEnumError(
                enumType: BackupProto_ChatUpdateMessage.OneOf_Update.self,
            ))
        case .groupChange(let groupChangeChatUpdateProto):
            return groupUpdateMessageArchiver.restoreGroupUpdate(
                groupChangeChatUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
            )
        case .individualCall(let individualCallProto):
            return individualCallArchiver.restoreIndividualCall(
                individualCallProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
            )
        case .groupCall(let groupCallProto):
            return groupCallArchiver.restoreGroupCall(
                groupCallProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
            )
        case .simpleUpdate(let simpleChatUpdateProto):
            return simpleChatUpdateArchiver.restoreSimpleChatUpdate(
                simpleChatUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
            )
        case .expirationTimerChange(let expirationTimerUpdateProto):
            return expirationTimerChatUpdateArchiver.restoreExpirationTimerChatUpdate(
                expirationTimerUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
            )
        case .profileChange(let profileChangeUpdateProto):
            return profileChangeChatUpdateArchiver.restoreProfileChangeChatUpdate(
                profileChangeUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
            )
        case .threadMerge(let threadMergeUpdateProto):
            return threadMergeChatUpdateArchiver.restoreThreadMergeChatUpdate(
                threadMergeUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
            )
        case .sessionSwitchover(let sessionSwitchoverUpdateProto):
            return sessionSwitchoverChatUpdateArchiver.restoreSessionSwitchoverChatUpdate(
                sessionSwitchoverUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
            )
        case .learnedProfileChange(let learnedProfileChangeProto):
            return learnedProfileChatUpdateArchiver.restoreLearnedProfileChatUpdate(
                learnedProfileChangeProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
            )
        case .pollTerminate(let pollTerminateUpdateProto):
            return pollTerminatedChatUpdateArchiver.restorePollTerminateChatUpdate(
                pollTerminateUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
            )
        case .pinMessage(let pinMessageUpdateProto):
            return pinMessageChatUpdateArchiver.restorePinMessageChatUpdate(
                pinMessageUpdateProto,
                chatItem: chatItem,
                chatThread: chatThread,
                context: context,
            )
        }
    }
}
