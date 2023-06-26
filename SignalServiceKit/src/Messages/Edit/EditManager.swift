//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

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
        editTarget: EditMessageTarget,
        serverTimestamp: UInt64,
        tx: DBWriteTransaction
    ) -> TSMessage? {

        guard checkForValidEdit(
            thread: thread,
            editTarget: editTarget,
            editMessage: newDataMessage,
            serverTimestamp: serverTimestamp,
            tx: tx)
        else { return nil }

        // Create a copy of the existing message and update with the edit
        let editedMessage = createEditedMessage(
            thread: thread,
            editTarget: editTarget,
            editMessage: newDataMessage,
            tx: tx
        )
        context.dataStore.updateEditedMessage(message: editedMessage, tx: tx)

        // Insert a new copy of the original message to preserve edit history.
        let newMessage = editTarget.createMessageCopy(
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
        editTarget: EditMessageTarget,
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

        let editedMessage = editTarget.createMessageCopy(
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
            if editTarget.message.quotedMessage != nil, !preserveExistingQuote {
                builder.quotedMessage = nil
            }

            // Reconcile the new and old attachments.
            // This currently only affects the long text attachment but could
            // expand out to removing/adding other attachments in the future.
            builder.attachmentIds = self.updateAttachments(
                targetMessage: editTarget.message,
                editMessage: editMessage,
                tx: tx
            )
        }

        // Swap out the newly created grdbId/uniqueId with the
        // one from the original message
        // This prevents needing to expose things like uniqueID as
        // writeable on the base model objects.
        if let rowId = editTarget.message.grdbId {
            editedMessage.replaceRowId(
                rowId.int64Value,
                uniqueId: editTarget.message.uniqueId
            )
            editedMessage.replaceSortId(editTarget.message.sortId)
        } else {
            owsFailDebug("Missing edit target rowID")
        }

        return editedMessage
    }

    private func checkForValidEdit(
        thread: TSThread,
        editTarget: EditMessageTarget,
        editMessage: SSKProtoDataMessage,
        serverTimestamp: UInt64,
        tx: DBReadTransaction
    ) -> Bool {
        let targetMessage = editTarget.message

        // check edit window (by comparing target message server timestamp
        // and incoming edit server timestamp)
        // drop silent and warn if outside of valid range
        switch editTarget {
        case .incomingMessage(let incomingMessage):
            guard let originalServerTimestamp = incomingMessage.serverTimestamp?.uint64Value else {
                Logger.warn("Edit message target doesn't have a server timestamp")
                return false
            }

            let (result, isOverflow) = originalServerTimestamp.addingReportingOverflow(Constants.editWindow)
            guard !isOverflow && serverTimestamp <= result else {
                Logger.warn("Message edit outside of allowed timeframe")
                return false
            }
        case .outgoingMessage:
            // Don't validate the edit window for outgoing/sync messages
            break
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

private extension EditMessageTarget {
    func createMessageCopy(
        dataStore: EditManager.Shims.DataStore,
        thread: TSThread,
        isLatestRevision: Bool,
        tx: DBWriteTransaction,
        updateBlock: ((TSMessageBuilder) -> Void)?
    ) -> TSMessage {
        switch self {
        case .incomingMessage(let message):
            let builder = TSIncomingMessageBuilder(
                thread: thread,
                timestamp: message.timestamp,
                authorAddress: message.authorAddress,
                sourceDeviceId: message.sourceDeviceId,
                messageBody: message.body,
                bodyRanges: message.bodyRanges,
                attachmentIds: message.attachmentIds,
                editState: isLatestRevision ? .latestRevision : .pastRevision,
                expiresInSeconds: isLatestRevision ? message.expiresInSeconds : 0,
                expireStartedAt: message.expireStartedAt,
                quotedMessage: message.quotedMessage,
                contactShare: message.contactShare,
                linkPreview: message.linkPreview,
                messageSticker: message.messageSticker,
                read: !isLatestRevision,
                serverTimestamp: message.serverTimestamp,
                serverDeliveryTimestamp: message.serverDeliveryTimestamp,
                serverGuid: message.serverGuid,
                wasReceivedByUD: message.wasReceivedByUD,
                isViewOnceMessage: message.isViewOnceMessage,
                storyAuthorAddress: message.storyAuthorAddress,
                storyTimestamp: message.storyTimestamp?.uint64Value,
                storyReactionEmoji: message.storyReactionEmoji,
                giftBadge: message.giftBadge
            )
            updateBlock?(builder)
            return builder.build()

        case .outgoingMessage(let message):
            let builder = TSOutgoingMessageBuilder(
                thread: thread,
                timestamp: message.timestamp,
                messageBody: message.body,
                bodyRanges: message.bodyRanges,
                attachmentIds: message.attachmentIds,
                editState: isLatestRevision ? .latestRevision : .pastRevision,
                expiresInSeconds: isLatestRevision ? message.expiresInSeconds : 0,
                quotedMessage: message.quotedMessage,
                contactShare: message.contactShare,
                linkPreview: message.linkPreview,
                messageSticker: message.messageSticker,
                isViewOnceMessage: message.isViewOnceMessage,
                storyAuthorAddress: message.storyAuthorAddress,
                storyTimestamp: message.storyTimestamp?.uint64Value,
                storyReactionEmoji: message.storyReactionEmoji,
                giftBadge: message.giftBadge
            )
            updateBlock?(builder)
            let messageCopy = dataStore.createOutgoingMessage(with: builder, tx: tx)
            // Need to copy over the recipient address from the old message
            dataStore.copyRecipients(from: message, to: messageCopy, tx: tx)
            return messageCopy
        }
    }
}
