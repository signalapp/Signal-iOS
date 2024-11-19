//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

final class MessageBackupProfileChangeChatUpdateArchiver {
    typealias Details = MessageBackup.InteractionArchiveDetails
    typealias ArchiveChatUpdateMessageResult = MessageBackup.ArchiveInteractionResult<Details>
    typealias RestoreChatUpdateMessageResult = MessageBackup.RestoreInteractionResult<Void>

    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>
    private typealias RestoreFrameError = MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>

    private let interactionStore: MessageBackupInteractionStore

    init(interactionStore: MessageBackupInteractionStore) {
        self.interactionStore = interactionStore
    }

    // MARK: -

    func archive(
        infoMessage: TSInfoMessage,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveChatUpdateMessageResult {
        func messageFailure(
            _ errorType: ArchiveFrameError.ErrorType,
            line: UInt = #line
        ) -> ArchiveChatUpdateMessageResult {
            return .messageFailure([.archiveFrameError(
                errorType,
                infoMessage.uniqueInteractionId,
                line: line
            )])
        }

        guard let profileAddress = infoMessage.profileChangeAddress?.asSingleServiceIdBackupAddress() else {
            return messageFailure(.profileChangeUpdateMissingAuthor)
        }

        guard let profileRecipientId = context.recipientContext[.contact(profileAddress)] else {
            return messageFailure(.referencedRecipientIdMissing(.contact(profileAddress)))
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

        let interactionArchiveDetails = Details(
            author: profileRecipientId,
            directionalDetails: .directionless(BackupProto_ChatItem.DirectionlessMessageDetails()),
            dateCreated: infoMessage.timestamp,
            expireStartDate: nil,
            expiresInMs: nil,
            isSealedSender: false,
            chatItemType: .updateMessage(chatUpdateMessage),
            isSmsPreviouslyRestoredFromBackup: false
        )

        return .success(interactionArchiveDetails)
    }

    // MARK: -

    func restoreProfileChangeChatUpdate(
        _ profileChangeChatUpdateProto: BackupProto_ProfileChangeChatUpdate,
        chatItem: BackupProto_ChatItem,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreChatUpdateMessageResult {
        func invalidProtoData(
            _ error: RestoreFrameError.ErrorType.InvalidProtoDataError,
            line: UInt = #line
        ) -> RestoreChatUpdateMessageResult {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(error),
                chatItem.id,
                line: line
            )])
        }

        let oldName = profileChangeChatUpdateProto.previousName.filterForDisplay
        let newName = profileChangeChatUpdateProto.newName.filterForDisplay

        guard !oldName.isEmpty, !newName.isEmpty else {
            return invalidProtoData(.profileChangeUpdateInvalidNames)
        }

        guard
            let profileChangeAuthor = context.recipientContext[chatItem.authorRecipientId],
            case .contact(let profileChangeAuthorContactAddress) = profileChangeAuthor
        else {
            return invalidProtoData(.profileChangeUpdateNotFromContact)
        }

        let profileChangeInfoMessage: TSInfoMessage = .makeForProfileChange(
            thread: chatThread.tsThread,
            timestamp: chatItem.dateSent,
            profileChanges: ProfileChanges(
                address: profileChangeAuthorContactAddress.asInteropAddress(),
                oldNameLiteral: oldName,
                newNameLiteral: newName
            )
        )

        guard let directionalDetails = chatItem.directionalDetails else {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.chatItemMissingDirectionalDetails),
                chatItem.id
            )])
        }

        do {
            try interactionStore.insert(
                profileChangeInfoMessage,
                in: chatThread,
                chatId: chatItem.typedChatId,
                directionalDetails: directionalDetails,
                context: context
            )
        } catch let error {
            return .messageFailure([.restoreFrameError(.databaseInsertionFailed(error), chatItem.id)])
        }

        return .success(())
    }
}
