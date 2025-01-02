//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class MessageBackupChatItemArchiverImpl: MessageBackupChatItemArchiver {
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>

    private let attachmentManager: AttachmentManager
    private let attachmentStore: AttachmentStore
    private let backupAttachmentDownloadManager: BackupAttachmentDownloadManager
    private let callRecordStore: CallRecordStore
    private let contactManager: MessageBackup.Shims.ContactManager
    private let dateProvider: DateProvider
    private let editMessageStore: EditMessageStore
    private let groupCallRecordManager: GroupCallRecordManager
    private let groupUpdateHelper: GroupUpdateInfoMessageInserterBackupHelper
    private let groupUpdateItemBuilder: GroupUpdateItemBuilder
    private let individualCallRecordManager: IndividualCallRecordManager
    private let interactionStore: MessageBackupInteractionStore
    private let archivedPaymentStore: ArchivedPaymentStore
    private let reactionStore: ReactionStore
    private let threadStore: MessageBackupThreadStore

    public init(
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        backupAttachmentDownloadManager: BackupAttachmentDownloadManager,
        callRecordStore: CallRecordStore,
        contactManager: MessageBackup.Shims.ContactManager,
        dateProvider: @escaping DateProvider,
        editMessageStore: EditMessageStore,
        groupCallRecordManager: GroupCallRecordManager,
        groupUpdateHelper: GroupUpdateInfoMessageInserterBackupHelper,
        groupUpdateItemBuilder: GroupUpdateItemBuilder,
        individualCallRecordManager: IndividualCallRecordManager,
        interactionStore: MessageBackupInteractionStore,
        archivedPaymentStore: ArchivedPaymentStore,
        reactionStore: ReactionStore,
        threadStore: MessageBackupThreadStore
    ) {
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.backupAttachmentDownloadManager = backupAttachmentDownloadManager
        self.callRecordStore = callRecordStore
        self.contactManager = contactManager
        self.dateProvider = dateProvider
        self.editMessageStore = editMessageStore
        self.groupCallRecordManager = groupCallRecordManager
        self.groupUpdateHelper = groupUpdateHelper
        self.groupUpdateItemBuilder = groupUpdateItemBuilder
        self.individualCallRecordManager = individualCallRecordManager
        self.interactionStore = interactionStore
        self.archivedPaymentStore = archivedPaymentStore
        self.reactionStore = reactionStore
        self.threadStore = threadStore
    }

    private lazy var attachmentsArchiver = MessageBackupMessageAttachmentArchiver(
        attachmentManager: attachmentManager,
        attachmentStore: attachmentStore,
        backupAttachmentDownloadManager: backupAttachmentDownloadManager
    )
    private lazy var reactionArchiver = MessageBackupReactionArchiver(
        reactionStore: MessageBackupReactionStore()
    )
    private lazy var contentsArchiver = MessageBackupTSMessageContentsArchiver(
        interactionStore: interactionStore,
        archivedPaymentStore: archivedPaymentStore,
        attachmentsArchiver: attachmentsArchiver,
        reactionArchiver: reactionArchiver
    )
    private lazy var incomingMessageArchiver =
        MessageBackupTSIncomingMessageArchiver(
            contentsArchiver: contentsArchiver,
            dateProvider: dateProvider,
            editMessageStore: editMessageStore,
            interactionStore: interactionStore
        )
    private lazy var outgoingMessageArchiver =
        MessageBackupTSOutgoingMessageArchiver(
            contentsArchiver: contentsArchiver,
            dateProvider: dateProvider,
            editMessageStore: editMessageStore,
            interactionStore: interactionStore
        )
    private lazy var chatUpdateMessageArchiver =
        MessageBackupChatUpdateMessageArchiver(
            callRecordStore: callRecordStore,
            contactManager: contactManager,
            groupCallRecordManager: groupCallRecordManager,
            groupUpdateHelper: groupUpdateHelper,
            groupUpdateItemBuilder: groupUpdateItemBuilder,
            individualCallRecordManager: individualCallRecordManager,
            interactionStore: interactionStore
        )

    // MARK: -

    public func archiveInteractions(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext
    ) throws(CancellationError) -> ArchiveMultiFrameResult {
        var completeFailureError: MessageBackup.FatalArchivingError?
        var partialFailures = [ArchiveFrameError]()

        func archiveInteraction(
            _ interaction: TSInteraction
        ) -> Bool {
            var stop = false
            autoreleasepool {
                let result = self.archiveInteraction(
                    interaction,
                    stream: stream,
                    context: context
                )
                switch result {
                case .success:
                    break
                case .partialSuccess(let errors):
                    partialFailures.append(contentsOf: errors)
                case .completeFailure(let error):
                    completeFailureError = error
                    stop = true
                    return
                }
            }

            return !stop
        }

        do {
            try interactionStore.enumerateAllInteractions(
                tx: context.tx,
                block: { interaction in
                    try Task.checkCancellation()
                    return archiveInteraction(interaction)
                }
            )
        } catch let error as CancellationError {
            throw error
        } catch let error {
            // Errors thrown here are from the iterator's SQL query,
            // not the individual interaction handler.
            return .completeFailure(.fatalArchiveError(.interactionIteratorError(error)))
        }

        if let completeFailureError {
            return .completeFailure(completeFailureError)
        } else if partialFailures.isEmpty {
            return .success
        } else {
            return .partialSuccess(partialFailures)
        }
    }

    private func archiveInteraction(
        _ interaction: TSInteraction,
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext
    ) -> ArchiveMultiFrameResult {
        var partialErrors = [ArchiveFrameError]()

        let chatId = context[interaction.uniqueThreadIdentifier]
        let threadInfo = chatId.map { context[$0] } ?? nil

        if context.gv1ThreadIds.contains(interaction.uniqueThreadIdentifier) {
            /// We are knowingly dropping GV1 data from backups, so we'll skip
            /// archiving any interactions for GV1 threads without errors.
            return .success
        }

        guard let chatId, let threadInfo else {
            partialErrors.append(.archiveFrameError(
                .referencedThreadIdMissing(interaction.uniqueThreadIdentifier),
                interaction.uniqueInteractionId
            ))
            return .partialSuccess(partialErrors)
        }

        let archiveInteractionResult: MessageBackup.ArchiveInteractionResult<MessageBackup.InteractionArchiveDetails>
        if
            let message = interaction as? TSMessage,
            message.isGroupStoryReply
        {
            // We skip group story reply messages, as stories
            // aren't backed up so neither should their replies.
            return .success
        } else if let incomingMessage = interaction as? TSIncomingMessage {
            archiveInteractionResult = incomingMessageArchiver.archiveIncomingMessage(
                incomingMessage,
                context: context
            )
        } else if let outgoingMessage = interaction as? TSOutgoingMessage {
            archiveInteractionResult = outgoingMessageArchiver.archiveOutgoingMessage(
                outgoingMessage,
                context: context
            )
        } else if let individualCallInteraction = interaction as? TSCall {
            archiveInteractionResult = chatUpdateMessageArchiver.archiveIndividualCall(
                individualCallInteraction,
                context: context
            )
        } else if let groupCallInteraction = interaction as? OWSGroupCallMessage {
            archiveInteractionResult = chatUpdateMessageArchiver.archiveGroupCall(
                groupCallInteraction,
                context: context
            )
        } else if let errorMessage = interaction as? TSErrorMessage {
            archiveInteractionResult = chatUpdateMessageArchiver.archiveErrorMessage(
                errorMessage,
                context: context
            )
        } else if let infoMessage = interaction as? TSInfoMessage {
            archiveInteractionResult = chatUpdateMessageArchiver.archiveInfoMessage(
                infoMessage,
                threadInfo: threadInfo,
                context: context
            )
        } else {
            /// Any interactions that landed us here will be legacy messages we
            /// no longer support and which have no corresponding type in the
            /// Backup, so we'll skip them and report it as a success.
            return .success
        }

        let details: MessageBackup.InteractionArchiveDetails
        switch archiveInteractionResult {
        case .success(let deets):
            details = deets
        case .partialFailure(let deets, let errors):
            details = deets
            partialErrors.append(contentsOf: errors)
        case .skippableChatUpdate:
            // Skip! Say it succeeded so we ignore it.
            return .success
        case .messageFailure(let errors):
            partialErrors.append(contentsOf: errors)
            return .partialSuccess(partialErrors)
        case .completeFailure(let error):
            return .completeFailure(error)
        }

        switch context.backupPurpose {
        case .deviceTransfer:
            // We include soon-to expire messages for
            // "device transfer" backups.
            break
        case .remoteBackup:
            let minExpireTime = dateProvider().ows_millisecondsSince1970
                + MessageBackup.Constants.minExpireTimerMs
            if
                let expireStartDate = details.expireStartDate,
                let expiresInMs = details.expiresInMs,
                expiresInMs > 0, // Only check expiration if `expiresInMs` is set to something interesting.
                expireStartDate + expiresInMs < minExpireTime
            {
                // Skip this message, but count it as a success.
                return .success
            }
        }

        let chatItem = buildChatItem(
            fromDetails: details,
            chatId: chatId
        )

        let error = Self.writeFrameToStream(
            stream,
            objectId: interaction.uniqueInteractionId
        ) {
            var frame = BackupProto_Frame()
            frame.item = .chatItem(chatItem)
            return frame
        }

        if let error {
            partialErrors.append(error)
            return .partialSuccess(partialErrors)
        } else if partialErrors.isEmpty {
            return .success
        } else {
            return .partialSuccess(partialErrors)
        }
    }

    private func buildChatItem(
        fromDetails details: MessageBackup.InteractionArchiveDetails,
        chatId: MessageBackup.ChatId
    ) -> BackupProto_ChatItem {
        var chatItem = BackupProto_ChatItem()
        chatItem.chatID = chatId.value
        chatItem.authorID = details.author.value
        chatItem.dateSent = details.dateCreated
        if let expiresInMs = details.expiresInMs, expiresInMs > 0 {
            if let expireStartDate = details.expireStartDate {
                chatItem.expireStartDate = expireStartDate
            }
            chatItem.expiresInMs = expiresInMs
        }
        chatItem.sms = details.isSmsPreviouslyRestoredFromBackup
        chatItem.item = details.chatItemType
        chatItem.directionalDetails = details.directionalDetails
        chatItem.revisions = details.pastRevisions.map { pastRevisionDetails in
            /// Recursively map our past revision details to `ChatItem`s of
            /// their own. (Their `pastRevisions` will all be empty.)
            return buildChatItem(
                fromDetails: pastRevisionDetails,
                chatId: chatId
            )
        }

        return chatItem
    }

    // MARK: -

    public func restore(
        _ chatItem: BackupProto_ChatItem,
        context: MessageBackup.ChatItemRestoringContext
    ) -> RestoreFrameResult {
        func restoreFrameError(
            _ error: MessageBackup.RestoreFrameError<MessageBackup.ChatItemId>.ErrorType,
            line: UInt = #line
        ) -> RestoreFrameResult {
            return .failure([.restoreFrameError(error, chatItem.id, line: line)])
        }

        switch context.recipientContext[chatItem.authorRecipientId] {
        case .releaseNotesChannel:
            // The release notes channel doesn't exist yet, so for the time
            // being we'll drop all chat items destined for it.
            //
            // TODO: [Backups] Implement restoring chat items into the release notes channel chat.
            return .success
        default:
            break
        }

        guard let thread = context.chatContext[chatItem.typedChatId] else {
            return restoreFrameError(.invalidProtoData(.chatIdNotFound(chatItem.typedChatId)))
        }

        let restoreInteractionResult: MessageBackup.RestoreInteractionResult<Void>
        switch chatItem.directionalDetails {
        case nil:
            return restoreFrameError(.invalidProtoData(.chatItemMissingDirectionalDetails))
        case .incoming:
            restoreInteractionResult = incomingMessageArchiver.restoreIncomingChatItem(
                chatItem,
                chatThread: thread,
                context: context
            )
        case .outgoing:
            restoreInteractionResult = outgoingMessageArchiver.restoreChatItem(
                chatItem,
                chatThread: thread,
                context: context
            )
        case .directionless:
            switch chatItem.item {
            case nil:
                return restoreFrameError(.invalidProtoData(.chatItemMissingItem))
            case .standardMessage, .contactMessage, .giftBadge, .viewOnceMessage, .paymentNotification, .remoteDeletedMessage, .stickerMessage:
                return restoreFrameError(.invalidProtoData(.directionlessChatItemNotUpdateMessage))
            case .updateMessage:
                restoreInteractionResult = chatUpdateMessageArchiver.restoreChatItem(
                    chatItem,
                    chatThread: thread,
                    context: context
                )
            }
        }

        switch restoreInteractionResult {
        case .success:
            return .success
        case .partialRestore(_, let errors):
            return .partialRestore(errors)
        case .messageFailure(let errors):
            return .failure(errors)
        }
    }
}
