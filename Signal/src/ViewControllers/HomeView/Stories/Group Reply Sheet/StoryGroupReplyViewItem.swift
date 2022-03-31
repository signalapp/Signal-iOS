//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import UIKit

class StoryGroupReplyViewItem: Dependencies {
    let interactionUniqueId: String
    let displayableText: DisplayableText?
    let reactionEmoji: String?
    let wasRemotelyDeleted: Bool
    let receivedAtTimestamp: UInt64
    let authorDisplayName: String?
    let authorAddress: SignalServiceAddress
    let authorColor: UIColor

    var cellType: StoryGroupReplyCell.CellType

    var timeString: String { DateUtil.formatMessageTimestampForCVC(receivedAtTimestamp, shouldUseLongFormat: false) }

    init(
        message: TSMessage,
        authorAddress: SignalServiceAddress,
        authorDisplayName: String?,
        authorColor: UIColor,
        transaction: SDSAnyReadTransaction
    ) {
        self.interactionUniqueId = message.uniqueId

        if !message.wasRemotelyDeleted {
            self.displayableText = DisplayableText.displayableText(
                withMessageBody: .init(text: message.body ?? "", ranges: message.bodyRanges ?? .empty),
                mentionStyle: .groupReply,
                transaction: transaction
            )
        } else {
            self.displayableText = nil
        }

        self.wasRemotelyDeleted = message.wasRemotelyDeleted
        self.receivedAtTimestamp = message.receivedAtTimestamp
        self.authorAddress = authorAddress
        self.authorDisplayName = authorDisplayName
        self.authorColor = authorColor

        if let reactionEmoji = message.storyReactionEmoji {
            self.cellType = .reaction
            self.reactionEmoji = reactionEmoji
        } else {
            self.cellType = .standalone
            self.reactionEmoji = nil
        }
    }
}
