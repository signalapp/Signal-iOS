//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class EditManager {

    internal enum Constants {
        // Edits will only be received for up to 24 hours from the
        // original message
        static let editWindow: UInt64 = UInt64(kDayInterval * 1000)

        // Receiving more than this number of edits on the same message
        // will result in subsequent edits being dropped
        static let maxReceiveEdits: UInt = UInt(100)
    }

    public struct Context {
        let dataStore: EditManager.Shims.DataStore
        let groupsShim: EditManager.Shims.Groups
        let linkPreviewShim: EditManager.Shims.LinkPreview

        public init(
            dataStore: EditManager.Shims.DataStore,
            groupsShim: EditManager.Shims.Groups,
            linkPreviewShim: EditManager.Shims.LinkPreview
        ) {
            self.dataStore = dataStore
            self.groupsShim = groupsShim
            self.linkPreviewShim = linkPreviewShim
        }
    }

    private let context: Context

    public init(context: Context) {
        self.context = context
    }

    public func processIncomingEditMessage(
        _ newDataMessage: SSKProtoDataMessage,
        thread: TSThread,
        targetMessage: TSMessage?,
        serverTimestamp: UInt64,
        tx: DBWriteTransaction
    ) -> TSMessage? {

        guard let targetMessage = targetMessage as? MessageCopyable else {
            // Unsupported type
            Logger.warn("Edit cannot find the target message")
            return nil
        }

        guard checkForValidEdit(
            thread: thread,
            targetMessage: targetMessage.message,
            editMessage: newDataMessage,
            serverTimestamp: serverTimestamp,
            tx: tx)
        else { return nil }

        // Create a copy of the existing message and update with the edit
        let editedMessage = createEditedMessage(
            thread: thread,
            targetMessage: targetMessage,
            editMessage: newDataMessage,
            tx: tx
        )
        context.dataStore.updateEditedMessage(message: editedMessage, tx: tx)

        // Insert a new copy of the original message to preserve edit history.
        let newMessage = targetMessage.createMessageCopy(
            dataStore: context.dataStore,
            thread: thread,
            isLatestRevision: false,
            tx: tx,
            updateBlock: nil
        )
        context.dataStore.insertMessageCopy(message: newMessage, tx: tx)

        if
            let originalId = editedMessage.grdbId?.int64Value,
            let editId = newMessage.grdbId?.int64Value
        {
            let editRecord = EditRecord(
                latestRevisionId: originalId,
                pastRevisionId: editId
            )
            context.dataStore.insertEditRecord(record: editRecord, tx: tx)
        } else {
            owsFailDebug("Missing EditRecord IDs")
        }

        return editedMessage
    }

    /// Creates a new message with the following steps:
    ///     1. Create a MessageBuilder based on the original message
    ///     2. Update the fields on the builder targeted by the edit
    ///     3. Build a new copy of the message.  This message will have a new grdbId/uniqueId
    ///     4. Swap the grdbId/uniqueId of the original message into this new copy.
    ///
    /// Using a MesageBuilder in this way allows creating an updated version of an existing
    /// message, while preserving the readonly behavior of the TSMessage
    private func createEditedMessage(
        thread: TSThread,
        targetMessage: MessageCopyable,
        editMessage: SSKProtoDataMessage,
        tx: DBWriteTransaction
    ) -> TSMessage {

        var bodyRanges: MessageBodyRanges?
        if !editMessage.bodyRanges.isEmpty {
            bodyRanges = MessageBodyRanges(protos: editMessage.bodyRanges)
        }

        var linkPreview: OWSLinkPreview?
        if editMessage.preview.isEmpty.negated {
            do {
                // NOTE: Currently makes no attempt to reuse existing link previews
                linkPreview = try context.linkPreviewShim.buildPreview(
                    dataMessage: editMessage,
                    tx: tx
                )
            } catch {
                owsFailDebug("Failed to build link preview")
            }
        }

        let editedMessage = targetMessage.createMessageCopy(
            dataStore: context.dataStore,
            thread: thread,
            isLatestRevision: true,
            tx: tx
        ) { builder in

            builder.messageBody = editMessage.body
            builder.bodyRanges = bodyRanges
            builder.linkPreview = linkPreview
            builder.timestamp = editMessage.timestamp

            // If the editMessage quote field is present, preserve the exisiting
            // quote. If the field is nil, remove any quote on the current message.
            let preserveExistingQuote = (editMessage.quote != nil)
            if
                targetMessage.message.quotedMessage != nil,
                !preserveExistingQuote
            {
                builder.quotedMessage = nil
            }

            // Reconcile the new and old attachments.
            // This currently only affects the long text attachment but could
            // expand out to removing/adding other attachments in the future.
            builder.attachmentIds = self.updateAttachments(
                targetMessage: targetMessage.message,
                editMessage: editMessage,
                tx: tx
            )
        }

        // Swap out the newly created grdbId/uniqueId with the
        // one from the original message
        // This prevents needing to expose things like uniqueID as
        // writeable on the base model objects.
        if let rowId = targetMessage.message.grdbId {
            editedMessage.replaceRowId(
                rowId.int64Value,
                uniqueId: targetMessage.message.uniqueId
            )
            editedMessage.replaceSortId(targetMessage.message.sortId)
        } else {
            owsFailDebug("Missing edit target rowID")
        }

        return editedMessage
    }

    private func checkForValidEdit(
        thread: TSThread,
        targetMessage: TSMessage,
        editMessage: SSKProtoDataMessage,
        serverTimestamp: UInt64,
        tx: DBReadTransaction
    ) -> Bool {

        // check edit window (by comparing target message server timestamp
        // and incoming edit server timestamp)
        // drop silent and warn if outside of valid range
        switch targetMessage {
        case let incomingMessage as TSIncomingMessage:
            guard let originalServerTimestamp = incomingMessage.serverTimestamp?.uint64Value else {
                Logger.warn("Edit message target doesn't have a server timestamp")
                return false
            }

            let (result, isOverflow) = originalServerTimestamp.addingReportingOverflow(Constants.editWindow)
            guard !isOverflow && serverTimestamp <= result else {
                Logger.warn("Message edit outside of allowed timeframe")
                return false
            }
        case is TSOutgoingMessage:
            // Don't validate the edit window for outgoing/sync messages
            break
        default:
            owsFailDebug("Can't edit message of type \(type(of: targetMessage))")
            return false
        }

        let numberOfEdits = context.dataStore.numberOfEdits(for: targetMessage, tx: tx)
        if numberOfEdits >= Constants.maxReceiveEdits {
            Logger.warn("Message edited too many times")
            return false
        }

        // If this is a group message, validate edit groupID matches the target
        if let groupThread = thread as? TSGroupThread {
            guard
                let data = context.groupsShim.groupId(for: editMessage),
                data.groupId == groupThread.groupModel.groupId
            else {
                Logger.warn("Edit message group does not match target message")
                return false
            }
        }

        // Skip remotely deleted
        if targetMessage.wasRemotelyDeleted {
            Logger.warn("Edit message group does not match target message")
            return false
        }

        // Skip view-once
        if targetMessage.isViewOnceMessage {
            Logger.warn("View once edits not supported")
            return false
        }

        let currentAttachments = context.dataStore.getMediaAttachments(
            message: targetMessage,
            tx: tx
        )

        if currentAttachments.filter({ $0.isVoiceMessage }).isEmpty.negated {
            // This will bail if it finds a voice memo
            // Might be able to handle image attachemnts, but fail for now.
            Logger.warn("Voice message edits not supported")
            return false
        }

        // Skip contact shares
        if targetMessage.contactShare != nil {
            Logger.warn("Contact share edits not supported")
            return false
        }

        return true
    }

    private func updateAttachments(
        targetMessage: TSMessage,
        editMessage: SSKProtoDataMessage,
        tx: DBWriteTransaction
    ) -> [String] {

        let newAttachments = TSAttachmentPointer.attachmentPointers(
            fromProtos: editMessage.attachments,
            albumMessage: targetMessage
        )

        // check for any oversized text in the edit
        let oversizeText = newAttachments.filter({ $0.isOversizeText }).first

        // check for existing oversized text
        let existingText = context.dataStore.getOversizedTextAttachments(
            message: targetMessage,
            tx: tx
        )

        var newAttachmentIds = targetMessage.attachmentIds.filter { $0 != existingText?.uniqueId }
        if let oversizeText {
            // insert the new oversized text attachment
            context.dataStore.insertAttachment(attachment: oversizeText, tx: tx)
            newAttachmentIds.append(oversizeText.uniqueId)
        }

        return newAttachmentIds
    }
}

private protocol MessageCopyable {
    var message: TSMessage { get }

    func createMessageCopy(
        dataStore: EditManager.Shims.DataStore,
        thread: TSThread,
        isLatestRevision: Bool,
        tx: DBWriteTransaction,
        updateBlock: ((TSMessageBuilder) -> Void)?
    ) -> TSMessage
}

extension TSIncomingMessage: MessageCopyable {
    fileprivate var message: TSMessage { return self }

    fileprivate func createMessageCopy(
        dataStore: EditManager.Shims.DataStore,
        thread: TSThread,
        isLatestRevision: Bool,
        tx: DBWriteTransaction,
        updateBlock: ((TSMessageBuilder) -> Void)?
    ) -> TSMessage {

        let builder = TSIncomingMessageBuilder(
            thread: thread,
            timestamp: self.timestamp,
            authorAddress: self.authorAddress,
            sourceDeviceId: self.sourceDeviceId,
            messageBody: self.body,
            bodyRanges: self.bodyRanges,
            attachmentIds: self.attachmentIds,
            editState: isLatestRevision ? .latestRevision : .pastRevision,
            expiresInSeconds: isLatestRevision ? self.expiresInSeconds : 0,
            expireStartedAt: self.expireStartedAt,
            quotedMessage: self.quotedMessage,
            contactShare: self.contactShare,
            linkPreview: self.linkPreview,
            messageSticker: self.messageSticker,
            read: !isLatestRevision,
            serverTimestamp: self.serverTimestamp,
            serverDeliveryTimestamp: self.serverDeliveryTimestamp,
            serverGuid: self.serverGuid,
            wasReceivedByUD: self.wasReceivedByUD,
            isViewOnceMessage: self.isViewOnceMessage,
            storyAuthorAddress: self.storyAuthorAddress,
            storyTimestamp: self.storyTimestamp?.uint64Value,
            storyReactionEmoji: self.storyReactionEmoji,
            giftBadge: self.giftBadge
        )

        updateBlock?(builder)

        let message = builder.build()

        return message
    }
}

extension TSOutgoingMessage: MessageCopyable {
    fileprivate var message: TSMessage { return self }

    fileprivate func createMessageCopy(
        dataStore: EditManager.Shims.DataStore,
        thread: TSThread,
        isLatestRevision: Bool,
        tx: DBWriteTransaction,
        updateBlock: ((TSMessageBuilder) -> Void)?
    ) -> TSMessage {

        let builder = TSOutgoingMessageBuilder(
            thread: thread,
            timestamp: self.timestamp,
            messageBody: self.body,
            bodyRanges: self.bodyRanges,
            attachmentIds: self.attachmentIds,
            editState: isLatestRevision ? .latestRevision : .pastRevision,
            expiresInSeconds: isLatestRevision ? self.expiresInSeconds : 0,
            quotedMessage: self.quotedMessage,
            contactShare: self.contactShare,
            linkPreview: self.linkPreview,
            messageSticker: self.messageSticker,
            isViewOnceMessage: self.isViewOnceMessage,
            storyAuthorAddress: self.storyAuthorAddress,
            storyTimestamp: self.storyTimestamp?.uint64Value,
            storyReactionEmoji: self.storyReactionEmoji,
            giftBadge: self.giftBadge
        )

        updateBlock?(builder)

        let message = dataStore.createOutgoingMessage(with: builder, tx: tx)

        // Need to copy over the recipient address from the old message
        dataStore.copyRecipients(from: self, to: message, tx: tx)

        return message
    }
}
