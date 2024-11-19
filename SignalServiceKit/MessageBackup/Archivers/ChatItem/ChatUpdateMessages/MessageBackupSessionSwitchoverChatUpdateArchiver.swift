//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

final class MessageBackupSessionSwitchoverChatUpdateArchiver {
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

    func archiveSessionSwitchoverChatUpdate(
        infoMessage: TSInfoMessage,
        threadInfo: MessageBackup.ChatArchivingContext.CachedThreadInfo,
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

        guard
            let sessionSwitchoverPhoneNumberString = infoMessage.sessionSwitchoverPhoneNumber,
            let sessionSwitchoverPhoneNumber = E164(sessionSwitchoverPhoneNumberString)
        else {
            return .skippableChatUpdate(.legacyInfoMessage(.sessionSwitchoverWithoutPhoneNumber))
        }

        let switchedOverContactAddress: MessageBackup.ContactAddress
        switch threadInfo {
        case .contactThread(let contactAddress):
            guard let contactAddress else { fallthrough }
            switchedOverContactAddress = contactAddress
        case .groupThread:
            return messageFailure(.sessionSwitchoverUpdateMissingAuthor)
        }

        guard let threadRecipientId = context.recipientContext[.contact(switchedOverContactAddress)] else {
            return messageFailure(.referencedRecipientIdMissing(.contact(switchedOverContactAddress)))
        }

        var sessionSwitchoverChatUpdate = BackupProto_SessionSwitchoverChatUpdate()
        sessionSwitchoverChatUpdate.e164 = sessionSwitchoverPhoneNumber.uint64Value

        var chatUpdateMessage = BackupProto_ChatUpdateMessage()
        chatUpdateMessage.update = .sessionSwitchover(sessionSwitchoverChatUpdate)

        let interactionArchiveDetails = Details(
            author: threadRecipientId,
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

    func restoreSessionSwitchoverChatUpdate(
        _ sessionSwitchoverUpdateProto: BackupProto_SessionSwitchoverChatUpdate,
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

        guard let e164 = E164(sessionSwitchoverUpdateProto.e164) else {
            return invalidProtoData(.invalidE164(protoClass: BackupProto_SessionSwitchoverChatUpdate.self))
        }

        guard case .contact(let switchedOverContactThread) = chatThread.threadType else {
            return invalidProtoData(.sessionSwitchoverUpdateNotFromContact)
        }

        let sessionSwitchoverInfoMessage: TSInfoMessage = .makeForSessionSwitchover(
            contactThread: switchedOverContactThread,
            timestamp: chatItem.dateSent,
            phoneNumber: e164.stringValue
        )

        guard let directionalDetails = chatItem.directionalDetails else {
            return .messageFailure([.restoreFrameError(
                .invalidProtoData(.chatItemMissingDirectionalDetails),
                chatItem.id
            )])
        }

        do {
            try interactionStore.insert(
                sessionSwitchoverInfoMessage,
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
