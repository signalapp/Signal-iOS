//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public class MessageBackupPostFrameRestoreActionManager {
    typealias PostFrameRestoreAction = MessageBackup.RestoringContext.PostFrameRestoreAction

    private let interactionStore: InteractionStore
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let threadStore: ThreadStore

    init(
        interactionStore: InteractionStore,
        recipientDatabaseTable: RecipientDatabaseTable,
        threadStore: ThreadStore
    ) {
        self.interactionStore = interactionStore
        self.recipientDatabaseTable = recipientDatabaseTable
        self.threadStore = threadStore
    }

    // MARK: -

    func performPostFrameRestoreActions(
        _ postFrameRestoreActions: [PostFrameRestoreAction],
        tx: DBWriteTransaction
    ) throws {
        for postFrameRestoreAction in postFrameRestoreActions {
            switch postFrameRestoreAction {
            case .insertContactHiddenInfoMessage(let recipientRowId):
                try insertContactHiddenInfoMessage(recipientRowId: recipientRowId, tx: tx)
            }
        }
    }

    /// Inserts a `TSInfoMessage` that a contact was hidden, for the given
    /// `SignalRecipient` SQLite row ID.
    private func insertContactHiddenInfoMessage(
        recipientRowId: Int64,
        tx: DBWriteTransaction
    ) throws {
        guard let recipient = recipientDatabaseTable.fetchRecipient(rowId: recipientRowId, tx: tx) else {
            throw OWSAssertionError("Missing recipient, but we have a row ID! How did we lose the recipient?")
        }

        guard let contactThread = threadStore.fetchContactThread(recipient: recipient, tx: tx) else {
            /// This is weird, because we shouldn't be able to hide a recipient
            /// without a chat existing. However, who's to say what we'll import
            /// and it's not illegal to create a Backup with a `Contact` frame
            /// that doesn't have a corresponding `Chat` frame.
            Logger.warn("Skipping insert of contact-hidden info message: missing contact thread for recipient!")
            return
        }

        let infoMessage: TSInfoMessage = .makeForContactHidden(contactThread: contactThread)
        interactionStore.insertInteraction(infoMessage, tx: tx)
    }
}
