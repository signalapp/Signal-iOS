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

        // EDUCATION

        static let collectionName: String = "EditManager"
        static let shouldShowEditSendWarning: String = "shouldShowEditSendWarning"
    }

    public struct Context {
        let attachmentStore: AttachmentStore
        let dataStore: EditManagerImpl.Shims.DataStore
        let editMessageStore: EditMessageStore
        let groupsShim: EditManagerImpl.Shims.Groups
        let keyValueStoreFactory: KeyValueStoreFactory
        let linkPreviewManager: LinkPreviewManager
        let receiptManagerShim: EditManagerImpl.Shims.ReceiptManager
        let tsResourceManager: TSResourceManager
        let tsResourceStore: TSResourceStore

        public init(
            attachmentStore: AttachmentStore,
            dataStore: EditManagerImpl.Shims.DataStore,
            editMessageStore: EditMessageStore,
            groupsShim: EditManagerImpl.Shims.Groups,
            keyValueStoreFactory: KeyValueStoreFactory,
            linkPreviewManager: LinkPreviewManager,
            receiptManagerShim: EditManagerImpl.Shims.ReceiptManager,
            tsResourceManager: TSResourceManager,
            tsResourceStore: TSResourceStore
        ) {
            self.attachmentStore = attachmentStore
            self.dataStore = dataStore
            self.editMessageStore = editMessageStore
            self.groupsShim = groupsShim
            self.keyValueStoreFactory = keyValueStoreFactory
            self.linkPreviewManager = linkPreviewManager
            self.receiptManagerShim = receiptManagerShim
            self.tsResourceManager = tsResourceManager
            self.tsResourceStore = tsResourceStore
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
    ) throws -> TSMessage {

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
                $0.contentType == OWSMimeTypeOversizeTextMessage
            })
            .map {
                OversizeTextSource.proto($0)
            }

        let quotedReplyEdit: MessageEdits.Edit<Void> = {
            // If the editMessage quote field is present, preserve the exisiting
            // quote. If the field is nil, remove any quote on the current message.
            if newDataMessage.quote == nil {
                return .change(())
            }
            return .keep
        }()

        let linkPreview = newDataMessage.preview.first.map { LinkPreviewSource.proto($0, newDataMessage) }

        let targetMessageWrapper = editTarget.wrapper

        let edits = MessageEdits(
            timestamp: newDataMessage.timestamp,
            body: .change(newDataMessage.body),
            bodyRanges: .change(bodyRanges)
        )

        // Create a copy of the existing message and update with the edit
        let editedMessage = createEditedMessage(
            editTarget: targetMessageWrapper,
            edits: edits,
            tx: tx
        )

        try insertEditCopies(
            editedMessage: editedMessage,
            editTarget: targetMessageWrapper,
            newOversizeText: oversizeText,
            quotedReplyEdit: quotedReplyEdit,
            newLinkPreview: linkPreview,
            tx: tx
        )

        return editedMessage
    }

    // MARK: - Edit UI Validation

    public func canShowEditMenu(interaction: TSInteraction, thread: TSThread) -> Bool {
        return Self.validateCanShowEditMenu(interaction: interaction, thread: thread) == nil
    }

    private static func validateCanShowEditMenu(interaction: TSInteraction, thread: TSThread) -> EditSendValidationError? {
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

        if let error = Self.validateCanShowEditMenu(interaction: targetMessage, thread: thread) {
            return error
        }

        let numberOfEdits = context.editMessageStore.numberOfEdits(for: targetMessage, tx: tx)
        if !thread.isNoteToSelf && numberOfEdits >= Constants.maxSendEdits {
            return .tooManyEdits(Constants.maxSendEdits)
        }

        return nil
    }

    public func shouldShowEditSendConfirmation(tx: DBReadTransaction) -> Bool {
        return keyValueStore.getBool(
            Constants.shouldShowEditSendWarning,
            defaultValue: true,
            transaction: tx
        )
    }

    public func setShouldShowEditSendConfirmation(_ shouldShow: Bool, tx: DBWriteTransaction) {
        keyValueStore.setBool(
            shouldShow,
            key: Constants.shouldShowEditSendWarning,
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
        edits: MessageEdits,
        oversizeText: DataSource?,
        quotedReplyEdit: MessageEdits.Edit<Void>,
        linkPreview: OWSLinkPreviewDraft?,
        tx: DBWriteTransaction
    ) throws -> OutgoingEditMessage {

        let editTarget = OutgoingEditMessageWrapper(
            message: targetMessage,
            thread: thread
        )

        let editedMessage = createEditedMessage(
            editTarget: editTarget,
            edits: edits,
            tx: tx
        )

        let outgoingEditMessage = context.dataStore.createOutgoingEditMessage(
            thread: thread,
            targetMessageTimestamp: targetMessage.timestamp,
            editMessage: editedMessage,
            tx: tx
        )

        guard let editTarget = context.editMessageStore.editTarget(
            timestamp: outgoingEditMessage.targetMessageTimestamp,
            authorAci: nil,
            tx: tx
        ) else {
            throw OWSAssertionError("Failed to find target message")
        }

        try insertEditCopies(
            editedMessage: outgoingEditMessage.editedMessage,
            editTarget: editTarget.wrapper,
            newOversizeText: oversizeText.map { .dataSource($0) },
            quotedReplyEdit: quotedReplyEdit,
            newLinkPreview: linkPreview.map { .draft($0) },
            tx: tx
        )

        return outgoingEditMessage
    }

    // MARK: - Edit Utilities

    // The method used for updating the database with both incoming
    // and outgoing edits.
    private func insertEditCopies<EditTarget: EditMessageWrapper> (
        editedMessage: TSMessage,
        editTarget: EditTarget,
        newOversizeText: OversizeTextSource?,
        quotedReplyEdit: MessageEdits.Edit<Void>,
        newLinkPreview: LinkPreviewSource?,
        tx: DBWriteTransaction
    ) throws {
        // Update the exiting message with edited fields
        context.dataStore.overwritingUpdate(editedMessage, tx: tx)

        let pastRevisionCopyEdits = MessageEdits(
            // Keep the timestamp & contents from the target
            timestamp: editTarget.message.timestamp,
            body: .keep,
            bodyRanges: .keep
        )

        // Create a new copy of the original message
        let newMessageBuilder = editTarget.cloneAsBuilderWithoutAttachments(
            applying: pastRevisionCopyEdits,
            isLatestRevision: false
        )

        let newMessage = EditTarget.build(
            newMessageBuilder,
            dataStore: context.dataStore,
            tx: tx
        )

        // Insert a new copy of the original message to preserve edit history.
        context.dataStore.insert(newMessage, tx: tx)

        try reconcileQuotedReply(
            editTarget: editTarget,
            latestRevision: editedMessage,
            latestRevisionRowId: editedMessage.sqliteRowId!,
            priorRevision: newMessage,
            priorRevisionRowId: newMessage.sqliteRowId!,
            quotedReplyEdit: quotedReplyEdit,
            tx: tx
        )
        try reconcileLinkPreview(
            editTarget: editTarget,
            latestRevision: editedMessage,
            latestRevisionRowId: editedMessage.sqliteRowId!,
            priorRevision: newMessage,
            priorRevisionRowId: newMessage.sqliteRowId!,
            newLinkPreview: newLinkPreview,
            tx: tx
        )
        try reconcileOversizeText(
            editTarget: editTarget,
            latestRevision: editedMessage,
            latestRevisionRowId: editedMessage.sqliteRowId!,
            priorRevision: newMessage,
            priorRevisionRowId: newMessage.sqliteRowId!,
            newOversizeText: newOversizeText,
            tx: tx
        )
        try reconcileBodyMediaAttachments(
            editTarget: editTarget,
            latestRevision: editedMessage,
            latestRevisionRowId: editedMessage.sqliteRowId!,
            priorRevision: newMessage,
            priorRevisionRowId: newMessage.sqliteRowId!,
            tx: tx
        )

        // Update the newly inserted message with any data that needs to be
        // copied from the original message
        editTarget.updateMessageCopy(
            dataStore: context.dataStore,
            tsResourceStore: context.tsResourceStore,
            newMessageCopy: newMessage,
            tx: tx
        )

        if
            let originalId = editedMessage.sqliteRowId,
            let editId = newMessage.sqliteRowId
        {
            let editRecord = EditRecord(
                latestRevisionId: originalId,
                pastRevisionId: editId,
                read: editTarget.wasRead
            )
            context.editMessageStore.insert(editRecord, tx: tx)
        } else {
            throw OWSAssertionError("Missing EditRecord IDs")
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
        editTarget: EditTarget,
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
                let data = context.groupsShim.groupId(for: editMessage),
                data.groupId == groupThread.groupModel.groupId
            else {
                throw OWSAssertionError("Edit message group does not match target message")
            }
        }

        if !Self.editMessageTypeSupported(message: targetMessage) {
            throw OWSAssertionError("Edit of message type not supported")
        }

        let currentAttachmentRefs = context.tsResourceStore.bodyMediaAttachments(
            for: targetMessage,
            tx: tx
        )
        let currentAttachments = context.tsResourceStore
            .fetch(currentAttachmentRefs.map(\.resourceId), tx: tx)
            .map(\.bridge)

        // Voice memos only ever have one attachment; only need to check the first.
        if
            let firstAttachment = currentAttachments.first,
            context.dataStore.isVoiceMessageAttachment(firstAttachment, inContainingMessage: targetMessage, tx: tx)
        {
            // This will bail if it finds a voice memo
            // Might be able to handle image attachemnts, but fail for now.
            throw OWSAssertionError("Voice message edits not supported")
        }

        // All good!
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

    // MARK: - Attachments

    private func reconcileQuotedReply<EditTarget: EditMessageWrapper>(
        editTarget: EditTarget,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        quotedReplyEdit: MessageEdits.Edit<Void>,
        tx: DBWriteTransaction
    ) throws {
        // This copy of the message has no edits applied.
        let quotedReplyPriorToEdit = editTarget.message.quotedMessage

        let attachmentReferencePriorToEdit: AttachmentReference? = FeatureFlags.readV2Attachments
            ? context.attachmentStore.quotedThumbnailAttachment(
                for: editTarget.message,
                tx: tx
            )
            : nil

        if let quotedReplyPriorToEdit {
            // If we had a quoted reply, always keep it on the prior revision.
            context.dataStore.update(priorRevision, with: quotedReplyPriorToEdit, tx: tx)
        }
        if let attachmentReferencePriorToEdit {
            // Always assign the prior revision as an owner of the existing attachment.
            try context.attachmentStore.addOwner(
                duplicating: attachmentReferencePriorToEdit,
                withNewOwner: .quotedReplyAttachment(messageRowId: priorRevisionRowId),
                tx: tx
            )
        }

        switch quotedReplyEdit {
        case .keep:
            if let quotedReplyPriorToEdit {
                // The latest revision keeps the prior revision's quoted reply.
                context.dataStore.update(latestRevision, with: quotedReplyPriorToEdit, tx: tx)
            }
            // No need to touch ownership edges, the latest revision message is already an owner
            // because it maintained the original's row id.
        case .change:
            // Drop the quoted reply on the latest revision.
            if let attachmentReferencePriorToEdit {
                // Break the owner edge from the latest revision.
                context.attachmentStore.removeOwner(
                    .quotedReplyAttachment(messageRowId: latestRevisionRowId),
                    for: attachmentReferencePriorToEdit.attachmentRowId,
                    tx: tx
                )
            }
            // No need to touch the TSMessage.quotedReply as it is already nil by default.
        }
    }

    private enum LinkPreviewSource {
        case draft(OWSLinkPreviewDraft)
        case proto(SSKProtoPreview, SSKProtoDataMessage)
    }

    private func reconcileLinkPreview<EditTarget: EditMessageWrapper>(
        editTarget: EditTarget,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        newLinkPreview: LinkPreviewSource?,
        tx: DBWriteTransaction
    ) throws {
        // This copy of the message has no edits applied.
        let linkPreviewPriorToEdit = editTarget.message.linkPreview

        let attachmentReferencePriorToEdit: AttachmentReference? = FeatureFlags.readV2Attachments
            ? context.attachmentStore.fetchFirstReference(
                owner: .messageLinkPreview(messageRowId: editTarget.message.sqliteRowId!),
                tx: tx
            )
            : nil

        if let linkPreviewPriorToEdit {
            // If we had a link preview, always keep it on the prior revision.
            context.dataStore.update(priorRevision, with: linkPreviewPriorToEdit, tx: tx)
        }
        if let attachmentReferencePriorToEdit {
            // Always assign the prior revision as an owner of the existing attachment.
            try context.attachmentStore.addOwner(
                duplicating: attachmentReferencePriorToEdit,
                withNewOwner: .messageLinkPreview(messageRowId: priorRevisionRowId),
                tx: tx
            )

            // Break the owner edge from the latest revision since we always
            // either drop the link preview or create a new one.
            context.attachmentStore.removeOwner(
                .messageLinkPreview(messageRowId: latestRevisionRowId),
                for: attachmentReferencePriorToEdit.attachmentRowId,
                tx: tx
            )
        }

        // Create and assign the new link preview.
        switch newLinkPreview {
        case .none:
            break
        case .draft(let draft):
            let builder = try context.linkPreviewManager.validateAndBuildLinkPreview(from: draft, tx: tx)
            context.dataStore.update(latestRevision, with: builder.info, tx: tx)
            try builder.finalize(
                owner: .messageLinkPreview(messageRowId: latestRevisionRowId),
                tx: tx
            )
        case .proto(let preview, let dataMessage):
            let builder = try context.linkPreviewManager.validateAndBuildLinkPreview(
                from: preview,
                dataMessage: dataMessage,
                tx: tx
            )
            context.dataStore.update(latestRevision, with: builder.info, tx: tx)
            try builder.finalize(
                owner: .messageLinkPreview(messageRowId: latestRevisionRowId),
                tx: tx
            )
        }
    }

    private enum OversizeTextSource {
        case dataSource(DataSource)
        case proto(SSKProtoAttachmentPointer)
    }

    private func reconcileOversizeText<EditTarget: EditMessageWrapper>(
        editTarget: EditTarget,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        newOversizeText: OversizeTextSource?,
        tx: DBWriteTransaction
    ) throws {
        let oversizeTextReferencePriorToEdit = context.tsResourceStore.oversizeTextAttachment(
            for: editTarget.message,
            tx: tx
        )

        if let oversizeTextReferencePriorToEdit {
            // If we had oversize text, always keep it on the prior revision.
            switch oversizeTextReferencePriorToEdit.concreteType {
            case .legacy(let legacyReference):
                // For legacy references, we update the message's attachment id array.
                if let oversizeTextAttachmentId = legacyReference.attachment?.uniqueId {
                    var priorRevisionAttachmentIds = priorRevision.attachmentIds
                    if !priorRevisionAttachmentIds.contains(oversizeTextAttachmentId) {
                        // oversize text goes first
                        priorRevisionAttachmentIds.insert(oversizeTextAttachmentId, at: 0)
                    }
                    context.dataStore.update(
                        priorRevision,
                        withLegacyBodyAttachmentIds: priorRevisionAttachmentIds,
                        tx: tx
                    )

                    var latestRevisionAttachmentIds = latestRevision.attachmentIds
                    if latestRevisionAttachmentIds.removeFirst(where: { $0 == oversizeTextAttachmentId}) != nil {
                        // Remove it from the latest revision since we always
                        // either drop the oversize text or create a new one.
                        context.dataStore.update(
                            latestRevision,
                            withLegacyBodyAttachmentIds: latestRevisionAttachmentIds,
                            tx: tx
                        )
                    }
                }
            case .v2(let attachmentReference):
                // Always assign the prior revision as an owner of the existing attachment.
                try context.attachmentStore.addOwner(
                    duplicating: attachmentReference,
                    withNewOwner: .messageOversizeText(messageRowId: priorRevisionRowId),
                    tx: tx
                )

                // Break the owner edge from the latest revision since we always
                // either drop the oversize text or create a new one.
                context.attachmentStore.removeOwner(
                    .messageOversizeText(messageRowId: latestRevisionRowId),
                    for: attachmentReference.attachmentRowId,
                    tx: tx
                )
            }
        }

        // Create and assign the new oversize text.
        switch newOversizeText {
        case .none:
            break
        case .dataSource(let dataSource):
            guard let latestRevisionOutgoing = latestRevision as? TSOutgoingMessage else {
                throw OWSAssertionError("Can only set local data source oversize text on outgoing edits")
            }
            try context.tsResourceManager.createOversizeTextAttachmentStream(
                consuming: dataSource,
                message: latestRevisionOutgoing,
                tx: tx
            )
        case .proto(let protoPointer):
            try context.tsResourceManager.createOversizeTextAttachmentPointer(
                from: protoPointer,
                message: latestRevision,
                tx: tx
            )
        }
    }

    private func reconcileBodyMediaAttachments<EditTarget: EditMessageWrapper>(
        editTarget: EditTarget,
        latestRevision: TSMessage,
        latestRevisionRowId: Int64,
        priorRevision: TSMessage,
        priorRevisionRowId: Int64,
        tx: DBWriteTransaction
    ) throws {
        let attachmentReferencesPriorToEdit = context.tsResourceStore.bodyMediaAttachments(
            for: editTarget.message,
            tx: tx
        )

        var priorRevisionLegacyAttachmentIds = priorRevision.attachmentIds
        var latestRevisionLegacyAttachmentIds = latestRevision.attachmentIds
        for attachmentReferencePriorToEdit in attachmentReferencesPriorToEdit {
            // If we had a body attachment, always keep it on the prior revision.
            switch attachmentReferencePriorToEdit.concreteType {
            case .legacy(let legacyReference):
                // Keep every legacy id on both the old and new revision.
                if let attachmentId = legacyReference.attachment?.uniqueId {
                    if !priorRevisionLegacyAttachmentIds.contains(attachmentId) {
                        priorRevisionLegacyAttachmentIds.append(attachmentId)
                    }
                    if !latestRevisionLegacyAttachmentIds.contains(attachmentId) {
                        latestRevisionLegacyAttachmentIds.append(attachmentId)
                    }
                }
            case .v2(let attachmentReference):
                // Always assign the prior revision as a new owner of the existing attachment.
                // The latest revision stays an owner; no change needed as its row id is already the owner.
                try context.attachmentStore.addOwner(
                    duplicating: attachmentReference,
                    withNewOwner: .messageBodyAttachment(messageRowId: priorRevisionRowId),
                    tx: tx
                )
            }
        }
        context.dataStore.update(
            priorRevision,
            withLegacyBodyAttachmentIds: priorRevisionLegacyAttachmentIds,
            tx: tx
        )
        context.dataStore.update(
            latestRevision,
            withLegacyBodyAttachmentIds: latestRevisionLegacyAttachmentIds,
            tx: tx
        )
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
            .filter { item in
                !item.0.read
            }
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
