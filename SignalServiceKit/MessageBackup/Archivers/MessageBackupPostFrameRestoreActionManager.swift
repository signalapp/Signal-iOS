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
    private let lastVisibleInteractionStore: LastVisibleInteractionStore
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let sskPreferences: Shims.SSKPreferences
    private let threadStore: MessageBackupThreadStore

    init(
        interactionStore: MessageBackupInteractionStore,
        lastVisibleInteractionStore: LastVisibleInteractionStore,
        recipientDatabaseTable: RecipientDatabaseTable,
        sskPreferences: Shims.SSKPreferences,
        threadStore: MessageBackupThreadStore
    ) {
        self.interactionStore = interactionStore
        self.lastVisibleInteractionStore = lastVisibleInteractionStore
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
            if
                let lastVisibleInteractionRowId = actions.lastVisibleInteractionRowId,
                let lastVisibleInteractionRowId = UInt64(exactly: lastVisibleInteractionRowId),
                !actions.hadAnyUnreadMessages
            {
                // If we had no unread messages but we have some message,
                // set that as the last visible message so that thats what
                // we scroll to.
                lastVisibleInteractionStore.setLastVisibleInteraction(
                    TSThread.LastVisibleInteraction(
                        sortId: lastVisibleInteractionRowId,
                        onScreenPercentage: 1
                    ),
                    for: thread.tsThread,
                    tx: chatItemContext.tx
                )
            }
            switch thread.threadType {
            case .contact:
                break
            case .groupV2(let groupThread):
                try updateLastInteractionTimestamps(
                    for: groupThread,
                    actions: actions,
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
            // This info message is directionless
            directionalDetails: .directionless(BackupProto_ChatItem.DirectionlessMessageDetails()),
            context: chatItemContext
        )
    }

    private func updateLastInteractionTimestamps(
        for groupThread: TSGroupThread,
        actions: ChatActions,
        context: MessageBackup.ChatRestoringContext
    ) throws {
        for memberAddress in groupThread.groupMembership.fullMembers {
            guard let memberAci = memberAddress.aci else {
                // We only restore v2 groups which always have acis for
                // full group members.
                throw OWSAssertionError("Non aci group member in backup!")
            }
            guard let latestTimestamp = actions.groupMemberLastInteractionTimestamp[memberAci] else {
                continue
            }
            let groupMember = try TSGroupMember.groupMember(
                for: memberAci,
                in: groupThread,
                tx: context.tx
            )

            try groupMember?.updateWith(
                lastInteractionTimestamp: latestTimestamp,
                tx: context.tx
            )
        }
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
