//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc
public class OutgoingMessagePreparer: NSObject {

    public let message: TSOutgoingMessage
    private let unsavedAttachmentInfos: [OutgoingAttachmentInfo]
    private var didCompletePrep = false
    public private(set) var savedAttachmentIds: [String]?

    public var unpreparedMessage: TSOutgoingMessage {
        assert(!didCompletePrep)
        if let message = message as? OutgoingEditMessage {
            return message.editedMessage
        } else {
            return message
        }
    }

    public convenience init(_ message: TSOutgoingMessage) {
        self.init(message, unsavedAttachmentInfos: [])
    }

    public init(_ message: TSOutgoingMessage, unsavedAttachmentInfos: [OutgoingAttachmentInfo]) {
        self.message = message
        self.unsavedAttachmentInfos = unsavedAttachmentInfos
    }

    public func insertMessage(
        linkPreviewDraft: OWSLinkPreviewDraft? = nil,
        transaction: SDSAnyWriteTransaction
    ) {
        if let message = message as? OutgoingEditMessage {
            // Write changes and insert new edit revisions/records
            guard let thread = message.thread(tx: transaction) else {
                owsFailDebug("Outgoing edit message missing thread.")
                return
            }
            DependenciesBridge.shared.editManager.insertOutgoingEditRevisions(
                for: message,
                thread: thread,
                tx: transaction.asV2Write
            )
        } else {
            unpreparedMessage.anyInsert(transaction: transaction)
        }

        if let linkPreviewDraft = linkPreviewDraft {
            do {
                let linkPreview = try OWSLinkPreview.buildValidatedLinkPreview(fromInfo: linkPreviewDraft,
                                                                               transaction: transaction)
                unpreparedMessage.update(with: linkPreview, transaction: transaction)
            } catch {
                Logger.error("error: \(error)")
            }
        }
    }

    public var canBePreparedWithoutTransaction: Bool {
        assert(!didCompletePrep)

        guard unsavedAttachmentInfos.isEmpty else {
            return false
        }
        guard unpreparedMessage.allAttachmentIds().isEmpty else {
            return false
        }
        guard unpreparedMessage.messageSticker == nil else {
            return false
        }
        guard unpreparedMessage.quotedMessage == nil else {
            return false
        }
        guard !message.hasFailedRecipients() else {
            return false
        }
        return true
    }

    public func prepareMessageWithoutTransaction() -> TSOutgoingMessage {
        assert(!didCompletePrep)
        assert(canBePreparedWithoutTransaction)

        self.savedAttachmentIds = []
        didCompletePrep = true
        return message
    }

    // NOTE: Any changes to this method should be reflected in canBePreparedWithoutTransaction.
    public func prepareMessage(transaction: SDSAnyWriteTransaction) throws -> TSOutgoingMessage {
        assert(!didCompletePrep)

        if unsavedAttachmentInfos.count > 0 {
            // Eventually we'll pad all outgoing attachments, but currently just stickers.
            // Currently this method is only used to process "body" attachments, which
            // cannot be sent along with stickers.
            owsAssertDebug(unpreparedMessage.messageSticker == nil)

            let isVoiceMessage = unpreparedMessage.isVoiceMessage
            let attachmentStreams = try unsavedAttachmentInfos.map {
                try $0.asStreamConsumingDataSource(isVoiceMessage: isVoiceMessage)
            }

            unpreparedMessage.anyUpdateOutgoingMessage(transaction: transaction) { unpreparedMessage in
                var attachmentIds = unpreparedMessage.attachmentIds
                attachmentIds.append(contentsOf: attachmentStreams.map { $0.uniqueId })
                unpreparedMessage.attachmentIds = attachmentIds
            }

            attachmentStreams.forEach { $0.anyInsert(transaction: transaction) }
        }

        self.savedAttachmentIds = Self.prepareAttachments(message: unpreparedMessage, tx: transaction)

        // When we start a message send, all "failed" recipients should be marked as "sending".
        unpreparedMessage.updateAllUnsentRecipientsAsSending(transaction: transaction)

        didCompletePrep = true
        return message
    }

    private static func prepareAttachments(message: TSOutgoingMessage, tx: SDSAnyWriteTransaction) -> [String] {
        var attachmentIds = [String]()

        attachmentIds.append(contentsOf: message.attachmentIds)

        if message.quotedMessage?.thumbnailAttachmentId != nil {
            // We need to update the message record here to reflect the new attachments we may create.
            message.anyUpdateOutgoingMessage(transaction: tx) { message in
                let thumbnail = message.quotedMessage?.createThumbnailIfNecessary(with: tx)
                thumbnail.map { attachmentIds.append($0.uniqueId) }
            }
        }

        if let contactShare = message.contactShare, contactShare.avatarAttachmentId != nil {
            let attachmentStream = contactShare.avatarAttachment(with: tx) as? TSAttachmentStream
            owsAssertDebug(attachmentStream != nil)
            attachmentStream.map { attachmentIds.append($0.uniqueId) }
        }

        if let linkPreview = message.linkPreview, let attachmentId = linkPreview.imageAttachmentId {
            let attachmentStream = TSAttachmentStream.anyFetchAttachmentStream(uniqueId: attachmentId, transaction: tx)
            owsAssertDebug(attachmentStream != nil)
            attachmentStream.map { attachmentIds.append($0.uniqueId) }
        }

        if let messageSticker = message.messageSticker {
            let attachmentId = messageSticker.attachmentId
            let attachmentStream = TSAttachmentStream.anyFetchAttachmentStream(uniqueId: attachmentId, transaction: tx)
            owsAssertDebug(attachmentStream != nil)
            attachmentStream.map { attachmentIds.append($0.uniqueId) }
        }

        return attachmentIds
    }
}

extension TSOutgoingMessage {
    @objc
    public var asPreparer: OutgoingMessagePreparer {
        return OutgoingMessagePreparer(self)
    }
}
