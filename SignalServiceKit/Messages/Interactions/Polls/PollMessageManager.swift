//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public class PollMessageManager {
    static let pollEmoji = "📊"

    private let pollStore: PollStore
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let interactionStore: InteractionStore
    private let db: DB
    private let accountManager: TSAccountManager

    init(
        pollStore: PollStore,
        recipientDatabaseTable: RecipientDatabaseTable,
        interactionStore: InteractionStore,
        accountManager: TSAccountManager,
        db: DB
    ) {
        self.pollStore = pollStore
        self.recipientDatabaseTable = recipientDatabaseTable
        self.interactionStore = interactionStore
        self.accountManager = accountManager
        self.db = db
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

        guard let localAci = accountManager.localIdentifiers(tx: transaction)?.aci else {
            throw OWSAssertionError("User not registered")
        }

        guard let targetMessage = try interactionStore.fetchMessage(
            timestamp: pollVoteProto.targetSentTimestamp,
            incomingMessageAuthor: localAci == pollAuthorAci ? nil : pollAuthorAci,
            transaction: transaction
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

        guard let localAci = accountManager.localIdentifiers(tx: transaction)?.aci else {
            throw OWSAssertionError("User not registered")
        }

        guard let targetMessage = try interactionStore.fetchMessage(
            timestamp: pollTerminateProto.targetSentTimestamp,
            incomingMessageAuthor: terminateAuthor == localAci ? nil : terminateAuthor,
            transaction: transaction
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
        guard let interactionId = message.grdbId?.int64Value,
              let question = message.body else {
            return nil
        }

        return try pollStore.owsPoll(
            question: question,
            interactionId: interactionId,
            transaction: transaction,
            ownerIsLocalUser: message.isOutgoing
        )
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

    public func sendPollTerminateMessage(poll: OWSPoll, thread: TSGroupThread) throws {
        try db.write { tx in
            guard let targetPoll = interactionStore.fetchInteraction(rowId: poll.interactionId, tx: tx) else {
                return
            }

            try pollStore.terminatePoll(interactionId: poll.interactionId, transaction: tx)

            // Touch message so it reloads to show poll ended state.
            SSKEnvironment.shared.databaseStorageRef.touch(interaction: targetPoll, shouldReindex: false, tx: tx)

            let pollTerminateMessage = OutgoingPollTerminateMessage(
                thread: thread,
                targetPollTimestamp: targetPoll.timestamp,
                tx: tx
            )

            let preparedMessage = PreparedOutgoingMessage.preprepared(
                transientMessageWithoutAttachments: pollTerminateMessage
            )

            SSKEnvironment.shared.messageSenderJobQueueRef.add(
                message: preparedMessage,
                transaction: tx
            )

            guard let localAci = accountManager.localIdentifiers(tx: tx)?.aci else {
                throw OWSAssertionError("User not registered")
            }

            insertInfoMessageForEndPoll(
                timestamp: Date().ows_millisecondsSince1970,
                groupThread: thread,
                targetPollTimestamp: targetPoll.timestamp,
                pollQuestion: poll.question,
                terminateAuthor: localAci,
                tx: tx
            )
        }
    }

    public func insertInfoMessageForEndPoll(
        timestamp: UInt64,
        groupThread: TSGroupThread,
        targetPollTimestamp: UInt64,
        pollQuestion: String,
        terminateAuthor: Aci,
        tx: DBWriteTransaction
    ) {
        var userInfoForNewMessage: [InfoMessageUserInfoKey: Any] = [:]
        userInfoForNewMessage[.endPoll] = PersistableEndPollItem(
            question: pollQuestion,
            authorServiceIdBinary: terminateAuthor.serviceIdBinary,
            timestamp: Int64(targetPollTimestamp)
        )

        let infoMessage = TSInfoMessage(
            thread: groupThread,
            timestamp: timestamp,
            serverGuid: nil,
            messageType: .typeEndPoll,
            infoMessageUserInfo: userInfoForNewMessage
        )

        infoMessage.anyInsert(transaction: tx)
    }
}
