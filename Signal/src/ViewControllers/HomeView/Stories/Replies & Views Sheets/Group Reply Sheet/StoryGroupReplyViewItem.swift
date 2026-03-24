//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI
import UIKit

class StoryGroupReplyViewItem {
    let interactionIdentifier: InteractionSnapshotIdentifier
    let interactionUniqueId: String
    let displayableText: DisplayableText?
    let reactionEmoji: String?
    let reactionSticker: Attachment?
    let reactionStickerInfo: StickerInfo?
    let reactionStickerDownloadState: AttachmentDownloadState?
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
        transaction: DBReadTransaction,
    ) {
        self.interactionIdentifier = .fromInteraction(message)
        self.interactionUniqueId = message.uniqueId

        if !message.wasRemotelyDeleted {
            self.displayableText = DisplayableText.displayableText(
                withMessageBody: .init(text: message.body ?? "", ranges: message.bodyRanges ?? .empty),
                transaction: transaction,
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

            let attachmentStore = DependenciesBridge.shared.attachmentStore
            if
                let messageRowId = message.sqliteRowId,
                let attachment = attachmentStore.fetchAnyReferencedAttachment(
                    for: .messageSticker(messageRowId: messageRowId),
                    tx: transaction,
                ),
                let stickerInfo = message.messageSticker?.info
            {
                self.reactionSticker = attachment.attachment
                self.reactionStickerInfo = stickerInfo
                if attachment.attachment.asStream() == nil {
                    self.reactionStickerDownloadState = attachment.attachment
                        .asAnyPointer()?.downloadState(tx: transaction)
                } else {
                    self.reactionStickerDownloadState = nil
                }
            } else {
                self.reactionSticker = nil
                self.reactionStickerInfo = nil
                self.reactionStickerDownloadState = nil
            }
        } else {
            self.cellType = .init(kind: .text)
            self.reactionEmoji = nil
            self.reactionSticker = nil
            self.reactionStickerInfo = nil
            self.reactionStickerDownloadState = nil
        }
    }
}
