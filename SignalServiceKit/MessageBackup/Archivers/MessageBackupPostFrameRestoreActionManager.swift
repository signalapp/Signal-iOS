//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public class MessageBackupPostFrameRestoreActionManager {
    typealias PostFrameRestoreAction = MessageBackup.RestoringContext.PostFrameRestoreAction

    private let interactionStore: MessageBackupInteractionStore
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let threadStore: MessageBackupThreadStore

    init(
        interactionStore: MessageBackupInteractionStore,
        recipientDatabaseTable: RecipientDatabaseTable,
        threadStore: MessageBackupThreadStore
    ) {
        self.interactionStore = interactionStore
        self.recipientDatabaseTable = recipientDatabaseTable
        self.threadStore = threadStore
    }

    // MARK: -

    func performPostFrameRestoreActions(
        _ postFrameRestoreActions: [PostFrameRestoreAction],
        chatItemContext: MessageBackup.ChatItemRestoringContext
    ) throws {
        for postFrameRestoreAction in postFrameRestoreActions {
            switch postFrameRestoreAction {
            case .insertContactHiddenInfoMessage(let recipientId):
                try insertContactHiddenInfoMessage(recipientId: recipientId, chatItemContext: chatItemContext)
            }
        }
    }

    /// Inserts a `TSInfoMessage` that a contact was hidden, for the given
    /// `SignalRecipient` SQLite row ID.
    private func insertContactHiddenInfoMessage(
        recipientId: MessageBackup.RecipientId,
        chatItemContext: MessageBackup.ChatItemRestoringContext
    ) throws {
        guard
            let chatId = chatItemContext.chatContext[recipientId],
            let chatThread = chatItemContext.chatContext[chatId],
            case let .contact(contactThread) = chatThread.threadType
        else {
            /// This is weird, because we shouldn't be able to hide a recipient
            /// without a chat existing. However, who's to say what we'll import
            /// and it's not illegal to create a Backup with a `Contact` frame
            /// that doesn't have a corresponding `Chat` frame.
            Logger.warn("Skipping insert of contact-hidden info message: missing contact thread for recipient!")
            return
        }

        let infoMessage: TSInfoMessage = .makeForContactHidden(contactThread: contactThread)
        try interactionStore.insert(infoMessage, in: chatThread, context: chatItemContext)
    }
}
