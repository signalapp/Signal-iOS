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
        voteCount: UInt32,
        transaction: DBWriteTransaction
    ) throws {
        guard let poll = try pollForInteractionId(
            interactionId: interactionId,
            transaction: transaction
        ), let pollId = poll.id else {
            Logger.error("Can't find target poll")
            return
        }

        guard !poll.isEnded else {
            Logger.error("Poll has ended, dropping vote")
            return
        }

        guard optionsVoted.count <= 1 || poll.allowsMultiSelect else {
            Logger.error("Poll doesn't support multiselect but multiple options were voted for")
            return
        }

        let pollOptionRecords = try optionsForPoll(
            pollId: pollId,
            transaction: transaction
        )

        let optionIdMap: [Int64] = pollOptionRecords.compactMap { $0.id }
        let currentVotes = try votesForPoll(
            voteAuthorId: voteAuthorId,
            optionIds: optionIdMap,
            transaction: transaction
        )

        if !currentVotes.isEmpty {
            let maxVoteCount = currentVotes.map { $0.voteCount }.max()
            guard let maxVoteCount, maxVoteCount < voteCount else {
                Logger.error("Ignoring vote interactionId \(interactionId), optionsVote \(optionsVoted) because it is not most recent")
                return
            }

            for oldVotes in currentVotes {
                try oldVotes.delete(transaction.database)
            }
        }

        let optionIndexMap = Dictionary(uniqueKeysWithValues: pollOptionRecords.map { ($0.optionIndex, $0) })
        for optionIndex in optionsVoted {
            guard let option = optionIndexMap[Int32(optionIndex)],
                  let optionId = option.id else {
                owsFailDebug("Can't find target option")
                continue
            }
            var pollVoteRecord = PollVoteRecord(
                optionId: optionId,
                voteAuthorId: voteAuthorId,
                voteCount: 1
            )
            try pollVoteRecord.insert(transaction.database)
        }
    }

    private func pollForInteractionId(
        interactionId: Int64,
        transaction: DBReadTransaction
    ) throws -> PollRecord? {
        return try PollRecord
            .filter(Column(PollRecord.CodingKeys.interactionId.rawValue) == interactionId)
            .fetchOne(transaction.database)
    }

    private func optionsForPoll(
        pollId: Int64,
        transaction: DBReadTransaction
    ) throws -> [PollOptionRecord] {
        return try PollOptionRecord
            .filter(Column(PollOptionRecord.CodingKeys.pollId.rawValue) == pollId)
            .fetchAll(transaction.database)
    }

    private func votesForPoll(
        voteAuthorId: Int64,
        optionIds: [Int64],
        transaction: DBReadTransaction
    ) throws -> [PollVoteRecord] {
        return try PollVoteRecord
            .filter(optionIds.contains(Column(PollVoteRecord.CodingKeys.optionId.rawValue)))
            .filter(Column(PollVoteRecord.CodingKeys.voteAuthorId.rawValue) == voteAuthorId)
            .fetchAll(transaction.database)
    }

    public func terminatePoll(
        interactionId: Int64,
        transaction: DBWriteTransaction
    ) throws {
        try PollRecord
            .filter(Column(PollRecord.CodingKeys.interactionId.rawValue) == interactionId)
            .updateAll(transaction.database, [PollRecord.Columns.isEnded.set(to: true)])
    }

    public func owsPoll(
        question: String,
        interactionId: Int64,
        transaction: DBReadTransaction,
        ownerIsLocalUser: Bool
    ) throws -> OWSPoll? {
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
            interactionId: interactionId,
            question: question,
            options: optionStrings,
            allowsMultiSelect: poll.allowsMultiSelect,
            votes: votes,
            isEnded: poll.isEnded,
            ownerIsLocalUser: ownerIsLocalUser
        )
    }
}
