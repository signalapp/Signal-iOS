//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

public struct ValidatedIncomingPollCreate {
    let messageBody: ValidatedInlineMessageBody
    let pollCreateProto: SSKProtoDataMessagePollCreate
}

// MARK: -

public class PollMessageManager {
    static let pollEmoji = "📊"

    private let pollStore: PollStore
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let interactionStore: InteractionStore
    private let db: DB
    private let messageSenderJobQueue: MessageSenderJobQueue
    private let accountManager: TSAccountManager
    private let disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore
    private let attachmentContentValidator: AttachmentContentValidator

    init(
        pollStore: PollStore,
        recipientDatabaseTable: RecipientDatabaseTable,
        interactionStore: InteractionStore,
        accountManager: TSAccountManager,
        messageSenderJobQueue: MessageSenderJobQueue,
        disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore,
        attachmentContentValidator: AttachmentContentValidator,
        db: DB,
    ) {
        self.pollStore = pollStore
        self.recipientDatabaseTable = recipientDatabaseTable
        self.interactionStore = interactionStore
        self.accountManager = accountManager
        self.messageSenderJobQueue = messageSenderJobQueue
        self.db = db
        self.disappearingMessagesConfigurationStore = disappearingMessagesConfigurationStore
        self.attachmentContentValidator = attachmentContentValidator
    }

    public func validateIncomingPollCreate(
        pollCreateProto pollCreate: SSKProtoDataMessagePollCreate,
        tx: DBWriteTransaction,
    ) throws -> ValidatedIncomingPollCreate {
        guard let question = pollCreate.question else {
            throw OWSAssertionError("Poll missing question")
        }
        guard
            question.trimmedIfNeeded(maxByteCount: OWSMediaUtils.kOversizeTextMessageSizeThresholdBytes) == nil,
            question.count <= OWSPoll.Constants.maxCharacterLength
        else {
            throw OWSAssertionError("Poll question too large")
        }

        guard question.count > 0 else {
            throw OWSAssertionError("Poll question empty")
        }

        guard pollCreate.options.count >= 2 else {
            throw OWSAssertionError("Poll does not have enough options")
        }

        for option in pollCreate.options {
            guard
                option.trimmedIfNeeded(maxByteCount: OWSMediaUtils.kOversizeTextMessageSizeThresholdBytes) == nil,
                option.count <= OWSPoll.Constants.maxCharacterLength
            else {
                throw OWSAssertionError("Poll option too large")
            }

            guard option.count > 0 else {
                throw OWSAssertionError("Poll option empty")
            }
        }

        let inlinedMessageBody = attachmentContentValidator.truncatedMessageBodyForInlining(
            MessageBody(text: question, ranges: .empty),
            tx: tx,
        )

        return ValidatedIncomingPollCreate(
            messageBody: inlinedMessageBody,
            pollCreateProto: pollCreate,
        )
    }

    public func processIncomingPollCreate(
        interactionId: Int64,
        pollCreateProto: SSKProtoDataMessagePollCreate,
        transaction: DBWriteTransaction,
    ) throws {
        try pollStore.createPoll(
            interactionId: interactionId,
            allowsMultiSelect: pollCreateProto.allowMultiple,
            options: pollCreateProto.options,
            transaction: transaction,
        )
    }

    public func processOutgoingPollCreate(
        interactionId: Int64,
        pollOptions: [String],
        allowsMultiSelect: Bool,
        transaction: DBWriteTransaction,
    ) throws {
        try pollStore.createPoll(
            interactionId: interactionId,
            allowsMultiSelect: allowsMultiSelect,
            options: pollOptions,
            transaction: transaction,
        )
    }

    public func processIncomingPollVote(
        voteAuthor: Aci,
        pollVoteProto: SSKProtoDataMessagePollVote,
        transaction: DBWriteTransaction,
    ) throws -> (TSMessage, shouldNotifyAuthorOfVote: Bool)? {
        guard
            let aciBinary = pollVoteProto.targetAuthorAciBinary,
            let pollAuthorAci = try? Aci.parseFrom(serviceIdBinary: aciBinary)
        else {
            Logger.error("Failure to parse Aci from binary")
            return nil
        }

        guard let localAci = accountManager.localIdentifiers(tx: transaction)?.aci else {
            throw OWSAssertionError("User not registered")
        }

        guard
            let targetMessage = try interactionStore.fetchMessage(
                timestamp: pollVoteProto.targetSentTimestamp,
                incomingMessageAuthor: localAci == pollAuthorAci ? nil : pollAuthorAci,
                transaction: transaction,
            ),
            targetMessage.isPoll,
            let interactionId = targetMessage.grdbId?.int64Value
        else {
            Logger.error("Can't find target poll")
            return nil
        }

        let signalRecipient = recipientDatabaseTable.fetchRecipient(serviceId: voteAuthor, transaction: transaction)

        guard let voteAuthorId = signalRecipient?.id else {
            Logger.error("Can't find voter in recipient table")
            return nil
        }

        let isUnvote = try pollStore.updatePollWithVotes(
            interactionId: interactionId,
            optionsVoted: pollVoteProto.optionIndexes,
            voteAuthorId: voteAuthorId,
            voteCount: pollVoteProto.voteCount,
            transaction: transaction,
        )

        let shouldNotifyAuthorOfVote = !isUnvote && localAci == pollAuthorAci && localAci != voteAuthor

        return (targetMessage, shouldNotifyAuthorOfVote)
    }

    public func processIncomingPollTerminate(
        pollTerminateProto: SSKProtoDataMessagePollTerminate,
        terminateAuthor: Aci,
        transaction: DBWriteTransaction,
    ) throws -> TSMessage? {

        guard let localAci = accountManager.localIdentifiers(tx: transaction)?.aci else {
            throw OWSAssertionError("User not registered")
        }

        guard
            let targetMessage = try interactionStore.fetchMessage(
                timestamp: pollTerminateProto.targetSentTimestamp,
                incomingMessageAuthor: terminateAuthor == localAci ? nil : terminateAuthor,
                transaction: transaction,
            ),
            targetMessage.isPoll,
            let interactionId = targetMessage.grdbId?.int64Value
        else {
            Logger.error("Can't find target poll")
            return nil
        }

        try pollStore.terminatePoll(interactionId: interactionId, transaction: transaction)

        return targetMessage
    }

    public func buildPoll(message: TSMessage, transaction: DBReadTransaction) throws -> OWSPoll? {
        guard
            let question = message.body?.filterStringForDisplay().nilIfEmpty,
            let localAci = accountManager.localIdentifiers(tx: transaction)?.aci
        else {
            throw OWSAssertionError("Invalid question body or local user not registered")
        }

        return try pollStore.owsPoll(
            question: question,
            message: message,
            localUser: localAci,
            transaction: transaction,
            ownerIsLocalUser: message.isOutgoing,
        )
    }

    public func buildProtoForSending(
        parentMessage: TSMessage,
        tx: DBReadTransaction,
    ) throws -> SSKProtoDataMessagePollCreate? {
        guard let poll = try buildPoll(message: parentMessage, transaction: tx) else {
            return nil
        }

        let pollBuilder = SSKProtoDataMessagePollCreate.builder()
        pollBuilder.setQuestion(poll.question)
        pollBuilder.setOptions(poll.sortedOptions().map(\.text))
        pollBuilder.setAllowMultiple(poll.allowsMultiSelect)

        let pollCreateProto = pollBuilder.buildInfallibly()

        return pollCreateProto
    }

    public func sendPollTerminateMessage(poll: OWSPoll, thread: TSGroupThread) throws {
        try db.write { tx in
            guard let targetPoll = interactionStore.fetchInteraction(rowId: poll.interactionId, tx: tx) else {
                return
            }

            try pollStore.terminatePoll(interactionId: poll.interactionId, transaction: tx)

            // Touch message so it reloads to show poll ended state.
            db.touch(interaction: targetPoll, shouldReindex: false, tx: tx)

            let pollTerminateMessage = OutgoingPollTerminateMessage(
                thread: thread,
                targetPollTimestamp: targetPoll.timestamp,
                expiresInSeconds: disappearingMessagesConfigurationStore.durationSeconds(for: thread, tx: tx),
                tx: tx,
            )

            let preparedMessage = PreparedOutgoingMessage.preprepared(
                transientMessageWithoutAttachments: pollTerminateMessage,
            )

            messageSenderJobQueue.add(
                message: preparedMessage,
                transaction: tx,
            )

            guard let localAci = accountManager.localIdentifiers(tx: tx)?.aci else {
                throw OWSAssertionError("User not registered")
            }

            let dmConfig = disappearingMessagesConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: tx)
            insertInfoMessageForEndPoll(
                timestamp: Date().ows_millisecondsSince1970,
                groupThread: thread,
                targetPollTimestamp: targetPoll.timestamp,
                pollQuestion: poll.question,
                terminateAuthor: localAci,
                expireTimer: dmConfig.durationSeconds,
                expireTimerVersion: dmConfig.timerVersion,
                tx: tx,
            )
        }
    }

    public func insertInfoMessageForEndPoll(
        timestamp: UInt64,
        groupThread: TSGroupThread,
        targetPollTimestamp: UInt64,
        pollQuestion: String,
        terminateAuthor: Aci,
        expireTimer: UInt32?,
        expireTimerVersion: UInt32?,
        tx: DBWriteTransaction,
    ) {
        var userInfoForNewMessage: [InfoMessageUserInfoKey: Any] = [:]
        userInfoForNewMessage[.endPoll] = PersistableEndPollItem(
            question: pollQuestion,
            authorServiceIdBinary: terminateAuthor.serviceIdBinary,
            timestamp: Int64(targetPollTimestamp),
        )

        var timerVersion: NSNumber?
        if let expireTimerVersion {
            timerVersion = NSNumber(value: expireTimerVersion)
        }

        let infoMessage = TSInfoMessage(
            thread: groupThread,
            timestamp: timestamp,
            serverGuid: nil,
            messageType: .typeEndPoll,
            expireTimerVersion: timerVersion,
            expiresInSeconds: expireTimer ?? 0,
            infoMessageUserInfo: userInfoForNewMessage,
        )

        infoMessage.anyInsert(transaction: tx)
    }

    public func processPollVoteMessageDidSend(
        targetPollTimestamp: UInt64,
        targetPollAuthorAci: Aci,
        optionIndexes: [OWSPoll.OptionIndex],
        voteCount: UInt32,
        tx: DBWriteTransaction,
    ) throws {
        guard let localAci = accountManager.localIdentifiers(tx: tx)?.aci else {
            Logger.error("Can't find local ACI")
            return
        }

        guard
            let localAuthorRecipientId = recipientDatabaseTable.fetchRecipient(
                serviceId: localAci,
                transaction: tx,
            )?.id
        else {
            Logger.error("Can't find vote author recipient")
            return
        }

        guard
            let interaction = try interactionStore.fetchMessage(
                timestamp: UInt64(targetPollTimestamp),
                incomingMessageAuthor: targetPollAuthorAci == localAci ? nil : targetPollAuthorAci,
                transaction: tx,
            ), let interactionId = interaction.grdbId?.int64Value
        else {
            Logger.error("Can't find vote poll")
            return
        }

        _ = try pollStore.updatePollWithVotes(
            interactionId: interactionId,
            optionsVoted: optionIndexes,
            voteAuthorId: localAuthorRecipientId,
            voteCount: voteCount,
            transaction: tx,
        )

        // Touch message so it reloads to show updated vote state.
        db.touch(interaction: interaction, shouldReindex: false, tx: tx)
    }

    public func applyPendingVoteToLocalState(
        pollInteraction: TSInteraction,
        optionIndex: UInt32,
        isUnvote: Bool,
        thread: TSGroupThread,
        tx: DBWriteTransaction,
    ) throws -> OutgoingPollVoteMessage? {
        guard
            let pollInteractionId = pollInteraction.grdbId?.int64Value,
            let poll = try pollStore.pollForInteractionId(
                interactionId: pollInteractionId,
                transaction: tx,
            )
        else {
            Logger.error("Can't find target poll")
            return nil
        }

        guard let localAci = accountManager.localIdentifiers(tx: tx)?.aci else {
            Logger.error("Can't find local ACI")
            return nil
        }

        var authorAci: Aci?
        if let _ = pollInteraction as? TSOutgoingMessage {
            authorAci = localAci
        } else if
            let incomingPoll = pollInteraction as? TSIncomingMessage,
            let authorUUID = incomingPoll.authorUUID,
            let incomingAci = try ServiceId.parseFrom(serviceIdString: authorUUID) as? Aci
        {
            authorAci = incomingAci
        }

        guard let authorAci else {
            Logger.error("Invalid poll message")
            return nil
        }

        guard
            let localRecipientId = recipientDatabaseTable.fetchRecipient(
                serviceId: localAci,
                transaction: tx,
            )?.id
        else {
            Logger.error("Can't find vote author recipient")
            return nil
        }

        guard
            let newHighestVoteCount = try pollStore.applyPendingVote(
                interactionId: pollInteractionId,
                localRecipientId: localRecipientId,
                optionIndex: optionIndex,
                isUnvote: isUnvote,
                transaction: tx,
            )
        else {
            return nil
        }

        var optionIndexVotes: [UInt32] = []
        if poll.allowsMultiSelect {
            optionIndexVotes = try pollStore.optionIndexVotesIncludingPending(
                interactionId: pollInteractionId,
                voteAuthorId: localRecipientId,
                voteCount: newHighestVoteCount,
                transaction: tx,
            ).map { UInt32($0) }
        } else {
            // Single select, only need to send latest vote (or empty if its an unvote).
            if !isUnvote {
                optionIndexVotes.append(optionIndex)
            }
        }

        return OutgoingPollVoteMessage(
            thread: thread,
            targetPollTimestamp: pollInteraction.timestamp,
            targetPollAuthorAci: authorAci,
            voteOptionIndexes: optionIndexVotes,
            voteCount: UInt32(newHighestVoteCount),
            tx: tx,
        )
    }
}

// MARK: - Backups

public struct BackupsPollData {
    public struct BackupsPollOption {
        public struct BackupsPollVote {
            let voteAuthorId: SignalRecipient.RowId
            let voteCount: UInt32
        }

        let text: String
        let votes: [BackupsPollVote]
    }

    let question: String
    let options: [BackupsPollOption]
    let allowMultiple: Bool
    let isEnded: Bool

    public init(
        question: String,
        allowMultiple: Bool,
        isEnded: Bool,
        options: [BackupsPollOption],
    ) {
        self.question = question
        self.options = options
        self.allowMultiple = allowMultiple
        self.isEnded = isEnded
    }
}

extension PollMessageManager {
    public func buildPollForBackup(
        message: TSMessage,
        messageRowId: Int64,
        tx: DBReadTransaction,
    ) -> BackupArchive.ArchiveSingleFrameResult<BackupsPollData, BackupArchive.InteractionUniqueId> {
        guard let question = message.body?.nilIfEmpty else {
            return .failure(.archiveFrameError(.pollMessageMissingQuestionBody, BackupArchive.InteractionUniqueId(interaction: message)))
        }

        return pollStore.backupPollData(
            question: question,
            message: message,
            interactionId: messageRowId,
            transaction: tx,
        )
    }

    public func restorePollFromBackup(
        pollBackupData: BackupsPollData,
        message: TSMessage,
        chatItemId: BackupArchive.ChatItemId,
        tx: DBWriteTransaction,
    ) -> BackupArchive.RestoreFrameResult<BackupArchive.ChatItemId> {
        guard let interactionId = message.grdbId?.int64Value else {
            return .failure([.restoreFrameError(
                .databaseModelMissingRowId(modelClass: type(of: message)),
                chatItemId,
            )])
        }

        do {
            try pollStore.createPoll(
                interactionId: interactionId,
                allowsMultiSelect: pollBackupData.allowMultiple,
                options: pollBackupData.options.map(\.text),
                transaction: tx,
            )
        } catch {
            return .failure([.restoreFrameError(
                .pollCreateFailedToInsertInDatabase,
                chatItemId,
            )])
        }

        var partialErrors = [BackupArchive.RestoreFrameError<BackupArchive.ChatItemId>]()

        var votesByAuthorId: [Int64: [OWSPoll.OptionIndex]] = [:]
        var voteCountByAuthorId: [Int64: UInt32] = [:]

        for (index, optionData) in pollBackupData.options.enumerated() {
            for vote in optionData.votes {
                votesByAuthorId[vote.voteAuthorId, default: []].append(OWSPoll.OptionIndex(index))
                if let currentVoteCount = voteCountByAuthorId[vote.voteAuthorId] {
                    if vote.voteCount != currentVoteCount {
                        partialErrors += [.restoreFrameError(
                            .invalidProtoData(.pollVoteCountRepeated),
                            chatItemId,
                        )]
                        continue
                    }
                } else {
                    voteCountByAuthorId[vote.voteAuthorId] = vote.voteCount
                }
            }
        }

        for (voteAuthorId, optionIndices) in votesByAuthorId {
            guard let voteCount = voteCountByAuthorId[voteAuthorId] else {
                partialErrors += [.restoreFrameError(
                    .invalidProtoData(.noPollVoteCountForAuthor),
                    chatItemId,
                )]
                continue
            }

            do {
                _ = try pollStore.updatePollWithVotes(
                    interactionId: interactionId,
                    optionsVoted: optionIndices,
                    voteAuthorId: voteAuthorId,
                    voteCount: voteCount,
                    transaction: tx,
                )
            } catch {
                partialErrors += [.restoreFrameError(
                    .pollVoteFailedToInsertInDatabase,
                    chatItemId,
                )]
            }
        }

        do {
            if pollBackupData.isEnded {
                try pollStore.terminatePoll(interactionId: interactionId, transaction: tx)
            }
        } catch {
            partialErrors += [.restoreFrameError(
                .pollTerminateFailedToInsertInDatabase,
                chatItemId,
            )]
        }

        if partialErrors.isEmpty {
            return .success
        }

        return .partialRestore(partialErrors)
    }
}
