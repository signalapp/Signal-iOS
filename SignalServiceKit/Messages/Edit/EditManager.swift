//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum EditSendValidationError: Error {
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
                comment: "Error message to display to user when a message is too old to edit"
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

public protocol EditManager {

    // MARK: - Incoming Edit Processing

    /// Process an incoming data message.
    ///
    /// Checks the external edit for valid field values, then calls shared code
    /// to create new copies and records as appropriate.
    func processIncomingEditMessage(
        _ newDataMessage: SSKProtoDataMessage,
        serverTimestamp: UInt64,
        serverGuid: String?,
        serverDeliveryTimestamp: UInt64,
        thread: TSThread,
        editTarget: EditMessageTarget,
        tx: DBWriteTransaction
    ) throws -> TSMessage

    // MARK: - Edit UI Validation

    func canShowEditMenu(interaction: TSInteraction, thread: TSThread) -> Bool

    func validateCanSendEdit(
        targetMessageTimestamp: UInt64,
        thread: TSThread,
        tx: DBReadTransaction
    ) -> EditSendValidationError?

    // MARK: - Outgoing Edit Send

    /// Fetches a fresh version of the `targetMessage`, creates and inserts
    /// copies into the database with edits applied as needed, and finally
    /// constructs and returns an `OutgoingEditMessage` with the newest copy.
    func createOutgoingEditMessage(
        targetMessage: TSOutgoingMessage,
        thread: TSThread,
        edits: MessageEdits,
        oversizeText: AttachmentDataSource?,
        quotedReplyEdit: MessageEdits.Edit<Void>,
        linkPreview: LinkPreviewDataSource?,
        tx: DBWriteTransaction
    ) throws -> OutgoingEditMessage

    // MARK: - Edit Revision Read State

    func markEditRevisionsAsRead(
        for edit: TSMessage,
        thread: TSThread,
        tx: DBWriteTransaction
    ) throws
}

public extension TSMessage {

    /// Check if the message is an old edit revision.
    ///
    /// Past edits will still technically be part of a conversation,
    /// but they should be hidden from operations that are determining
    /// latest messages for things like sorting conversations.
    func isPastEditRevision() -> Bool {
        return self.editState == .pastRevision
    }
}
