//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class EditManager {

    internal enum Constants {
        static let editWindow: UInt64 = UInt64(kDayInterval * 1000)
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
        serverTimestamp: UInt64,
        targetTimestamp: UInt64,
        author: SignalServiceAddress,
        tx: DBWriteTransaction
    ) -> TSMessage? {

        // Find the target message to edit.
        // This will implicily validate that the sender of the
        // edited message is the author of the original message.
        guard let targetMessage = context.dataStore.findTargetMessage(
            timestamp: targetTimestamp,
            author: author,
            tx: tx
        ) as? TSIncomingMessage else {
            // TODO[EditMessage]: if orig message doesn't exist, put in
            // early receipt cache
            Logger.warn("Edit cannot find the target message")
            return nil
        }

        guard checkForValidEdit(
            thread: thread,
            targetMessage: targetMessage,
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

        // Insert a new copy of the original message to preserve the
        // edit history.
        let newMessageBuilder = targetMessage.createCopyBuilder(
            thread: thread,
            isLatestRevision: false
        )
        let newMessage = newMessageBuilder.build()
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
    internal func createEditedMessage(
        thread: TSThread,
        targetMessage: TSIncomingMessage,
        editMessage: SSKProtoDataMessage,
        tx: DBWriteTransaction
    ) -> TSIncomingMessage {

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

        let builder = targetMessage.createCopyBuilder(
            thread: thread,
            isLatestRevision: true
        )
        builder.messageBody = editMessage.body
        builder.bodyRanges = bodyRanges
        builder.linkPreview = linkPreview
        builder.timestamp = editMessage.timestamp

        // If the editMessage quote field is present, preserve the exisiting
        // quote. If the field is nil, remove any quote on the current message.
        // TODO: [Edit] Wrap editMessage proto in an object that can clarify
        // things like quote logic (change quote to a preserveQuote boolean)
        let preserveExistingQuote = (editMessage.quote != nil)
        if
            targetMessage.quotedMessage != nil,
            !preserveExistingQuote
        {
            builder.quotedMessage = nil
        }

        // Reconcile the new and old attachments
        // This currenly only affects the long text attachment
        // but could expand out to removing/adding attachments in the future.
        builder.attachmentIds = updateAttachments(
            targetMessage: targetMessage,
            editMessage: editMessage,
            tx: tx
        )

        // Swap out the newly created grdbId/uniqueId with the
        // one from the original message
        // This prevents needing to expose things like uniqueID as
        // writeable on the base model objects.
        let editedMessage = builder.build()
        if let rowId = targetMessage.grdbId {
            editedMessage.replaceRowId(
                rowId.int64Value,
                uniqueId: targetMessage.uniqueId
            )
        } else {
            owsFailDebug("Missing edit target rowID")
        }

        return editedMessage
    }

    internal func checkForValidEdit(
        thread: TSThread,
        targetMessage: TSMessage,
        editMessage: SSKProtoDataMessage,
        serverTimestamp: UInt64,
        tx: DBReadTransaction
    ) -> Bool {

        // check edit window (using incoming server timestamp)
        //  drop silent and warn if outside of valid range
        let editWindow = Constants.editWindow
        let endEditTime = targetMessage.receivedAtTimestamp
        if endEditTime + editWindow < serverTimestamp {
            Logger.warn("Edit message outside of allowed timeframe")
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

        // TODO[Edit Message]: skip expired messages

        let currentAttachments = context.dataStore.getMediaAttachments(
            message: targetMessage,
            tx: tx
        )

        if currentAttachments.filter({ $0.isVoiceMessage }).isEmpty.negated {
            // This will bail if it finds a voice memo
            // Might be able to handle image attachemnts, but fail for now.
            // Voice memo?
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

    internal func updateAttachments(
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

extension TSIncomingMessage {
    fileprivate func createCopyBuilder(
        thread: TSThread,
        isLatestRevision: Bool
    ) -> TSIncomingMessageBuilder {
        let builder = TSIncomingMessageBuilder(
            thread: thread,
            timestamp: self.timestamp,
            authorAddress: self.authorAddress,
            sourceDeviceId: self.sourceDeviceId,
            messageBody: self.body,
            bodyRanges: self.bodyRanges,
            attachmentIds: self.attachmentIds,
            editState: isLatestRevision ? .latestRevision : .pastRevision,
            expiresInSeconds: self.expiresInSeconds,
            expireStartedAt: self.expireStartedAt,
            quotedMessage: self.quotedMessage,
            contactShare: self.contactShare,
            linkPreview: self.linkPreview,
            messageSticker: self.messageSticker,
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
        return builder
    }
}
