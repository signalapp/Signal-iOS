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
    let hasFailedSends: Bool

    let secondLatestMessageAttachment: StoryThumbnailView.Attachment?

    init(messages: [StoryMessage], transaction: SDSAnyReadTransaction) {
        sendingCount = messages.reduce(0) {
            $0 + ([.sending, .pending].contains($1.sendingState) ? 1 : 0)
        }
        hasFailedSends = messages.contains { $0.sendingState == .failed }

        let sortedFilteredMessages = messages.sorted { $0.timestamp < $1.timestamp }.prefix(2)
        self.messages = Array(sortedFilteredMessages)

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
