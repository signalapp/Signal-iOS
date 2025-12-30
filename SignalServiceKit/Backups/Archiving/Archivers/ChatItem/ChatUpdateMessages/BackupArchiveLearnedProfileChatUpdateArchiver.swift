//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

final class BackupArchiveLearnedProfileChatUpdateArchiver {
    typealias Details = BackupArchive.InteractionArchiveDetails
    typealias ArchiveChatUpdateMessageResult = BackupArchive.ArchiveInteractionResult<Details>
    typealias RestoreChatUpdateMessageResult = BackupArchive.RestoreInteractionResult<Void>

    private typealias ArchiveFrameError = BackupArchive.ArchiveFrameError<BackupArchive.InteractionUniqueId>
    private typealias RestoreFrameError = BackupArchive.RestoreFrameError<BackupArchive.ChatItemId>

    private let interactionStore: BackupArchiveInteractionStore

    init(interactionStore: BackupArchiveInteractionStore) {
        self.interactionStore = interactionStore
    }

    // MARK: -

    func archiveLearnedProfileChatUpdate(
        infoMessage: TSInfoMessage,
        threadInfo: BackupArchive.ChatArchivingContext.CachedThreadInfo,
        context: BackupArchive.ChatArchivingContext,
    ) -> ArchiveChatUpdateMessageResult {
        func messageFailure(
            _ errorType: ArchiveFrameError.ErrorType,
            line: UInt = #line,
        ) -> ArchiveChatUpdateMessageResult {
            return .messageFailure([.archiveFrameError(
                errorType,
                infoMessage.uniqueInteractionId,
                line: line,
            )])
        }

        guard let displayNameBeforeLearningProfileKey = infoMessage.displayNameBeforeLearningProfileName else {
            return messageFailure(.learnedProfileUpdateMissingPreviousName)
        }

        var learnedProfileChatUpdate = BackupProto_LearnedProfileChatUpdate()
        switch displayNameBeforeLearningProfileKey {
        case .phoneNumber(let phoneNumber):
            guard let e164 = E164(phoneNumber) else {
                return messageFailure(.learnedProfileUpdateInvalidE164)
            }

            learnedProfileChatUpdate.previousName = .e164(e164.uint64Value)
        case .username(let username):
            learnedProfileChatUpdate.previousName = .username(username)
        }

        var chatUpdateMessage = BackupProto_ChatUpdateMessage()
        chatUpdateMessage.update = .learnedProfileChange(learnedProfileChatUpdate)

        return Details.validateAndBuild(
            interactionUniqueId: infoMessage.uniqueInteractionId,
            author: .localUser,
            directionalDetails: .directionless(BackupProto_ChatItem.DirectionlessMessageDetails()),
            dateCreated: infoMessage.timestamp,
            expireStartDate: nil,
            expiresInMs: nil,
            isSealedSender: false,
            chatItemType: .updateMessage(chatUpdateMessage),
            isSmsPreviouslyRestoredFromBackup: false,
            threadInfo: threadInfo,
            pinMessageDetails: nil,
            context: context.recipientContext,
        )
    }

    // MARK: -

    func restoreLearnedProfileChatUpdate(
        _ learnedProfileUpdateProto: BackupProto_LearnedProfileChatUpdate,
        chatItem: BackupProto_ChatItem,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreChatUpdateMessageResult {
        func invalidProtoData(
            _ error: RestoreFrameError.ErrorType.InvalidProtoDataError,
            line: UInt = #line,
        ) -> RestoreChatUpdateMessageResult {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(error),
                chatItem.id,
                line: line,
            )])
        }

        guard case .contact(let contactThread) = chatThread.threadType else {
            return invalidProtoData(.learnedProfileUpdateNotFromContact)
        }

        let displayNameBefore: TSInfoMessage.DisplayNameBeforeLearningProfileName
        switch learnedProfileUpdateProto.previousName {
        case .e164(let uintValue):
            guard let e164 = E164(uintValue) else {
                return invalidProtoData(.invalidE164(protoClass: BackupProto_LearnedProfileChatUpdate.self))
            }

            displayNameBefore = .phoneNumber(e164.stringValue)
        case .username(let username):
            displayNameBefore = .username(username)
        case nil:
            // This isn't great, but we just use an empty username.
            displayNameBefore = .username("")
        }

        let learnedProfileKeyInfoMessage: TSInfoMessage = .makeForLearnedProfileName(
            contactThread: contactThread,
            timestamp: chatItem.dateSent,
            displayNameBefore: displayNameBefore,
        )

        do {
            try interactionStore.insert(
                learnedProfileKeyInfoMessage,
                in: chatThread,
                chatId: chatItem.typedChatId,
                context: context,
            )
        } catch let error {
            return .messageFailure([.restoreFrameError(.databaseInsertionFailed(error), chatItem.id)])
        }

        return .success(())
    }
}
