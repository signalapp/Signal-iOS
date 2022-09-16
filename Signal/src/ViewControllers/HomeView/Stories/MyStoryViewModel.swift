//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

struct MyStoryViewModel: Dependencies {
    let messages: [StoryMessage]

    let latestMessageAttachment: StoryThumbnailView.Attachment?
    let latestMessageTimestamp: UInt64?
    let sendingCount: UInt64

    enum FailureState {
        case none
        case partial
        case complete
    }
    let failureState: FailureState

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
            latestMessageAttachment = .from(latestMessage.attachment, transaction: transaction)
            latestMessageTimestamp = latestMessage.timestamp
        } else {
            latestMessageAttachment = nil
            latestMessageTimestamp = nil
        }

        if let secondLatestMessage = sortedFilteredMessages.dropLast().last {
            secondLatestMessageAttachment = .from(secondLatestMessage.attachment, transaction: transaction)
        } else {
            secondLatestMessageAttachment = nil
        }
    }
}
