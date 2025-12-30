//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

final class BackupArchivePollTerminateChatUpdateArchiver {
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

    func archivePollTerminateChatUpdate(
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

        guard let endPollItem: PersistableEndPollItem = infoMessage.infoMessageValue(forKey: .endPoll) else {
            return messageFailure(.pollEndMissingPersistableData)
        }

        guard let question = endPollItem.question else {
            return messageFailure(.pollEndMissingQuestion)
        }

        let chatUpdateAuthorAddress: BackupArchive.InteractionArchiveDetails.AuthorAddress
        do {
            chatUpdateAuthorAddress = BackupArchive.InteractionArchiveDetails.AuthorAddress.contact(
                BackupArchive.ContactAddress(
                    aci: try Aci.parseFrom(
                        serviceIdBinary: endPollItem.authorServiceIdBinary,
                    ),
                ),
            )
        } catch {
            return messageFailure(.endPollUpdateInvalidAuthorAci)
        }

        var pollTerminateChatUpdate = BackupProto_PollTerminateUpdate()
        pollTerminateChatUpdate.question = question
        pollTerminateChatUpdate.targetSentTimestamp = UInt64(endPollItem.timestamp)

        var chatUpdateMessage = BackupProto_ChatUpdateMessage()
        chatUpdateMessage.update = .pollTerminate(pollTerminateChatUpdate)

        return Details.validateAndBuild(
            interactionUniqueId: infoMessage.uniqueInteractionId,
            author: chatUpdateAuthorAddress,
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

    func restorePollTerminateChatUpdate(
        _ pollTerminateUpdateProto: BackupProto_PollTerminateUpdate,
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

        guard case .groupV2(let groupThread) = chatThread.threadType else {
            return invalidProtoData(.pollTerminateNotFromGroupChat)
        }

        let recipientId = BackupArchive.RecipientId(value: chatItem.authorID)
        let authorAddress: BackupArchive.InteropAddress
        switch context.recipientContext[recipientId] {
        case .localAddress:
            authorAddress = context.recipientContext.localIdentifiers.aciAddress
        case .none, .group, .distributionList, .releaseNotesChannel, .callLink:
            // Groups and distritibution lists cannot be an authors of a message!
            return invalidProtoData(.pollTerminateAuthorNotContact)
        case .contact(let contactAddress):
            guard contactAddress.aci != nil || contactAddress.e164 != nil else {
                return invalidProtoData(.incomingMessageNotFromAciOrE164)
            }
            authorAddress = contactAddress.asInteropAddress()
        }
        guard let aci = authorAddress.aci else {
            return invalidProtoData(.recipientIdNotFound(recipientId))
        }

        var userInfoForNewMessage: [InfoMessageUserInfoKey: Any] = [:]
        userInfoForNewMessage[.endPoll] = PersistableEndPollItem(
            question: pollTerminateUpdateProto.question,
            authorServiceIdBinary: aci.serviceIdBinary,
            timestamp: Int64(pollTerminateUpdateProto.targetSentTimestamp),
        )

        let infoMessage = TSInfoMessage(
            thread: groupThread,
            messageType: .typeEndPoll,
            timestamp: chatItem.dateSent,
            infoMessageUserInfo: userInfoForNewMessage,
        )

        do {
            try interactionStore.insert(
                infoMessage,
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
