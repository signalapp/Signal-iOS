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

    // MARK: - Incoming Edit Processing

    // Process incoming data message
    // 1) Check the external edit for valid field values
    // 2) Call shared code to create new copies/records
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

        var bodyRanges: MessageBodyRanges?
        if !newDataMessage.bodyRanges.isEmpty {
            bodyRanges = MessageBodyRanges(protos: newDataMessage.bodyRanges)
        }

        var linkPreview: OWSLinkPreview?
        if newDataMessage.preview.isEmpty.negated {
            do {
                // NOTE: Currently makes no attempt to reuse existing link previews
                linkPreview = try context.linkPreviewShim.buildPreview(
                    dataMessage: newDataMessage,
                    tx: tx
                )
            } catch {
                owsFailDebug("Failed to build link preview")
            }
        }

        let targetMessageWrapper = editTarget.wrapper

        // Create a copy of the existing message and update with the edit
        let editedMessage = createEditedMessage(
            thread: thread,
            editTarget: targetMessageWrapper,
            tx: tx
        ) { builder in

            builder.messageBody = newDataMessage.body
            builder.bodyRanges = bodyRanges
            builder.linkPreview = linkPreview
            builder.timestamp = newDataMessage.timestamp

            // If the editMessage quote field is present, preserve the exisiting
            // quote. If the field is nil, remove any quote on the current message.
            if
                targetMessageWrapper.message.quotedMessage != nil,
                newDataMessage.quote == nil
            {
                builder.quotedMessage = nil
            }

            // Reconcile the new and old attachments.
            // This currently only affects the long text attachment but could
            // expand out to removing/adding other attachments in the future.
            builder.attachmentIds = self.updateAttachments(
                targetMessage: targetMessageWrapper.message,
                editMessage: newDataMessage,
                tx: tx
            )
        }

        insertEditCopies(
            thread: thread,
            editedMessage: editedMessage,
            editTarget: targetMessageWrapper,
            tx: tx
        )

        return editedMessage
    }

    // MARK: - Outgoing Edit Send

    /// Creates a copy of the passed in `targetMessage`, then constructs
    /// an `OutgoingEditMessage` with this new copy.  Note that this only creates an
    /// in-memory copy and doesn't persist the new message.
    public func createOutgoingEditMessage(
        targetMessage: TSOutgoingMessage,
        thread: TSThread,
        tx: DBReadTransaction,
        updateBlock: @escaping ((TSOutgoingMessageBuilder) -> Void)
    ) -> OutgoingEditMessage {

        let editTarget = OutgoingEditMessageWrapper(message: targetMessage)

        let editedMessage = createEditedMessage(
            thread: thread,
            editTarget: editTarget,
            tx: tx
        ) { messageBuilder in
            updateBlock(messageBuilder)
            messageBuilder.timestamp = NSDate.ows_millisecondTimeStamp()
        }

        return context.dataStore.createOutgoingEditMessage(
            thread: thread,
            targetMessageTimestamp: targetMessage.timestamp,
            editMessage: editedMessage,
            tx: tx
        )
    }

    /// Fetches a fresh version of the message targeted by `OutgoingEditMessage`,
    /// and creates the necessary copies of the edits in the database.
    public func insertOutgoingEditRevisions(
        for outgoingEditMessage: OutgoingEditMessage,
        thread: TSThread,
        tx: DBWriteTransaction
    ) {
        guard let editTarget = context.dataStore.findEditTarget(
            timestamp: outgoingEditMessage.targetMessageTimestamp,
            authorAci: nil,
            tx: tx
        ) else {
            owsFailDebug("Failed to find target message")
            return
        }

        insertEditCopies(
            thread: thread,
            editedMessage: outgoingEditMessage.editedMessage,
            editTarget: editTarget.wrapper,
            tx: tx
        )
    }

    // MARK: - Edit Utilities

    // The method used for updating the database with both incoming
    // and outgoing edits.
    private func insertEditCopies<EditTarget: EditMessageWrapper> (
        thread: TSThread,
        editedMessage: TSMessage,
        editTarget: EditTarget,
        tx: DBWriteTransaction
    ) {
        // Update the exiting message with edited fields
        context.dataStore.updateEditedMessage(message: editedMessage, tx: tx)

        // Create a new copy of the original message
        let newMessage = editTarget.createMessageCopy(
            dataStore: context.dataStore,
            thread: thread,
            isLatestRevision: false,
            tx: tx,
            updateBlock: nil
        )

        // Insert a new copy of the original message to preserve edit history.
        context.dataStore.insertMessageCopy(message: newMessage, tx: tx)

        // Update the newly inserted message with any data that needs to be
        // copied from the original message
        editTarget.updateMessageCopy(
            dataStore: context.dataStore,
            newMessageCopy: newMessage,
            tx: tx
        )

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
    }

    /// Creates a new message with the following steps:
    ///     1. Create a MessageBuilder based on the original message
    ///     2. Update the fields on the builder targeted by the edit
    ///     3. Build a new copy of the message.  This message will have a new grdbId/uniqueId
    ///     4. Swap the grdbId/uniqueId of the original message into this new copy.
    ///
    /// Using a MesageBuilder in this way allows creating an updated version of an existing
    /// message, while preserving the readonly behavior of the TSMessage
    private func createEditedMessage<EditTarget: EditMessageWrapper>(
        thread: TSThread,
        editTarget: EditTarget,
        tx: DBReadTransaction,
        editBlock: @escaping ((EditTarget.MessageBuilderType) -> Void)
    ) -> EditTarget.MessageType {

        let editedMessage = editTarget.createMessageCopy(
            dataStore: context.dataStore,
            thread: thread,
            isLatestRevision: true,
            tx: tx) { builder in
            // Apply the edits to the new copy
            editBlock(builder)
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

    // MARK: - Incoming Edit Validation

    private func checkForValidEdit(
        thread: TSThread,
        editTarget: EditMessageTarget,
        editMessage: SSKProtoDataMessage,
        serverTimestamp: UInt64,
        tx: DBReadTransaction
    ) -> Bool {
        let targetMessage = editTarget.wrapper.message

        // check edit window (by comparing target message server timestamp
        // and incoming edit server timestamp)
        // drop silent and warn if outside of valid range
        switch editTarget {
        case .incomingMessage(let incomingMessage):
            guard let originalServerTimestamp = incomingMessage.message.serverTimestamp?.uint64Value else {
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
