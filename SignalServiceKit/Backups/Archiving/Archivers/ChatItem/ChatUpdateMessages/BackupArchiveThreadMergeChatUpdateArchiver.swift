//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

final class BackupArchiveThreadMergeChatUpdateArchiver {
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

    func archiveThreadMergeChatUpdate(
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

        guard
            let threadMergePhoneNumberString = infoMessage.threadMergePhoneNumber,
            let threadMergePhoneNumber = E164(threadMergePhoneNumberString)
        else {
            return .skippableInteraction(.legacyInfoMessage(.threadMergeWithoutPhoneNumber))
        }

        let mergedContactAddress: BackupArchive.ContactAddress
        switch threadInfo {
        case .noteToSelfThread:
            mergedContactAddress = context.recipientContext.localRecipientAddress
        case .contactThread(let contactAddress):
            guard let contactAddress else { fallthrough }
            mergedContactAddress = contactAddress
        case .groupThread:
            return messageFailure(.threadMergeUpdateMissingAuthor)
        }

        var threadMergeChatUpdate = BackupProto_ThreadMergeChatUpdate()
        threadMergeChatUpdate.previousE164 = threadMergePhoneNumber.uint64Value

        var chatUpdateMessage = BackupProto_ChatUpdateMessage()
        chatUpdateMessage.update = .threadMerge(threadMergeChatUpdate)

        return Details.validateAndBuild(
            interactionUniqueId: infoMessage.uniqueInteractionId,
            author: .contact(mergedContactAddress),
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

    func restoreThreadMergeChatUpdate(
        _ threadMergeUpdateProto: BackupProto_ThreadMergeChatUpdate,
        chatItem: BackupProto_ChatItem,
        chatThread: BackupArchive.ChatThread,
        context: BackupArchive.ChatItemRestoringContext
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

        guard let previousE164 = E164(threadMergeUpdateProto.previousE164) else {
            return invalidProtoData(.invalidE164(protoClass: BackupProto_ThreadMergeChatUpdate.self))
        }

        guard case .contact(let mergedThread) = chatThread.threadType else {
            return invalidProtoData(.threadMergeUpdateNotFromContact)
        }

        let threadMergeInfoMessage: TSInfoMessage = .makeForThreadMerge(
            mergedThread: mergedThread,
            timestamp: chatItem.dateSent,
            previousE164: previousE164.stringValue
        )

        do {
            try interactionStore.insert(
                threadMergeInfoMessage,
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
