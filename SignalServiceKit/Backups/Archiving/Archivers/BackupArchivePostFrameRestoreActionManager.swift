//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public class BackupArchivePostFrameRestoreActionManager {
    typealias SharedMap = BackupArchive.SharedMap
    typealias RecipientId = BackupArchive.RecipientId
    typealias RecipientActions = BackupArchive.RecipientRestoringContext.PostFrameRestoreActions
    typealias ChatId = BackupArchive.ChatId
    typealias ChatActions = BackupArchive.ChatRestoringContext.PostFrameRestoreActions

    private let avatarFetcher: BackupArchiveAvatarFetcher
    private let dateProvider: DateProvider
    private let interactionStore: BackupArchiveInteractionStore
    private let lastVisibleInteractionStore: LastVisibleInteractionStore
    private let preferences: BackupArchive.Shims.Preferences
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let sskPreferences: BackupArchive.Shims.SSKPreferences
    private let threadStore: BackupArchiveThreadStore

    init(
        avatarFetcher: BackupArchiveAvatarFetcher,
        dateProvider: @escaping DateProvider,
        interactionStore: BackupArchiveInteractionStore,
        lastVisibleInteractionStore: LastVisibleInteractionStore,
        preferences: BackupArchive.Shims.Preferences,
        recipientDatabaseTable: RecipientDatabaseTable,
        sskPreferences: BackupArchive.Shims.SSKPreferences,
        threadStore: BackupArchiveThreadStore,
    ) {
        self.avatarFetcher = avatarFetcher
        self.dateProvider = dateProvider
        self.interactionStore = interactionStore
        self.lastVisibleInteractionStore = lastVisibleInteractionStore
        self.preferences = preferences
        self.recipientDatabaseTable = recipientDatabaseTable
        self.sskPreferences = sskPreferences
        self.threadStore = threadStore
    }

    // MARK: -

    func performPostFrameRestoreActions(
        recipientActions: SharedMap<RecipientId, RecipientActions>,
        chatActions: SharedMap<ChatId, ChatActions>,
        bencher: BackupArchive.RestoreBencher,
        chatItemContext: BackupArchive.ChatItemRestoringContext,
    ) throws {
        for (recipientId, actions) in recipientActions {
            if actions.insertContactHiddenInfoMessage {
                try bencher.benchPostFrameRestoreAction(.InsertContactHiddenInfoMessage) {
                    try insertContactHiddenInfoMessage(recipientId: recipientId, chatItemContext: chatItemContext)
                }
            }
            if actions.hasIncomingMessagesMissingAci {
                bencher.benchPostFrameRestoreAction(.InsertPhoneNumberMissingAci) {
                    insertPhoneNumberMissingAci(recipientId: recipientId, chatItemContext: chatItemContext)
                }
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
            try bencher.benchPostFrameRestoreAction(.UpdateThreadMetadata) {
                if actions.shouldBeMarkedVisible {
                    wasAnyThreadVisible = true
                    try threadStore.markVisible(
                        thread: thread,
                        lastInteractionRowId: actions.lastVisibleInteractionRowId,
                        context: chatItemContext.chatContext,
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
                            onScreenPercentage: 1,
                        ),
                        for: thread.tsThread,
                        tx: chatItemContext.tx,
                    )
                }
                switch thread.threadType {
                case .contact:
                    break
                case .groupV2(let groupThread):
                    try updateLastInteractionTimestamps(
                        for: groupThread,
                        actions: actions,
                        context: chatItemContext.chatContext,
                    )
                }
            }
        }
        if wasAnyThreadVisible {
            sskPreferences.setHasSavedThread(true, tx: chatItemContext.tx)
        }

        let avatarFetchTimestamp = dateProvider().ows_millisecondsSince1970
        for recipientId in chatItemContext.recipientContext.allRecipientIds() {
            guard let recipientAddress = chatItemContext.recipientContext[recipientId] else {
                continue
            }

            func getLastVisibleInteractionRowId() -> Int64? {
                guard
                    let chatId = chatItemContext.chatContext[recipientId],
                    let action = chatActions[chatId]
                else {
                    return nil
                }
                return action.lastVisibleInteractionRowId
            }

            try bencher.benchPostFrameRestoreAction(.EnqueueAvatarFetch) {
                switch recipientAddress {
                case .releaseNotesChannel, .distributionList, .callLink:
                    return
                case .localAddress:
                    try avatarFetcher.enqueueFetchOfUserProfile(
                        serviceId: chatItemContext.recipientContext.localIdentifiers.aci,
                        currentTimestamp: avatarFetchTimestamp,
                        lastVisibleInteractionRowIdInContactThread: getLastVisibleInteractionRowId(),
                        localIdentifiers: chatItemContext.recipientContext.localIdentifiers,
                        tx: chatItemContext.tx,
                    )
                case .contact(let contactAddress):
                    guard let serviceId: ServiceId = contactAddress.aci ?? contactAddress.pni else {
                        return
                    }
                    try avatarFetcher.enqueueFetchOfUserProfile(
                        serviceId: serviceId,
                        currentTimestamp: avatarFetchTimestamp,
                        lastVisibleInteractionRowIdInContactThread: getLastVisibleInteractionRowId(),
                        localIdentifiers: chatItemContext.recipientContext.localIdentifiers,
                        tx: chatItemContext.tx,
                    )
                case .group(let groupId):
                    guard let groupThread = chatItemContext.recipientContext[groupId] else {
                        return
                    }
                    try avatarFetcher.enqueueFetchOfGroupAvatar(
                        groupThread,
                        currentTimestamp: avatarFetchTimestamp,
                        lastVisibleInteractionRowIdInGroupThread: getLastVisibleInteractionRowId(),
                        localIdentifiers: chatItemContext.recipientContext.localIdentifiers,
                        tx: chatItemContext.tx,
                    )
                }
            }
        }
    }

    /// Inserts a `TSInfoMessage` that a contact was hidden, for the given
    /// `SignalRecipient` SQLite row ID.
    private func insertContactHiddenInfoMessage(
        recipientId: BackupArchive.RecipientId,
        chatItemContext: BackupArchive.ChatItemRestoringContext,
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
            return
        }

        let infoMessage: TSInfoMessage = .makeForContactHidden(contactThread: contactThread)
        try interactionStore.insert(
            infoMessage,
            in: chatThread,
            chatId: chatId,
            context: chatItemContext,
        )
    }

    private func insertPhoneNumberMissingAci(recipientId: BackupArchive.RecipientId, chatItemContext: BackupArchive.ChatItemRestoringContext) {
        guard
            let address = chatItemContext.recipientContext[recipientId],
            case .contact(let contactAddress) = address,
            let phoneNumber = contactAddress.e164
        else {
            return
        }
        AuthorMergeHelper().foundMissingAci(for: phoneNumber.stringValue, tx: chatItemContext.tx)
    }

    private func updateLastInteractionTimestamps(
        for groupThread: TSGroupThread,
        actions: ChatActions,
        context: BackupArchive.ChatRestoringContext,
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
                tx: context.tx,
            )

            try groupMember?.updateWith(
                lastInteractionTimestamp: latestTimestamp,
                tx: context.tx,
            )
        }
    }
}
