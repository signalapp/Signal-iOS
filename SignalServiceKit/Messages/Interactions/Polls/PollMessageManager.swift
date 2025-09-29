//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

final public class PollMessageManager {
    static let pollEmoji = "📊"

    let pollStore: PollStore
    let recipientDatabaseTable: RecipientDatabaseTable
    let interactionStore: InteractionStore

    init(
        pollStore: PollStore,
        recipientDatabaseTable: RecipientDatabaseTable,
        interactionStore: InteractionStore
    ) {
        self.pollStore = pollStore
        self.recipientDatabaseTable = recipientDatabaseTable
        self.interactionStore = interactionStore
    }

    public func processIncomingPollCreate(
        interactionId: Int64,
        pollCreateProto: SSKProtoDataMessagePollCreate,
        transaction: DBWriteTransaction
    ) throws {
        try pollStore.createPoll(
            interactionId: interactionId,
            allowsMultiSelect: pollCreateProto.allowMultiple,
            options: pollCreateProto.options,
            transaction: transaction
        )
    }

    public func processOutgoingPollCreate(
        interactionId: Int64,
        pollOptions: [String],
        allowsMultiSelect: Bool,
        transaction: DBWriteTransaction
    ) throws {
        try pollStore.createPoll(
            interactionId: interactionId,
            allowsMultiSelect: allowsMultiSelect,
            options: pollOptions,
            transaction: transaction
        )
    }

    public func processIncomingPollVote(
        voteAuthor: Aci,
        pollVoteProto: SSKProtoDataMessagePollVote,
        transaction: DBWriteTransaction
    ) throws -> TSMessage? {
        guard let aciBinary = pollVoteProto.targetAuthorAciBinary,
              let pollAuthorAci = try? Aci.parseFrom(serviceIdBinary: aciBinary)
        else {
            Logger.error("Failure to parse Aci from binary")
            return nil
        }

        guard let targetMessage = try interactionStore.fetchMessage(
            timestamp: pollVoteProto.targetSentTimestamp,
            author: pollAuthorAci,
            transaction: transaction
        ) as? TSIncomingMessage,
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

        try pollStore.updatePollWithVotes(
            interactionId: interactionId,
            optionsVoted: pollVoteProto.optionIndexes,
            voteAuthorId: voteAuthorId,
            voteCount: pollVoteProto.voteCount,
            transaction: transaction
        )

        return targetMessage
    }

    public func processIncomingPollTerminate(
        pollTerminateProto: SSKProtoDataMessagePollTerminate,
        terminateAuthor: Aci,
        transaction: DBWriteTransaction
    ) throws -> TSMessage? {
        guard let targetMessage = try interactionStore.fetchMessage(
            timestamp: pollTerminateProto.targetSentTimestamp,
            author: terminateAuthor,
            transaction: transaction
        ) as? TSIncomingMessage,
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
        guard let interactionId = message.grdbId?.int64Value,
              let question = message.body else {
            return nil
        }

        return try pollStore.owsPoll(question: question, interactionId: interactionId, transaction: transaction)
    }

    public func buildProtoForSending(
        parentMessage: TSMessage,
        tx: DBReadTransaction
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
}
