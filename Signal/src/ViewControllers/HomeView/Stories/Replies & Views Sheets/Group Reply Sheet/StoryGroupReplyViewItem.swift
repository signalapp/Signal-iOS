//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
    let recipientStatus: MessageReceiptStatus?

    var cellType: StoryGroupReplyCell.CellType

    var timeString: String { DateUtil.formatTimestampRelatively(receivedAtTimestamp) }

    init(
        message: TSMessage,
        authorAddress: SignalServiceAddress,
        authorDisplayName: String?,
        authorColor: UIColor,
        recipientStatus: MessageReceiptStatus?,
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
        self.recipientStatus = recipientStatus

        if let reactionEmoji = message.storyReactionEmoji {
            self.cellType = .init(kind: .reaction)
            self.reactionEmoji = reactionEmoji
        } else {
            self.cellType = .init(kind: .text)
            self.reactionEmoji = nil
        }
    }
}
