//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

final class BackupArchiveSessionSwitchoverChatUpdateArchiver {
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

    func archiveSessionSwitchoverChatUpdate(
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

        guard
            let sessionSwitchoverPhoneNumberString = infoMessage.sessionSwitchoverPhoneNumber,
            let sessionSwitchoverPhoneNumber = E164(sessionSwitchoverPhoneNumberString)
        else {
            return .skippableInteraction(.legacyInfoMessage(.sessionSwitchoverWithoutPhoneNumber))
        }

        let switchedOverContactAddress: BackupArchive.ContactAddress
        switch threadInfo {
        case .noteToSelfThread:
            // See comment on skippable update enum case.
            return .skippableInteraction(.legacyInfoMessage(.sessionSwitchoverInNoteToSelf))
        case .contactThread(let contactAddress):
            guard let contactAddress else { fallthrough }
            switchedOverContactAddress = contactAddress
        case .groupThread:
            return messageFailure(.sessionSwitchoverUpdateMissingAuthor)
        }

        var sessionSwitchoverChatUpdate = BackupProto_SessionSwitchoverChatUpdate()
        sessionSwitchoverChatUpdate.e164 = sessionSwitchoverPhoneNumber.uint64Value

        var chatUpdateMessage = BackupProto_ChatUpdateMessage()
        chatUpdateMessage.update = .sessionSwitchover(sessionSwitchoverChatUpdate)

        return Details.validateAndBuild(
            interactionUniqueId: infoMessage.uniqueInteractionId,
            author: .contact(switchedOverContactAddress),
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

    func restoreSessionSwitchoverChatUpdate(
        _ sessionSwitchoverUpdateProto: BackupProto_SessionSwitchoverChatUpdate,
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

        guard let e164 = E164(sessionSwitchoverUpdateProto.e164) else {
            return invalidProtoData(.invalidE164(protoClass: BackupProto_SessionSwitchoverChatUpdate.self))
        }

        guard case .contact(let switchedOverContactThread) = chatThread.threadType else {
            return invalidProtoData(.sessionSwitchoverUpdateNotFromContact)
        }

        let sessionSwitchoverInfoMessage: TSInfoMessage = .makeForSessionSwitchover(
            contactThread: switchedOverContactThread,
            timestamp: chatItem.dateSent,
            phoneNumber: e164.stringValue,
        )

        do {
            try interactionStore.insert(
                sessionSwitchoverInfoMessage,
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
