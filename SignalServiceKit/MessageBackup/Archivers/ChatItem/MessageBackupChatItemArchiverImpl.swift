//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class MessageBackupChatItemArchiverImpl: MessageBackupChatItemArchiver {

    private let callRecordStore: CallRecordStore
    private let dateProvider: DateProvider
    private let groupCallRecordManager: GroupCallRecordManager
    private let groupUpdateHelper: GroupUpdateInfoMessageInserterBackupHelper
    private let groupUpdateItemBuilder: GroupUpdateItemBuilder
    private let individualCallRecordManager: IndividualCallRecordManager
    private let interactionStore: InteractionStore
    private let reactionStore: ReactionStore
    private let sentMessageTranscriptReceiver: SentMessageTranscriptReceiver
    private let threadStore: ThreadStore

    public init(
        callRecordStore: CallRecordStore,
        dateProvider: @escaping DateProvider,
        groupCallRecordManager: GroupCallRecordManager,
        groupUpdateHelper: GroupUpdateInfoMessageInserterBackupHelper,
        groupUpdateItemBuilder: GroupUpdateItemBuilder,
        individualCallRecordManager: IndividualCallRecordManager,
        interactionStore: InteractionStore,
        reactionStore: ReactionStore,
        sentMessageTranscriptReceiver: SentMessageTranscriptReceiver,
        threadStore: ThreadStore
    ) {
        self.callRecordStore = callRecordStore
        self.dateProvider = dateProvider
        self.groupCallRecordManager = groupCallRecordManager
        self.groupUpdateHelper = groupUpdateHelper
        self.groupUpdateItemBuilder = groupUpdateItemBuilder
        self.individualCallRecordManager = individualCallRecordManager
        self.interactionStore = interactionStore
        self.reactionStore = reactionStore
        self.sentMessageTranscriptReceiver = sentMessageTranscriptReceiver
        self.threadStore = threadStore
    }

    private lazy var reactionArchiver = MessageBackupReactionArchiver(
        reactionStore: reactionStore
    )
    private lazy var contentsArchiver = MessageBackupTSMessageContentsArchiver(
        interactionStore: interactionStore,
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
    private lazy var groupUpdateMessageArchiver =
        MessageBackupGroupUpdateMessageArchiver(
            groupUpdateBuilder: groupUpdateItemBuilder,
            groupUpdateHelper: groupUpdateHelper,
            interactionStore: interactionStore
        )
    private lazy var individualCallArchiver = MessageBackupIndividualCallArchiver(
        callRecordStore: callRecordStore,
        individualCallRecordManager: individualCallRecordManager,
        interactionStore: interactionStore
    )
    private lazy var groupCallArchiver = MessageBackupGroupCallArchiver(
        callRecordStore: callRecordStore,
        groupCallRecordManager: groupCallRecordManager,
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
        var partialFailures = [ArchiveMultiFrameResult.ArchiveFrameError]()

        func archiveInteraction(
            _ interaction: TSInteraction,
            stop: inout Bool
        ) {
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
                stop = true
            }
        }

        do {
            try interactionStore.enumerateAllInteractions(
                tx: tx,
                block: archiveInteraction(_:stop:)
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
        case .individualCall:
            archiver = individualCallArchiver
        case .groupCall:
            archiver = groupCallArchiver
        case .groupUpdateInfoMessage:
            archiver = groupUpdateMessageArchiver
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
        var partialErrors = [ArchiveMultiFrameResult.ArchiveFrameError]()

        guard let chatId = context[interaction.uniqueThreadIdentifier] else {
            partialErrors.append(.archiveFrameError(
                .referencedThreadIdMissing(interaction.uniqueThreadIdentifier),
                interaction.uniqueInteractionId
            ))
            return .partialSuccess(partialErrors)
        }

        guard let archiver = self.archiver(
            for: interaction.archiverType(
                localIdentifiers: context.recipientContext.localIdentifiers
            )
        ) else {
            // TODO: when we have a complete set of archivers, this should
            // maybe be considered a catastrophic failure?
            // For now there's interactions we don't handle; just ignore it.
            return .success
        }

        let result = archiver.archiveInteraction(
            interaction,
            context: context,
            tx: tx
        )

        let details: MessageBackup.InteractionArchiveDetails
        switch result {
        case .success(let deets):
            details = deets

        case .isPastRevision, .skippableGroupUpdate, .notYetImplemented:
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
            sms: details.isSms
        )

        chatItem.item = details.chatItemType
        chatItem.directionalDetails = details.directionalDetails
        if let expireStartDate = details.expireStartDate, expireStartDate > 0 {
            chatItem.expireStartDate = expireStartDate
        }
        if let expiresInMs = details.expiresInMs, expiresInMs > 0 {
            chatItem.expiresInMs = expiresInMs
        }
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
