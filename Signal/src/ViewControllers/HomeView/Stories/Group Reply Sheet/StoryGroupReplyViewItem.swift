//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import UIKit

class StoryGroupReplyViewItem: Dependencies {
    let displayableText: DisplayableText?
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

        self.cellType = .standalone
    }
}
