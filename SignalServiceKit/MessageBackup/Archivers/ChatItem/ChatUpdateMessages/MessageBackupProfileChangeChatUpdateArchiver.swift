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

    private let interactionStore: any InteractionStore

    init(interactionStore: any InteractionStore) {
        self.interactionStore = interactionStore
    }

    // MARK: -

    func archive(
        infoMessage: TSInfoMessage,
        thread: TSThread,
        context: MessageBackup.ChatArchivingContext,
        tx: any DBReadTransaction
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

        var chatUpdateMessage = BackupProto.ChatUpdateMessage()
        chatUpdateMessage.update = .profileChange(BackupProto.ProfileChangeChatUpdate(
            previousName: oldProfileName,
            newName: newProfileName
        ))

        let interactionArchiveDetails = Details(
            author: profileRecipientId,
            directionalDetails: .directionless(BackupProto.ChatItem.DirectionlessMessageDetails()),
            expireStartDate: nil,
            expiresInMs: nil,
            isSealedSender: false,
            chatItemType: .updateMessage(chatUpdateMessage)
        )

        return .success(interactionArchiveDetails)
    }

    // MARK: -

    func restoreProfileChangeChatUpdate(
        _ profileChangeChatUpdateProto: BackupProto.ProfileChangeChatUpdate,
        chatItem: BackupProto.ChatItem,
        chatThread: MessageBackup.ChatThread,
        context: MessageBackup.ChatRestoringContext,
        tx: any DBWriteTransaction
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

        let profileChangeInfoMessage = TSInfoMessage.makeForProfileChange(
            profileAddress: profileChangeAuthorContactAddress.asInteropAddress(),
            oldName: oldName,
            newName: newName,
            thread: chatThread.tsThread
        )
        interactionStore.insertInteraction(profileChangeInfoMessage, tx: tx)

        return .success(())
    }
}
