//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

final class BackupArchiveProfileChangeChatUpdateArchiver {
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

    func archive(
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

        guard let profileAddress = infoMessage.profileChangeAddress?.asSingleServiceIdBackupAddress() else {
            return messageFailure(.profileChangeUpdateMissingAuthor)
        }

        guard
            let oldProfileName: String = infoMessage.profileChangesOldFullName,
            let newProfileName: String = infoMessage.profileChangesNewFullName
        else {
            return messageFailure(.profileChangeUpdateMissingNames)
        }

        var profileChangeChatUpdate = BackupProto_ProfileChangeChatUpdate()
        profileChangeChatUpdate.previousName = oldProfileName
        profileChangeChatUpdate.newName = newProfileName

        var chatUpdateMessage = BackupProto_ChatUpdateMessage()
        chatUpdateMessage.update = .profileChange(profileChangeChatUpdate)

        return Details.validateAndBuild(
            interactionUniqueId: infoMessage.uniqueInteractionId,
            author: .contact(profileAddress),
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

    func restoreProfileChangeChatUpdate(
        _ profileChangeChatUpdateProto: BackupProto_ProfileChangeChatUpdate,
        chatItem: BackupProto_ChatItem,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext,
    ) -> RestoreChatUpdateMessageResult {
        let oldName = profileChangeChatUpdateProto.previousName
        let newName = profileChangeChatUpdateProto.newName

        guard
            let profileChangeAuthor = context.recipientContext[chatItem.authorRecipientId],
            case .contact(let profileChangeAuthorContactAddress) = profileChangeAuthor
        else {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.profileChangeUpdateNotFromContact),
                chatItem.id,
            )])
        }

        let profileChangeInfoMessage: TSInfoMessage = .makeForProfileChange(
            thread: chatThread.tsThread,
            timestamp: chatItem.dateSent,
            profileChanges: ProfileChanges(
                address: profileChangeAuthorContactAddress.asInteropAddress(),
                oldNameLiteral: oldName,
                newNameLiteral: newName,
            ),
        )

        do {
            try interactionStore.insert(
                profileChangeInfoMessage,
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
