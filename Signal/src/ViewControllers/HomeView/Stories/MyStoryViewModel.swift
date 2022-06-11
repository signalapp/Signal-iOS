//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit

struct MyStoryViewModel: Dependencies {
    let messages: [StoryMessage]

    let latestMessageAttachment: StoryThumbnailView.Attachment?
    let latestMessageTimestamp: UInt64?

    let secondLatestMessageAttachment: StoryThumbnailView.Attachment?

    init(messages: [StoryMessage], transaction: SDSAnyReadTransaction) {
        let sortedFilteredMessages = messages.sorted { $0.timestamp < $1.timestamp }
        self.messages = sortedFilteredMessages

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
