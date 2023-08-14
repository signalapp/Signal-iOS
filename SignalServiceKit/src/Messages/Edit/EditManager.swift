//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public enum EditSendValidationError: Error {
    case editDisabled
    case messageTypeNotSupported
    case messageNotFound
    case editWindowClosed
    case tooManyEdits(UInt)
}

extension EditSendValidationError: LocalizedError {
    public var errorDescription: String? {
        localizedDescription
    }

    public var localizedDescription: String {
        switch self {
        case .editWindowClosed:
            return OWSLocalizedString(
                "EDIT_MESSAGE_SEND_MESSAGE_TOO_OLD_ERROR",
                comment: "Error message to display to user when a messaeg is too old to edit"
            )
        case .tooManyEdits(let numEdits):
            return String.localizedStringWithFormat(
                OWSLocalizedString(
                    "EDIT_MESSAGE_SEND_TOO_MANY_EDITS_ERROR",
                    tableName: "PluralAware",
                    comment: "Error message to display to user when edit limit reached"
                ),
                numEdits
            )
        default:
            return OWSLocalizedString(
                "EDIT_MESSAGE_SEND_MESSAGE_UNKNOWN_ERROR",
                comment: "Edit failed for an unexpected reason"
            )
        }
    }
}

public class EditManager {

    internal enum Constants {
        // RECEIVE

        // Edits will only be received for up to 48 hours from the
        // original message
        static let editWindowMilliseconds: UInt64 = UInt64(kHourInterval * 48 * 1000)

        // Receiving more than this number of edits on the same message
        // will result in subsequent edits being dropped
        static let maxReceiveEdits: UInt = UInt(100)

        // SEND

        // Edits can only be sent for up to 24 hours from the
        // original message
        static let editSendWindowMilliseconds: UInt64 = UInt64(kHourInterval * 24 * 1000)

        // Message can only be edited 10 times
        static let maxSendEdits: UInt = UInt(10)

        // EDUCATION

        static let collectionName: String = "EditManager"
        static let shouldShowEditSendBetaWarning: String = "shouldShowEditSendBetaWarning"
    }

    public struct Context {
        let dataStore: EditManager.Shims.DataStore
        let groupsShim: EditManager.Shims.Groups
        let keyValueStoreFactory: KeyValueStoreFactory
        let linkPreviewShim: EditManager.Shims.LinkPreview
        let receiptManagerShim: EditManager.Shims.ReceiptManager

        public init(
            dataStore: EditManager.Shims.DataStore,
            groupsShim: EditManager.Shims.Groups,
            keyValueStoreFactory: KeyValueStoreFactory,
            linkPreviewShim: EditManager.Shims.LinkPreview,
            receiptManagerShim: EditManager.Shims.ReceiptManager
        ) {
            self.dataStore = dataStore
            self.groupsShim = groupsShim
            self.keyValueStoreFactory = keyValueStoreFactory
            self.linkPreviewShim = linkPreviewShim
            self.receiptManagerShim = receiptManagerShim
        }
    }

    private let context: Context
    private let keyValueStore: KeyValueStore

    public init(context: Context) {
        self.context = context
        self.keyValueStore = context.keyValueStoreFactory.keyValueStore(collection: Constants.collectionName)
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

    // MARK: - Edit UI Validation

    public static func canShowEditMenu(interaction: TSInteraction, thread: TSThread) -> Bool {
        return Self.validateCanShowEditMenu(interaction: interaction, thread: thread) == nil
    }

    private static func validateCanShowEditMenu(interaction: TSInteraction, thread: TSThread) -> EditSendValidationError? {
        guard FeatureFlags.editMessageSend else { return .editDisabled }
        guard let message = interaction as? TSOutgoingMessage else { return .messageTypeNotSupported }

        if !Self.editMessageTypeSupported(message: message) {
            return .messageTypeNotSupported
        }

        if !thread.isNoteToSelf {
            let (result, isOverflow) = interaction.timestamp.addingReportingOverflow(Constants.editSendWindowMilliseconds)
            guard !isOverflow && Date.ows_millisecondTimestamp() <= result else {
                return .editWindowClosed
            }
        }
        return nil
    }

    public func validateCanSendEdit(
        targetMessageTimestamp: UInt64,
        thread: TSThread,
        tx: DBReadTransaction
    ) -> EditSendValidationError? {
        guard FeatureFlags.editMessageSend else { return .editDisabled }

        guard let editTarget = context.dataStore.findEditTarget(
            timestamp: targetMessageTimestamp,
            authorAci: nil,
            tx: tx
        ) else {
            owsFailDebug("Target edit message missing")
            return .messageNotFound
        }

        guard case .outgoingMessage(let targetMessageWrapper) = editTarget else {
            return .messageNotFound
        }

        let targetMessage = targetMessageWrapper.message

        if let error = Self.validateCanShowEditMenu(interaction: targetMessage, thread: thread) {
            return error
        }

        let numberOfEdits = context.dataStore.numberOfEdits(for: targetMessage, tx: tx)
        if !thread.isNoteToSelf && numberOfEdits >= Constants.maxSendEdits {
            return .tooManyEdits(Constants.maxSendEdits)
        }

        return nil
    }

    public func shouldShowEditSendBetaConfirmation(tx: DBReadTransaction) -> Bool {
        return keyValueStore.getBool(
            Constants.shouldShowEditSendBetaWarning,
            defaultValue: true,
            transaction: tx
        )
    }

    public func setShouldShowEditSendBetaConfirmation(_ shouldShow: Bool, tx: DBWriteTransaction) {
        keyValueStore.setBool(
            shouldShow,
            key: Constants.shouldShowEditSendBetaWarning,
            transaction: tx
        )
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
                pastRevisionId: editId,
                read: editTarget.wasRead
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

            let (result, isOverflow) = originalServerTimestamp.addingReportingOverflow(Constants.editWindowMilliseconds)
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

        if !Self.editMessageTypeSupported(message: targetMessage) {
            Logger.warn("Edit of message type not supported")
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

        return true
    }

    private static func editMessageTypeSupported(message: TSMessage) -> Bool {
        // Skip remotely deleted
        if message.wasRemotelyDeleted {
            return false
        }

        // Skip view-once
        if message.isViewOnceMessage {
            return false
        }

        // Skip contact shares
        if message.contactShare != nil {
            return false
        }

        if message.messageSticker != nil {
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

    // MARK: - Edit Revision Read State

    public func markEditRevisionsAsRead(
        for edit: TSMessage,
        thread: TSThread,
        tx: DBWriteTransaction
    ) throws {
        try context.dataStore
            .findEditHistory(for: edit, tx: tx)
            .lazy
            .filter { item in
                !item.0.read
            }
            .forEach { item in
                guard let message = item.1 as? TSIncomingMessage else { return }
                var record: EditRecord = item.0

                record.read = true
                try self.context.dataStore.update(editRecord: record, tx: tx)

                self.context.receiptManagerShim.messageWasRead(
                    message,
                    thread: thread,
                    circumstance: .onThisDevice,
                    tx: tx
                )
            }
    }
}

public extension EditManager {

    /// Check if the message is an old edit revision.
    ///
    /// Past edits will still technically be part of a conversation,
    /// but they should be hidden from operations that are determining
    /// latest messages for things like sorting conversations.
    static func isPastEditRevision(message: TSMessage) -> Bool {
        return message.editState == .pastRevision
    }
}
