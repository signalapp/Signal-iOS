//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class PollStore {
    public func createPoll(
        interactionId: Int64,
        allowMultiSelect: Bool,
        options: [String],
        transaction: DBWriteTransaction
    ) throws {
        var pollRecord = PollRecord(
            interactionId: interactionId,
            allowsMultiSelect: allowMultiSelect
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
}
