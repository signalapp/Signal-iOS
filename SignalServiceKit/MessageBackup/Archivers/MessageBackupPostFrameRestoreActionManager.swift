//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public class MessageBackupPostFrameRestoreActionManager {
    typealias SharedMap = MessageBackup.SharedMap
    typealias RecipientId = MessageBackup.RecipientId
    typealias RecipientActions = MessageBackup.RecipientRestoringContext.PostFrameRestoreActions
    typealias ChatId = MessageBackup.ChatId
    typealias ChatActions = MessageBackup.ChatRestoringContext.PostFrameRestoreActions

    private let interactionStore: MessageBackupInteractionStore
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let sskPreferences: Shims.SSKPreferences
    private let threadStore: MessageBackupThreadStore

    init(
        interactionStore: MessageBackupInteractionStore,
        recipientDatabaseTable: RecipientDatabaseTable,
        sskPreferences: Shims.SSKPreferences,
        threadStore: MessageBackupThreadStore
    ) {
        self.interactionStore = interactionStore
        self.recipientDatabaseTable = recipientDatabaseTable
        self.sskPreferences = sskPreferences
        self.threadStore = threadStore
    }

    // MARK: -

    func performPostFrameRestoreActions(
        recipientActions: SharedMap<RecipientId, RecipientActions>,
        chatActions: SharedMap<ChatId, ChatActions>,
        chatItemContext: MessageBackup.ChatItemRestoringContext
    ) throws {
        for (recipientId, actions) in recipientActions {
            if actions.insertContactHiddenInfoMessage {
                try insertContactHiddenInfoMessage(recipientId: recipientId, chatItemContext: chatItemContext)
            }
        }
        // Note: This should happen after recipient actions; the recipient actions insert
        // messages which may themselves influence the set of chat actions.
        // (At time of writing, ordering is irrelevant, because hiding info messages aren't "visible".
        // But ordering requirements could change in the future).
        var wasAnyThreadVisible = false
        for (chatId, actions) in chatActions {
            guard let thread = chatItemContext.chatContext[chatId] else {
                continue
            }
            if actions.shouldBeMarkedVisible {
                wasAnyThreadVisible = true
                try threadStore.markVisible(
                    thread: thread,
                    lastInteractionRowId: actions.lastVisibleInteractionRowId,
                    context: chatItemContext.chatContext
                )
            }
        }
        if wasAnyThreadVisible {
            sskPreferences.setHasSavedThread(true, tx: chatItemContext.tx)
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
        try interactionStore.insert(
            infoMessage,
            in: chatThread,
            chatId: chatId,
            context: chatItemContext
        )
    }
}

extension MessageBackupPostFrameRestoreActionManager {
    public enum Shims {
        public typealias SSKPreferences = _MessageBackupPostFrameRestoreActionManager_SSKPreferencesShim
    }
    public enum Wrappers {
        public typealias SSKPreferences = _MessageBackupPostFrameRestoreActionManager_SSKPreferencesWrapper
    }
}

public protocol _MessageBackupPostFrameRestoreActionManager_SSKPreferencesShim {
    func setHasSavedThread(_ newValue: Bool, tx: DBWriteTransaction)
}

public class _MessageBackupPostFrameRestoreActionManager_SSKPreferencesWrapper: MessageBackupPostFrameRestoreActionManager.Shims.SSKPreferences {

    public init() {}

    public func setHasSavedThread(_ newValue: Bool, tx: DBWriteTransaction) {
        SSKPreferences.setHasSavedThread(newValue, transaction: SDSDB.shimOnlyBridge(tx))
    }
}
