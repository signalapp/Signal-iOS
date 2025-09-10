//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

public class PollStore {
    public func createPoll(
        interactionId: Int64,
        allowsMultiSelect: Bool,
        options: [String],
        transaction: DBWriteTransaction
    ) throws {
        var pollRecord = PollRecord(
            interactionId: interactionId,
            allowsMultiSelect: allowsMultiSelect
        )
        try pollRecord.insert(transaction.database)

        guard let pollID = pollRecord.id else {
            owsFailDebug("Poll failed to insert")
            return
        }

        for (index, option) in options.enumerated() {
            var pollOptionRecord = PollOptionRecord(
                pollId: pollID,
                option: option,
                optionIndex: Int32(index)
            )
            try pollOptionRecord.insert(transaction.database)
        }
    }

    public func updatePollWithVotes(
        interactionId: Int64,
        optionsVoted: [OWSPoll.OptionIndex],
        voteAuthorId: Int64,
        transaction: DBWriteTransaction
    ) throws {
        // TODO: Implement me
    }

    public func terminatePoll(
        interactionId: Int64,
        transaction: DBWriteTransaction
    ) throws {
        try PollRecord
            .filter(Column(PollRecord.CodingKeys.interactionId.rawValue) == interactionId)
            .updateAll(transaction.database, [PollRecord.Columns.isEnded.set(to: true)])
    }

    public func owsPoll(question: String, interactionId: Int64, transaction: DBReadTransaction) throws -> OWSPoll? {
        guard let poll = try PollRecord
            .filter(PollRecord.Columns.interactionId == interactionId)
            .fetchOne(transaction.database),
        let pollId = poll.id
        else {
            owsFailDebug("No poll found")
            return nil
        }

        var optionStrings: [String] = []
        var votes: [OWSPoll.OptionIndex: [Aci]] = [:]

        let optionRows = try PollOptionRecord
            .filter(PollOptionRecord.Columns.pollId == pollId)
            .fetchAll(transaction.database)

        for optionRow in optionRows {
            optionStrings.append(optionRow.option)

            let voteRows = try PollVoteRecord
                .filter(PollVoteRecord.Columns.optionId == optionRow.id)
                .fetchAll(transaction.database)

            for voteRow in voteRows {
                guard let recipient = try SignalRecipient
                    .filter(voteRow.voteAuthorId == Column(SignalRecipient.CodingKeys.id.rawValue))
                    .fetchOne(transaction.database),
                      let aci = recipient.aci
                else {
                    owsFailDebug("Vote author not found in recipients table")
                    return nil
                }

                let index = OWSPoll.OptionIndex(optionRow.optionIndex)
                var currentAcis = votes[index] ?? []
                currentAcis.append(aci)
                votes[index] = currentAcis
            }
        }

        return OWSPoll(
            pollId: pollId,
            question: question,
            options: optionStrings,
            allowsMultiSelect: poll.allowsMultiSelect,
            votes: votes,
            isEnded: poll.isEnded
        )
    }
}
