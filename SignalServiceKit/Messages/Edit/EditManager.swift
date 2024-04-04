//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

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

    // Process incoming data message
    // 1) Check the external edit for valid field values
    // 2) Call shared code to create new copies/records
    func processIncomingEditMessage(
        _ newDataMessage: SSKProtoDataMessage,
        thread: TSThread,
        editTarget: EditMessageTarget,
        serverTimestamp: UInt64,
        tx: DBWriteTransaction
    ) throws -> TSMessage

    // MARK: - Edit UI Validation

    func canShowEditMenu(interaction: TSInteraction, thread: TSThread) -> Bool

    func validateCanSendEdit(
        targetMessageTimestamp: UInt64,
        thread: TSThread,
        tx: DBReadTransaction
    ) -> EditSendValidationError?

    func shouldShowEditSendConfirmation(tx: DBReadTransaction) -> Bool

    func setShouldShowEditSendConfirmation(_ shouldShow: Bool, tx: DBWriteTransaction)

    // MARK: - Outgoing Edit Send

    /// Creates a copy of the passed in `targetMessage`, then constructs
    /// an `OutgoingEditMessage` with this new copy.  Note that this only creates an
    /// in-memory copy and doesn't persist the new message.
    func createOutgoingEditMessage(
        targetMessage: TSOutgoingMessage,
        thread: TSThread,
        edits: MessageEdits,
        tx: DBReadTransaction
    ) -> OutgoingEditMessage

    /// Fetches a fresh version of the message targeted by `OutgoingEditMessage`,
    /// and creates the necessary copies of the edits in the database.
    func insertOutgoingEditRevisions(
        for outgoingEditMessage: OutgoingEditMessage,
        tx: DBWriteTransaction
    ) throws

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
