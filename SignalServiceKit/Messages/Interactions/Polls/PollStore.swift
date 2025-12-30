//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
public import LibSignalClient

public class PollStore {
    public func createPoll(
        interactionId: Int64,
        allowsMultiSelect: Bool,
        options: [String],
        transaction: DBWriteTransaction,
    ) throws {
        var pollRecord = PollRecord(
            interactionId: interactionId,
            allowsMultiSelect: allowsMultiSelect,
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
                optionIndex: Int32(index),
            )
            try pollOptionRecord.insert(transaction.database)
        }
    }

    public func terminatePoll(
        interactionId: Int64,
        transaction: DBWriteTransaction,
    ) throws {
        try PollRecord
            .filter(Column(PollRecord.CodingKeys.interactionId.rawValue) == interactionId)
            .updateAll(transaction.database, [PollRecord.Columns.isEnded.set(to: true)])
    }

    public func revertPollTerminate(
        interactionId: Int64,
        transaction: DBWriteTransaction,
    ) throws {
        try PollRecord
            .filter(Column(PollRecord.CodingKeys.interactionId.rawValue) == interactionId)
            .updateAll(transaction.database, [PollRecord.Columns.isEnded.set(to: false)])
    }

    public func owsPoll(
        question: String,
        message: TSMessage,
        localUser: Aci,
        transaction: DBReadTransaction,
        ownerIsLocalUser: Bool,
    ) throws -> OWSPoll? {
        guard let interactionId = message.grdbId?.int64Value else {
            owsFailDebug("No interactionId found")
            return nil
        }

        guard
            let poll = try PollRecord
                .filter(PollRecord.Columns.interactionId == interactionId)
                .fetchOne(transaction.database),
            let pollId = poll.id
        else {
            owsFailDebug("No poll found")
            return nil
        }

        var optionStrings: [String] = []
        var votes: [OWSPoll.OptionIndex: [Aci]] = [:]
        var pendingVotes: [OWSPoll.OptionIndex: OWSPoll.PendingVoteType] = [:]
        var maxPendingVoteCount: Int32 = 0

        let optionRows = try PollOptionRecord
            .filter(PollOptionRecord.Columns.pollId == pollId)
            .fetchAll(transaction.database)

        for optionRow in optionRows {
            optionStrings.append(optionRow.option)

            let voteRows = try PollVoteRecord
                .filter(PollVoteRecord.Columns.optionId == optionRow.id)
                .order(PollVoteRecord.Columns.voteCount.asc)
                .fetchAll(transaction.database)

            for voteRow in voteRows {
                guard
                    let recipient = try SignalRecipient
                        .filter(voteRow.voteAuthorId == Column(SignalRecipient.CodingKeys.id.rawValue))
                        .fetchOne(transaction.database),
                    let aci = recipient.aci
                else {
                    owsFailDebug("Vote author not found in recipients table")
                    return nil
                }

                let index = OWSPoll.OptionIndex(optionRow.optionIndex)

                if voteRow.voteState == .vote {
                    var currentAcis = votes[index] ?? []
                    currentAcis.append(aci)
                    votes[index] = currentAcis
                }

                if voteRow.voteState.isPending() {
                    if !poll.allowsMultiSelect, voteRow.voteState == .pendingVote {
                        // If most recent single select vote, visually "un-vote" everything else to avoid UX
                        // confusion, since only the latest vote will apply when pending vote messages send.
                        if voteRow.voteCount > maxPendingVoteCount {
                            for (_index, state) in pendingVotes {
                                if state == .pendingVote {
                                    pendingVotes[_index] = .pendingUnvote
                                }
                            }
                            maxPendingVoteCount = voteRow.voteCount
                            pendingVotes[index] = voteRow.voteState.isUnvote() ? .pendingUnvote : .pendingVote
                            continue
                        }
                        // Flip non-most-recent pending votes to pending unvote.
                        pendingVotes[index] = .pendingUnvote
                        continue
                    }
                    pendingVotes[index] = voteRow.voteState.isUnvote() ? .pendingUnvote : .pendingVote
                }
            }
        }

        return OWSPoll(
            interactionId: interactionId,
            question: question,
            options: optionStrings,
            localUserPendingState: pendingVotes,
            allowsMultiSelect: poll.allowsMultiSelect,
            votes: votes,
            isEnded: poll.isEnded,
            ownerIsLocalUser: ownerIsLocalUser,
        )
    }

    public func pollForInteractionId(
        interactionId: Int64,
        transaction: DBReadTransaction,
    ) throws -> PollRecord? {
        return try PollRecord
            .filter(Column(PollRecord.CodingKeys.interactionId.rawValue) == interactionId)
            .fetchOne(transaction.database)
    }

    // MARK: - Poll Voting

    typealias OptionId = Int64

    /// Updates a poll with the new snapshot of votes.
    /// Returns a bool indicating whether this new
    /// snapshot only "unvoted" options.
    public func updatePollWithVotes(
        interactionId: Int64,
        optionsVoted: [OWSPoll.OptionIndex],
        voteAuthorId: Int64,
        voteCount: UInt32,
        transaction: DBWriteTransaction,
    ) throws -> Bool {
        guard
            let poll = try pollForInteractionId(
                interactionId: interactionId,
                transaction: transaction,
            ), let pollId = poll.id
        else {
            Logger.error("Can't find target poll")
            return false
        }

        guard
            try checkValidVote(
                poll: poll,
                optionsVoted: optionsVoted,
                transaction: transaction,
            )
        else {
            return false
        }

        let highestVoteCount = try highestVoteCount(
            pollId: pollId,
            voteAuthorId: voteAuthorId,
            includePending: false,
            transaction: transaction,
        )

        guard highestVoteCount < voteCount else {
            Logger.error("Ignoring vote because it is not most recent")
            return false
        }

        /*
         Update votes with new vote state & count.

         The only thing we need to track about previous votes is whether something
         was previously voted for but is now not present in optionsVoted (the vote author's
         snapshot of all current votes). In this case, we will set voteState to "unvote".
         This preserves the usefulness of voteCount to avoid out-of-order votes,
         even when unvotes are involved.
         */

        let currentVoteOptionIds = try votesForPoll(
            pollId: pollId,
            voteAuthorId: voteAuthorId,
            voteCount: highestVoteCount,
            transaction: transaction,
        )

        let newVoteOptionIds = try voteOptionIds(
            from: optionsVoted,
            pollId: pollId,
            transaction: transaction,
        )

        // Delete vote counts up to and including the new one to clean up,
        // since those states are outdated now. This will delete anything
        // pending at the current vote count, which is OK because we are
        // about to insert them as completed below.
        try deleteAllVotes(
            for: voteAuthorId,
            pollId: pollId,
            minRequiredVoteCount: Int32(voteCount) + 1,
            transaction: transaction,
        )

        let unvotes = currentVoteOptionIds.subtracting(newVoteOptionIds)
        let votesToUpdate = Set(newVoteOptionIds).union(unvotes)

        for optionId in votesToUpdate {
            var pollVoteRecord = PollVoteRecord(
                optionId: optionId,
                voteAuthorId: voteAuthorId,
                voteCount: Int32(voteCount),
                voteState: unvotes.contains(optionId) ? .unvote : .vote,
            )
            try pollVoteRecord.insert(transaction.database)
        }

        return optionsVoted.isEmpty || Set(newVoteOptionIds).isSubset(of: currentVoteOptionIds)
    }

    private func checkValidVote(
        poll: PollRecord,
        optionsVoted: [OWSPoll.OptionIndex],
        transaction: DBReadTransaction,
    ) throws -> Bool {
        guard !poll.isEnded else {
            Logger.error("Poll has ended, dropping vote")
            return false
        }

        guard optionsVoted.count <= 1 || poll.allowsMultiSelect else {
            Logger.error("Poll doesn't support multi-select but multiple options were voted for")
            return false
        }

        return true
    }

    private func highestVoteCount(
        pollId: Int64,
        voteAuthorId: Int64,
        includePending: Bool,
        transaction: DBReadTransaction,
    ) throws -> Int32 {
        let optionIds = try PollOptionRecord
            .filter(PollOptionRecord.Columns.pollId == pollId)
            .select(PollOptionRecord.Columns.id)
            .asRequest(of: Row.self)
            .fetchAll(transaction.database)
            .compactMap { $0[PollOptionRecord.Columns.id] as? OptionId }

        var voteStatesToInclude = [VoteState.vote.rawValue, VoteState.unvote.rawValue]

        if includePending {
            voteStatesToInclude += [VoteState.pendingVote.rawValue, VoteState.pendingUnvote.rawValue]
        }

        let pollVoteRecord = try PollVoteRecord
            .filter(optionIds.contains(PollVoteRecord.Columns.optionId))
            .filter(PollVoteRecord.Columns.voteAuthorId == voteAuthorId)
            .filter(voteStatesToInclude.contains(PollVoteRecord.Columns.voteState))
            .select(max(PollVoteRecord.Columns.voteCount).forKey("maxVoteCount"))
            .asRequest(of: Row.self)
            .fetchOne(transaction.database)

        return pollVoteRecord?["maxVoteCount"] ?? 0
    }

    // Returns optionIds for votes with "vote" state for a given vote count.
    // This excludes unvotes, and pending votes.
    private func votesForPoll(
        pollId: Int64,
        voteAuthorId: Int64,
        voteCount: Int32,
        transaction: DBReadTransaction,
    ) throws -> Set<OptionId> {
        let optionIds = try PollOptionRecord
            .filter(PollOptionRecord.Columns.pollId == pollId)
            .select(PollOptionRecord.Columns.id)
            .asRequest(of: Row.self)
            .fetchAll(transaction.database)
            .compactMap { $0[PollOptionRecord.Columns.id] as? OptionId }

        let voteOptionIds = try PollVoteRecord
            .filter(optionIds.contains(PollVoteRecord.Columns.optionId))
            .filter(Column(PollVoteRecord.CodingKeys.voteAuthorId.rawValue) == voteAuthorId)
            .filter(PollVoteRecord.Columns.voteCount == voteCount)
            .filter(PollVoteRecord.Columns.voteState == VoteState.vote.rawValue)
            .select(PollVoteRecord.Columns.optionId)
            .asRequest(of: Row.self)
            .fetchAll(transaction.database)
            .compactMap { $0[PollVoteRecord.Columns.optionId] as? OptionId }

        return Set(voteOptionIds)
    }

    private func voteOptionIds(
        from optionIndexes: [OWSPoll.OptionIndex],
        pollId: Int64,
        transaction: DBReadTransaction,
    ) throws -> [OptionId] {
        return try PollOptionRecord
            .filter(PollOptionRecord.Columns.pollId == pollId)
            .filter(optionIndexes.contains(PollOptionRecord.Columns.optionIndex))
            .select(PollOptionRecord.Columns.id)
            .asRequest(of: Row.self)
            .fetchAll(transaction.database)
            .compactMap { $0[PollOptionRecord.Columns.id] as? OptionId }
    }

    private func deleteAllVotes(
        for voteAuthorId: Int64,
        pollId: Int64,
        minRequiredVoteCount: Int32,
        transaction: DBWriteTransaction,
    ) throws {
        let optionIds = try PollOptionRecord
            .filter(PollOptionRecord.Columns.pollId == pollId)
            .select(PollOptionRecord.Columns.id)
            .asRequest(of: Row.self)
            .fetchAll(transaction.database)
            .compactMap { $0[PollOptionRecord.Columns.id] as? OptionId }

        try PollVoteRecord
            .filter(optionIds.contains(PollVoteRecord.Columns.optionId))
            .filter(PollVoteRecord.Columns.voteAuthorId == voteAuthorId)
            .filter(PollVoteRecord.Columns.voteCount < minRequiredVoteCount)
            .deleteAll(transaction.database)
    }

    public func applyPendingVote(
        interactionId: Int64,
        localRecipientId: Int64,
        optionIndex: OWSPoll.OptionIndex,
        isUnvote: Bool,
        transaction: DBWriteTransaction,
    ) throws -> Int32? {
        guard
            let poll = try pollForInteractionId(
                interactionId: interactionId,
                transaction: transaction,
            ), let pollId = poll.id
        else {
            Logger.error("Can't find target poll")
            return nil
        }

        // Include pending here so we don't reuse an already-sent but not-yet-delivered vote count.
        let newHighestVoteCount = try highestVoteCount(
            pollId: pollId,
            voteAuthorId: localRecipientId,
            includePending: true,
            transaction: transaction,
        ) + 1

        guard
            let optionId = try voteOptionIds(
                from: [optionIndex],
                pollId: pollId,
                transaction: transaction,
            ).first
        else {
            Logger.error("Invalid option index")
            return nil
        }

        // Insert or update the db to apply the single pending vote/unvote.
        // Don't delete any previous state until we confirm the vote has been sent,
        // because we might need to roll back.
        var voteRecord = PollVoteRecord(
            optionId: optionId,
            voteAuthorId: localRecipientId,
            voteCount: newHighestVoteCount,
            voteState: isUnvote ? .pendingUnvote : .pendingVote,
        )

        try voteRecord.insert(transaction.database)

        return newHighestVoteCount
    }

    public func optionIndexVotesIncludingPending(
        interactionId: Int64,
        voteAuthorId: Int64,
        voteCount: Int32?,
        transaction: DBReadTransaction,
    ) throws -> [Int32] {
        guard
            let poll = try pollForInteractionId(
                interactionId: interactionId,
                transaction: transaction,
            ), let pollId = poll.id
        else {
            Logger.error("Can't find target poll")
            return []
        }

        let pollOptions = try PollOptionRecord
            .filter(PollOptionRecord.Columns.pollId == pollId)
            .fetchAll(transaction.database)

        let optionIdToIndex = Dictionary(uniqueKeysWithValues: pollOptions.map {
            (key: $0.id, value: $0.optionIndex)
        })

        let optionIds = optionIdToIndex.keys.compactMap { $0 }

        let pollVoteRecords = try PollVoteRecord
            .filter(optionIds.contains(PollVoteRecord.Columns.optionId))
            .filter(PollVoteRecord.Columns.voteAuthorId == voteAuthorId)
            .order(PollVoteRecord.Columns.voteCount)
            .fetchAll(transaction.database)

        var pollVoteRecordOptionIds: Set<OptionId> = Set()

        // Iterate over votes in order of increasing vote count
        // to make sure our state reflects the latest correct snapshot.
        // Include "pending" because this is what we send to other devices.
        // It will be updated to complete once the send succeeds.
        for voteRecord in pollVoteRecords {
            switch voteRecord.voteState {
            case .pendingVote, .vote:
                pollVoteRecordOptionIds.insert(voteRecord.optionId)
            case .pendingUnvote, .unvote:
                pollVoteRecordOptionIds.remove(voteRecord.optionId)
            }
        }

        return pollVoteRecordOptionIds.compactMap { optionIdToIndex[$0] }
    }

    public func revertVoteCount(
        voteCount: Int32,
        interactionId: Int64,
        voteAuthorId: Int64,
        transaction: DBWriteTransaction,
    ) throws {
        guard
            let poll = try pollForInteractionId(
                interactionId: interactionId,
                transaction: transaction,
            ), let pollId = poll.id
        else {
            Logger.error("Can't find target poll")
            return
        }

        guard
            let highestNonPendingVoteCount = try? highestVoteCount(
                pollId: pollId,
                voteAuthorId: voteAuthorId,
                includePending: false,
                transaction: transaction,
            )
        else {
            Logger.error("Couldn't get highest non-pending vote count")
            return
        }

        guard voteCount > highestNonPendingVoteCount else {
            Logger.error("Ignoring vote send failure, state has already moved on")
            return
        }

        let pollOptions = try PollOptionRecord
            .filter(PollOptionRecord.Columns.pollId == pollId)
            .fetchAll(transaction.database)
        let optionIds = pollOptions.compactMap { $0.id }

        try PollVoteRecord
            .filter(optionIds.contains(PollVoteRecord.Columns.optionId))
            .filter(PollVoteRecord.Columns.voteAuthorId == voteAuthorId)
            .filter(PollVoteRecord.Columns.voteCount == voteCount)
            .deleteAll(transaction.database)
    }
}

// MARK: - Backups

extension PollStore {
    public func backupPollData(
        question: String,
        message: TSMessage,
        interactionId: Int64,
        transaction: DBReadTransaction,
    ) -> BackupArchive.ArchiveSingleFrameResult<BackupsPollData, BackupArchive.InteractionUniqueId> {
        let interactionUniqueId = BackupArchive.InteractionUniqueId(interaction: message)
        var poll: PollRecord
        var pollId: Int64
        do {
            guard
                let wrappedPoll = try PollRecord
                    .filter(PollRecord.Columns.interactionId == interactionId)
                    .fetchOne(transaction.database),
                let wrappedPollId = wrappedPoll.id
            else {
                return .failure(.archiveFrameError(.pollMissing, interactionUniqueId))
            }
            poll = wrappedPoll
            pollId = wrappedPollId
        } catch {
            return .failure(.archiveFrameError(.invalidPollRecordDatabaseRow, interactionUniqueId))
        }

        var optionRows: [PollOptionRecord]
        do {
            optionRows = try PollOptionRecord
                .filter(PollOptionRecord.Columns.pollId == pollId)
                .fetchAll(transaction.database)
        } catch {
            return .failure(.archiveFrameError(.invalidPollOptionRecordDatabaseRow, interactionUniqueId))
        }

        var voteRows: [PollVoteRecord]
        do {
            let optionRowIds = optionRows.compactMap { $0.id }
            voteRows = try PollVoteRecord
                .filter(optionRowIds.contains(PollVoteRecord.Columns.optionId))
                .fetchAll(transaction.database)
        } catch {
            return .failure(.archiveFrameError(.invalidPollVoteRecordDatabaseRow, interactionUniqueId))
        }

        let optionIdToVotes = Dictionary(grouping: voteRows, by: { $0.optionId })

        var optionData: [BackupsPollData.BackupsPollOption] = []
        for optionRow in optionRows {
            guard let optionId = optionRow.id else {
                return .failure(.archiveFrameError(.pollOptionIdMissing, interactionUniqueId))
            }
            var votes: [BackupsPollData.BackupsPollOption.BackupsPollVote] = []
            for voteRow in optionIdToVotes[optionId] ?? [] {
                if voteRow.voteState == .vote {
                    votes.append(BackupsPollData.BackupsPollOption.BackupsPollVote(voteAuthorId: voteRow.voteAuthorId, voteCount: UInt32(voteRow.voteCount)))
                }
            }
            optionData.append(BackupsPollData.BackupsPollOption(text: optionRow.option, votes: votes))
        }

        return .success(BackupsPollData(
            question: question,
            allowMultiple: poll.allowsMultiSelect,
            isEnded: poll.isEnded,
            options: optionData,
        ))
    }
}
