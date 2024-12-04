//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class EditManagerImpl: EditManager {

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
    }

    public struct Context {
        let attachmentStore: AttachmentStore
        let dataStore: EditManagerImpl.Shims.DataStore
        let editManagerAttachments: EditManagerAttachments
        let editMessageStore: EditMessageStore
        let receiptManagerShim: EditManagerImpl.Shims.ReceiptManager

        public init(
            attachmentStore: AttachmentStore,
            dataStore: EditManagerImpl.Shims.DataStore,
            editManagerAttachments: EditManagerAttachments,
            editMessageStore: EditMessageStore,
            receiptManagerShim: EditManagerImpl.Shims.ReceiptManager
        ) {
            self.attachmentStore = attachmentStore
            self.dataStore = dataStore
            self.editManagerAttachments = editManagerAttachments
            self.editMessageStore = editMessageStore
            self.receiptManagerShim = receiptManagerShim
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
        serverTimestamp: UInt64,
        serverGuid: String?,
        serverDeliveryTimestamp: UInt64,
        thread: TSThread,
        editTarget: EditMessageTarget,
        tx: DBWriteTransaction
    ) throws -> TSMessage {
        guard let threadRowId = thread.sqliteRowId else {
            throw OWSAssertionError("Can't apply edit in uninserted thread")
        }

        try checkForValidEdit(
            thread: thread,
            editTarget: editTarget,
            editMessage: newDataMessage,
            serverTimestamp: serverTimestamp,
            tx: tx
        )

        var bodyRanges: MessageBodyRanges?
        if !newDataMessage.bodyRanges.isEmpty {
            bodyRanges = MessageBodyRanges(protos: newDataMessage.bodyRanges)
        }

        let oversizeText = newDataMessage.attachments
            .first(where: {
                $0.contentType == MimeType.textXSignalPlain.rawValue
            })
            .map {
                MessageEdits.OversizeTextSource.proto($0)
            }

        let quotedReplyEdit: MessageEdits.Edit<Void> = {
            // If the editMessage quote field is present, preserve the exisiting
            // quote. If the field is nil, remove any quote on the current message.
            if newDataMessage.quote == nil {
                return .change(())
            }
            return .keep
        }()

        let linkPreview = newDataMessage.preview.first.map { MessageEdits.LinkPreviewSource.proto($0, newDataMessage) }

        let edits: MessageEdits = .forIncomingEdit(
            timestamp: .change(newDataMessage.timestamp),
            // Received now!
            receivedAtTimestamp: .change(Date.ows_millisecondTimestamp()),
            serverTimestamp: .change(serverTimestamp),
            serverDeliveryTimestamp: .change(serverDeliveryTimestamp),
            serverGuid: .change(serverGuid),
            body: .change(newDataMessage.body),
            bodyRanges: .change(bodyRanges)
        )

        let editedMessage = try applyAndInsertEdits(
            editTargetWrapper: editTarget.wrapper,
            editsToApply: edits,
            threadRowId: threadRowId,
            newOversizeText: oversizeText,
            quotedReplyEdit: quotedReplyEdit,
            newLinkPreview: linkPreview,
            tx: tx
        )

        return editedMessage
    }

    // MARK: - Edit UI Validation

    public func canShowEditMenu(interaction: TSInteraction, thread: TSThread) -> Bool {
        return Self.validateCanShowEditMenu(interaction: interaction, thread: thread, dataStore: context.dataStore) == nil
    }

    private static func validateCanShowEditMenu(
        interaction: TSInteraction,
        thread: TSThread,
        dataStore: EditManagerImpl.Shims.DataStore
    ) -> EditSendValidationError? {
        guard let message = interaction as? TSOutgoingMessage else { return .messageTypeNotSupported }

        if !Self.editMessageTypeSupported(message: message, dataStore: dataStore) {
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
        guard let editTarget = context.editMessageStore.editTarget(
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

        if let error = Self.validateCanShowEditMenu(interaction: targetMessage, thread: thread, dataStore: context.dataStore) {
            return error
        }

        let numberOfEdits = context.editMessageStore.numberOfEdits(for: targetMessage, tx: tx)
        if !thread.isNoteToSelf && numberOfEdits >= Constants.maxSendEdits {
            return .tooManyEdits(Constants.maxSendEdits)
        }

        return nil
    }

    // MARK: - Outgoing Edit Send

    /// Creates a copy of the passed in `targetMessage`, then constructs
    /// an `OutgoingEditMessage` with this new copy.  Note that this only creates an
    /// in-memory copy and doesn't persist the new message.
    public func createOutgoingEditMessage(
        targetMessage: TSOutgoingMessage,
        thread: TSThread,
        edits: MessageEdits,
        oversizeText: AttachmentDataSource?,
        quotedReplyEdit: MessageEdits.Edit<Void>,
        linkPreview: LinkPreviewDataSource?,
        tx: DBWriteTransaction
    ) throws -> OutgoingEditMessage {
        guard let threadRowId = thread.sqliteRowId else {
            throw OWSAssertionError("Can't apply edit in uninserted thread")
        }

        let editTargetWrapper = OutgoingEditMessageWrapper(
            message: targetMessage,
            thread: thread
        )

        let editedMessage = try applyAndInsertEdits(
            editTargetWrapper: editTargetWrapper,
            editsToApply: edits,
            threadRowId: threadRowId,
            newOversizeText: oversizeText.map { .dataSource($0) },
            quotedReplyEdit: quotedReplyEdit,
            newLinkPreview: linkPreview.map { .draft($0) },
            tx: tx
        )

        let outgoingEditMessage = context.dataStore.createOutgoingEditMessage(
            thread: thread,
            targetMessageTimestamp: targetMessage.timestamp,
            editMessage: editedMessage,
            tx: tx
        )

        return outgoingEditMessage
    }

    // MARK: - Edit Utilities

    /// Apply edits to a target message and insert the edited message as the
    /// latest revision, along with records for the now-previous revision.
    ///
    /// - Parameter editTargetWrapper
    /// A wrapper around the target message to which edits will be applied.
    /// - Parameter editsToApply
    /// Describes what edits should be performed on the target message.
    /// - Returns
    /// The target message with edits applied; i.e., the "latest revision" of
    /// the message. The updates to this message will have been persisted.
    private func applyAndInsertEdits<EditTarget: EditMessageWrapper>(
        editTargetWrapper: EditTarget,
        editsToApply: MessageEdits,
        threadRowId: Int64,
        newOversizeText: MessageEdits.OversizeTextSource?,
        quotedReplyEdit: MessageEdits.Edit<Void>,
        newLinkPreview: MessageEdits.LinkPreviewSource?,
        tx: DBWriteTransaction
    ) throws -> EditTarget.MessageType {
        /// Create and insert a clone of the existing message, with edits
        /// applied.
        let latestRevisionMessage: EditTarget.MessageType = createEditedMessage(
            editTargetWrapper: editTargetWrapper,
            edits: editsToApply,
            tx: tx
        )
        context.dataStore.overwritingUpdate(latestRevisionMessage, tx: tx)
        let latestRevisionRowId = latestRevisionMessage.sqliteRowId!

        /// Create and insert a clone of the original message, preserving all
        /// fields, as a record of the now-prior revision of the now-edited
        /// message.
        ///
        /// Keep the original message's timestamp, as well as its content.
        let priorRevisionMessageBuilder = editTargetWrapper.cloneAsBuilderWithoutAttachments(
            applying: .noChanges(),
            isLatestRevision: false
        )
        let priorRevisionMessage = EditTarget.build(
            priorRevisionMessageBuilder,
            dataStore: context.dataStore,
            tx: tx
        )
        context.dataStore.insert(priorRevisionMessage, tx: tx)
        let priorRevisionRowId = priorRevisionMessage.sqliteRowId!

        try context.editManagerAttachments.reconcileAttachments(
            editTarget: editTargetWrapper,
            latestRevision: latestRevisionMessage,
            latestRevisionRowId: latestRevisionRowId,
            priorRevision: priorRevisionMessage,
            priorRevisionRowId: priorRevisionRowId,
            threadRowId: threadRowId,
            newOversizeText: newOversizeText,
            newLinkPreview: newLinkPreview,
            quotedReplyEdit: quotedReplyEdit,
            tx: tx
        )

        // Update the newly inserted message with any data that needs to be
        // copied from the original message
        editTargetWrapper.updateMessageCopy(
            dataStore: context.dataStore,
            newMessageCopy: priorRevisionMessage,
            tx: tx
        )

        let editRecord = EditRecord(
            latestRevisionId: latestRevisionRowId,
            pastRevisionId: priorRevisionRowId,
            read: editTargetWrapper.wasRead
        )
        do {
            try context.editMessageStore.insert(editRecord, tx: tx)
        } catch {
            owsFailDebug("Unexpected edit record insertion error \(error)")
        }

        return latestRevisionMessage
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
        editTargetWrapper editTarget: EditTarget,
        edits: MessageEdits,
        tx: DBReadTransaction
    ) -> EditTarget.MessageType {

        let editedMessageBuilder = editTarget.cloneAsBuilderWithoutAttachments(
            applying: edits,
            isLatestRevision: true
        )

        let editedMessage = EditTarget.build(
            editedMessageBuilder,
            dataStore: context.dataStore,
            tx: tx
        )

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
    ) throws {
        let targetMessage = editTarget.wrapper.message

        // check edit window (by comparing target message server timestamp
        // and incoming edit server timestamp)
        // drop silent and warn if outside of valid range
        switch editTarget {
        case .incomingMessage(let incomingMessage):
            guard let originalServerTimestamp = incomingMessage.message.serverTimestamp?.uint64Value else {
                throw OWSAssertionError("Edit message target doesn't have a server timestamp")
            }

            let (result, isOverflow) = originalServerTimestamp.addingReportingOverflow(Constants.editWindowMilliseconds)
            guard !isOverflow && serverTimestamp <= result else {
                throw OWSAssertionError("Message edit outside of allowed timeframe")
            }
        case .outgoingMessage:
            // Don't validate the edit window for outgoing/sync messages
            break
        }

        let numberOfEdits = context.editMessageStore.numberOfEdits(for: targetMessage, tx: tx)
        if numberOfEdits >= Constants.maxReceiveEdits {
            throw OWSAssertionError("Message edited too many times")
        }

        // If this is a group message, validate edit groupID matches the target
        if let groupThread = thread as? TSGroupThread {
            guard
                let masterKey = editMessage.groupV2?.masterKey,
                let contextInfo = try? GroupV2ContextInfo.deriveFrom(masterKeyData: masterKey),
                contextInfo.groupId == groupThread.groupModel.groupId
            else {
                throw OWSAssertionError("Edit message group does not match target message")
            }
        }

        if !Self.editMessageTypeSupported(message: targetMessage, dataStore: context.dataStore) {
            throw OWSAssertionError("Edit of message type not supported")
        }

        let firstAttachmentRef = context.attachmentStore.fetchFirstReference(
            owner: .messageBodyAttachment(messageRowId: targetMessage.sqliteRowId!),
            tx: tx
        )

        // Voice memos only ever have one attachment; only need to check the first.
        if
            let firstAttachmentRef,
            firstAttachmentRef.renderingFlag == .voiceMessage
        {
            // This will bail if it finds a voice memo
            // Might be able to handle image attachemnts, but fail for now.
            throw OWSAssertionError("Voice message edits not supported")
        }

        // All good!
    }

    private static func editMessageTypeSupported(
        message: TSMessage,
        dataStore: EditManagerImpl.Shims.DataStore
    ) -> Bool {
        // Skip remotely deleted
        if message.wasRemotelyDeleted {
            return false
        }

        // Skip view-once
        if message.isViewOnceMessage {
            return false
        }

        // Skip restored SMS messages
        if message.isSmsMessageRestoredFromBackup {
            return false
        }

        // Skip contact shares
        if dataStore.isMessageContactShare(message) {
            return false
        }

        if message.messageSticker != nil {
            return false
        }

        return true
    }

    // MARK: - Edit Revision Read State

    public func markEditRevisionsAsRead(
        for edit: TSMessage,
        thread: TSThread,
        tx: DBWriteTransaction
    ) throws {
        try context.editMessageStore
            .findEditHistory(for: edit, tx: tx)
            .lazy
            .filter { !$0.record.read }
            .forEach { item in
                guard let message = item.1 as? TSIncomingMessage else { return }
                var record: EditRecord = item.0

                record.read = true
                try self.context.editMessageStore.update(record, tx: tx)

                self.context.receiptManagerShim.messageWasRead(
                    message,
                    thread: thread,
                    circumstance: .onThisDevice,
                    tx: tx
                )
            }
    }
}
