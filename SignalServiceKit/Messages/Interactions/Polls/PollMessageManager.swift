//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public class PollMessageManager {
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

    public func processIncomingPollVote(
        voteAuthor: Aci,
        pollVoteProto: SSKProtoDataMessagePollVote,
        transaction: DBWriteTransaction
    ) throws {
        guard let aciBinary = pollVoteProto.targetAuthorAciBinary,
              let pollAuthorAci = try? Aci.parseFrom(serviceIdBinary: aciBinary)
        else {
            Logger.error("Failure to parse Aci from binary")
            return
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
            return
        }

        let signalRecipient = recipientDatabaseTable.fetchRecipient(serviceId: voteAuthor, transaction: transaction)

        guard let voteAuthorId = signalRecipient?.id else {
            Logger.error("Can't find voter in recipient table")
            return
        }

        try pollStore.updatePollWithVotes(
            interactionId: interactionId,
            optionsVoted: pollVoteProto.optionIndexes,
            voteAuthorId: voteAuthorId,
            transaction: transaction
        )
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
}
