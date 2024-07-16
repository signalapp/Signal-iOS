//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class MessageBackupChatItemArchiverImpl: MessageBackupChatItemArchiver {
    private typealias ArchiveFrameError = MessageBackup.ArchiveFrameError<MessageBackup.InteractionUniqueId>

    private let callRecordStore: CallRecordStore
    private let contactManager: MessageBackup.Shims.ContactManager
    private let dateProvider: DateProvider
    private let groupCallRecordManager: GroupCallRecordManager
    private let groupUpdateHelper: GroupUpdateInfoMessageInserterBackupHelper
    private let groupUpdateItemBuilder: GroupUpdateItemBuilder
    private let individualCallRecordManager: IndividualCallRecordManager
    private let interactionStore: InteractionStore
    private let archivedPaymentStore: ArchivedPaymentStore
    private let reactionStore: ReactionStore
    private let sentMessageTranscriptReceiver: SentMessageTranscriptReceiver
    private let threadStore: ThreadStore

    public init(
        callRecordStore: CallRecordStore,
        contactManager: MessageBackup.Shims.ContactManager,
        dateProvider: @escaping DateProvider,
        groupCallRecordManager: GroupCallRecordManager,
        groupUpdateHelper: GroupUpdateInfoMessageInserterBackupHelper,
        groupUpdateItemBuilder: GroupUpdateItemBuilder,
        individualCallRecordManager: IndividualCallRecordManager,
        interactionStore: InteractionStore,
        archivedPaymentStore: ArchivedPaymentStore,
        reactionStore: ReactionStore,
        sentMessageTranscriptReceiver: SentMessageTranscriptReceiver,
        threadStore: ThreadStore
    ) {
        self.callRecordStore = callRecordStore
        self.contactManager = contactManager
        self.dateProvider = dateProvider
        self.groupCallRecordManager = groupCallRecordManager
        self.groupUpdateHelper = groupUpdateHelper
        self.groupUpdateItemBuilder = groupUpdateItemBuilder
        self.individualCallRecordManager = individualCallRecordManager
        self.interactionStore = interactionStore
        self.archivedPaymentStore = archivedPaymentStore
        self.reactionStore = reactionStore
        self.sentMessageTranscriptReceiver = sentMessageTranscriptReceiver
        self.threadStore = threadStore
    }

    private lazy var reactionArchiver = MessageBackupReactionArchiver(
        reactionStore: reactionStore
    )
    private lazy var contentsArchiver = MessageBackupTSMessageContentsArchiver(
        interactionStore: interactionStore,
        archivedPaymentStore: archivedPaymentStore,
        reactionArchiver: reactionArchiver
    )
    private lazy var incomingMessageArchiver =
        MessageBackupTSIncomingMessageArchiver(
            contentsArchiver: contentsArchiver,
            interactionStore: interactionStore
        )
    private lazy var outgoingMessageArchiver =
        MessageBackupTSOutgoingMessageArchiver(
            contentsArchiver: contentsArchiver,
            interactionStore: interactionStore,
            sentMessageTranscriptReceiver: sentMessageTranscriptReceiver
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
    // TODO: need for info messages. not story messages, those are skipped.
    // are there other message types? what about e.g. payment messages?
    // anything that isnt a TSOutgoingMessage or TSIncomingMessage.

    public func archiveInteractions(
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveMultiFrameResult {
        var completeFailureError: MessageBackup.FatalArchivingError?
        var partialFailures = [ArchiveFrameError]()

        func archiveInteraction(
            _ interaction: TSInteraction
        ) -> Bool {
            let result = self.archiveInteraction(
                interaction,
                stream: stream,
                context: context,
                tx: tx
            )
            switch result {
            case .success:
                break
            case .partialSuccess(let errors):
                partialFailures.append(contentsOf: errors)
            case .completeFailure(let error):
                completeFailureError = error
                return false
            }

            return true
        }

        do {
            try interactionStore.enumerateAllInteractions(
                tx: tx,
                block: archiveInteraction(_:)
            )
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

    // TODO: once we have a complete set of archivers, this
    // should return a non-optional value.
    private func archiver(
        for archiverType: MessageBackup.ChatItemArchiverType
    ) -> MessageBackupInteractionArchiver? {
        let archiver: MessageBackupInteractionArchiver
        switch archiverType {
        case .incomingMessage:
            archiver = incomingMessageArchiver
        case .outgoingMessage:
            archiver = outgoingMessageArchiver
        case .chatUpdateMessage:
            archiver = chatUpdateMessageArchiver
        case .unimplemented:
            return nil
        }

        owsAssertDebug(archiverType == type(of: archiver).archiverType)
        return archiver
    }

    private func archiveInteraction(
        _ interaction: TSInteraction,
        stream: MessageBackupProtoOutputStream,
        context: MessageBackup.ChatArchivingContext,
        tx: DBReadTransaction
    ) -> ArchiveMultiFrameResult {
        var partialErrors = [ArchiveFrameError]()

        guard
            let chatId = context[interaction.uniqueThreadIdentifier],
            let thread = threadStore.fetchThreadForInteraction(interaction, tx: tx)
        else {
            partialErrors.append(.archiveFrameError(
                .referencedThreadIdMissing(interaction.uniqueThreadIdentifier),
                interaction.uniqueInteractionId
            ))
            return .partialSuccess(partialErrors)
        }

        if
            let groupThread = thread as? TSGroupThread,
            groupThread.isGroupV1Thread
        {
            /// We are knowingly dropping GV1 data from backups, so we'll skip
            /// archiving any interactions for GV1 threads without errors.
            return .success
        }

        guard let archiver = self.archiver(for: interaction.archiverType()) else {
            // TODO: when we have a complete set of archivers, this should
            // maybe be considered a catastrophic failure?
            // For now there's interactions we don't handle; just ignore it.
            return .success
        }

        let result = archiver.archiveInteraction(
            interaction,
            thread: thread,
            context: context,
            tx: tx
        )

        let details: MessageBackup.InteractionArchiveDetails
        switch result {
        case .success(let deets):
            details = deets

        case
                .isPastRevision,
                .skippableChatUpdate,
                .notYetImplemented:
            // Skip! Say it succeeded so we ignore it.
            return .success

        case .messageFailure(let errors):
            partialErrors.append(contentsOf: errors)
            return .partialSuccess(partialErrors)
        case .partialFailure(let deets, let errors):
            partialErrors.append(contentsOf: errors)
            details = deets
        case .completeFailure(let error):
            return .completeFailure(error)
        }

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

        var chatItem = BackupProto.ChatItem(
            chatId: chatId.value,
            authorId: details.author.value,
            dateSent: interaction.timestamp,
            expireStartDate: details.expireStartDate ?? 0,
            expiresInMs: details.expiresInMs ?? 0,
            sms: details.isSms
        )
        chatItem.item = details.chatItemType
        chatItem.directionalDetails = details.directionalDetails
        chatItem.revisions = details.revisions

        let error = Self.writeFrameToStream(
            stream,
            objectId: interaction.uniqueInteractionId
        ) {
            var frame = BackupProto.Frame()
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

    public func restore(
        _ chatItem: BackupProto.ChatItem,
        context: MessageBackup.ChatRestoringContext,
        tx: DBWriteTransaction
    ) -> RestoreFrameResult {
        guard let archiver = self.archiver(for: chatItem.archiverType) else {
            // TODO: when we have a complete set of archivers, this should
            // maybe be considered a catastrophic failure?
            // For now there's interactions we don't handle; just ignore it.
            return .success
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

        guard let threadUniqueId = context[chatItem.typedChatId] else {
            return .failure([.restoreFrameError(
                .invalidProtoData(.chatIdNotFound(chatItem.typedChatId)),
                chatItem.id
            )])
        }

        guard
            let threadRaw = threadStore.fetchThread(uniqueId: threadUniqueId.value, tx: tx)
        else {
            return .failure([.restoreFrameError(
                .referencedChatThreadNotFound(threadUniqueId),
                chatItem.id
            )])
        }

        let thread: MessageBackup.ChatThread
        if let contactThread = threadRaw as? TSContactThread {
            thread = .contact(contactThread)
        } else if let groupThread = threadRaw as? TSGroupThread, groupThread.isGroupV2Thread {
            thread = .groupV2(groupThread)
        } else {
            // It should be enforced by ChatRestoringContext that any
            // thread ID in it maps to a valid TSContact- or TSGroup- thread.
            return .failure([.restoreFrameError(
                .developerError(OWSAssertionError("Invalid TSThread type for chatId")),
                chatItem.id
            )])
        }

        let result = archiver.restoreChatItem(
            chatItem,
            chatThread: thread,
            context: context,
            tx: tx
        )

        switch result {
        case .success:
            return .success
        case .partialRestore(_, let errors):
            return .partialRestore(errors)
        case .messageFailure(let errors):
            return .failure(errors)
        }
    }
}
