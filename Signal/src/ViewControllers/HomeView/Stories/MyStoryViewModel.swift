//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

struct MyStoryViewModel: Dependencies {
    let messages: [StoryMessage]

    let latestMessageIdentifier: InteractionSnapshotIdentifier?
    let latestMessageAttachment: StoryThumbnailView.Attachment?
    let latestMessageTimestamp: UInt64?
    let sendingCount: UInt64

    enum FailureState {
        case none
        case partial
        case complete
    }
    let failureState: FailureState

    let secondLatestMessageIdentifier: InteractionSnapshotIdentifier?
    let secondLatestMessageAttachment: StoryThumbnailView.Attachment?

    init(messages: [StoryMessage], transaction: SDSAnyReadTransaction) {
        sendingCount = messages.reduce(0) {
            $0 + ([.sending, .pending].contains($1.sendingState) ? 1 : 0)
        }

        let sortedFilteredMessages = messages.sorted { $0.timestamp < $1.timestamp }.suffix(2)
        self.messages = Array(sortedFilteredMessages)

        if let latestFailedMessage = sortedFilteredMessages.last(where: { $0.sendingState == .failed }) {
            failureState = latestFailedMessage.hasSentToAnyRecipients ? .partial : .complete
        } else {
            failureState = .none
        }

        if let latestMessage = sortedFilteredMessages.last {
            latestMessageIdentifier = .fromStoryMessage(latestMessage)
            latestMessageAttachment = .from(latestMessage, transaction: transaction)
            latestMessageTimestamp = latestMessage.timestamp
        } else {
            latestMessageIdentifier = nil
            latestMessageAttachment = nil
            latestMessageTimestamp = nil
        }

        if let secondLatestMessage = sortedFilteredMessages.dropLast().last {
            secondLatestMessageIdentifier = .fromStoryMessage(secondLatestMessage)
            secondLatestMessageAttachment = .from(secondLatestMessage, transaction: transaction)
        } else {
            secondLatestMessageIdentifier = nil
            secondLatestMessageAttachment = nil
        }
    }
}
