//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

final class BackupArchivePinMessageChatUpdateArchiver {
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

    func archivePinMessageChatUpdate(
        infoMessage: TSInfoMessage,
        threadInfo: BackupArchive.ChatArchivingContext.CachedThreadInfo,
        context: BackupArchive.ChatArchivingContext
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

        guard let pinMessageItem: PersistablePinnedMessageItem = infoMessage.infoMessageValue(forKey: .pinnedMessage) else {
            return messageFailure(.pinMessageChatUpdateMissingPersistableData)
        }

        let chatUpdateAuthorAddress = BackupArchive.InteractionArchiveDetails.AuthorAddress.contact(
            BackupArchive.ContactAddress(
                aci: pinMessageItem.pinnedMessageAuthorAci
            )
        )

        var pinMessageChatUpdate = BackupProto_PinMessageUpdate()

        switch context.recipientContext.getRecipientId(aci: pinMessageItem.originalMessageAuthorAci, forInteraction: infoMessage) {
        case .found(let recipientId):
            pinMessageChatUpdate.authorID = recipientId.value
        case .missing(let archiveFrameError):
            return .messageFailure([archiveFrameError])
        }

        pinMessageChatUpdate.targetSentTimestamp = UInt64(pinMessageItem.timestamp)

        var chatUpdateMessage = BackupProto_ChatUpdateMessage()
        chatUpdateMessage.update = .pinMessage(pinMessageChatUpdate)

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
            context: context.recipientContext
        )
    }

    // MARK: -

    func restorePinMessageChatUpdate(
        _ pinMessageChatUpdateProto: BackupProto_PinMessageUpdate,
        chatItem: BackupProto_ChatItem,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext
    ) -> RestoreChatUpdateMessageResult {
        func aciForRecipientId(recipientId: BackupArchive.RecipientId, partialErrors: inout [BackupArchive.RestoreFrameError<BackupArchive.ChatItemId>]) -> Aci? {
            var partialErrors = [BackupArchive.RestoreFrameError<BackupArchive.ChatItemId>]()

            let authorAddress: BackupArchive.InteropAddress
            switch context.recipientContext[recipientId] {
            case .localAddress:
                authorAddress = context.recipientContext.localIdentifiers.aciAddress
            case .none, .group, .distributionList, .releaseNotesChannel, .callLink:
                // Groups and distribution lists cannot be an authors of a message!
                partialErrors.append(.restoreFrameError(
                    .invalidProtoData(.pinMessageAuthorNotContact),
                    chatItem.id
                ))
                return nil
            case .contact(let contactAddress):
                guard contactAddress.aci != nil || contactAddress.e164 != nil else {
                    partialErrors.append(.restoreFrameError(
                        .invalidProtoData(.incomingMessageNotFromAciOrE164),
                        chatItem.id
                    ))
                    return nil
                }
                authorAddress = contactAddress.asInteropAddress()
            }
            guard let authorAci = authorAddress.aci else {
                partialErrors.append(.restoreFrameError(
                    .invalidProtoData(.recipientIdNotFound(recipientId)),
                    chatItem.id
                ))
                return nil
            }
            return authorAci
        }

        var partialErrors = [BackupArchive.RestoreFrameError<BackupArchive.ChatItemId>]()
        let pinAuthorAci = aciForRecipientId(
            recipientId: BackupArchive.RecipientId(value: chatItem.authorID),
            partialErrors: &partialErrors
        )
        let originalMessageAci = aciForRecipientId(
            recipientId: BackupArchive.RecipientId(value: pinMessageChatUpdateProto.authorID),
            partialErrors: &partialErrors
        )

        guard let pinAuthorAci, let originalMessageAci, partialErrors.isEmpty else {
            return .messageFailure(partialErrors)
        }

        guard BackupArchive.Timestamps.isValid(pinMessageChatUpdateProto.targetSentTimestamp) else {
            return .messageFailure([.restoreFrameError(.invalidProtoData(.sentTimestampOverflowedLocalType), chatItem.id)])
        }

        var userInfoForNewMessage: [InfoMessageUserInfoKey: Any] = [:]
        userInfoForNewMessage[.pinnedMessage] = PersistablePinnedMessageItem(
            pinnedMessageAuthorAci: pinAuthorAci,
            originalMessageAuthorAci: originalMessageAci,
            timestamp: Int64(pinMessageChatUpdateProto.targetSentTimestamp)
        )

        let infoMessage = TSInfoMessage(
            thread: chatThread.tsThread,
            messageType: .typePinnedMessage,
            timestamp: chatItem.dateSent,
            infoMessageUserInfo: userInfoForNewMessage
        )

        do {
            try interactionStore.insert(
                infoMessage,
                in: chatThread,
                chatId: chatItem.typedChatId,
                context: context
            )
        } catch let error {
            return .messageFailure([.restoreFrameError(.databaseInsertionFailed(error), chatItem.id)])
        }

        return .success(())
    }
}
