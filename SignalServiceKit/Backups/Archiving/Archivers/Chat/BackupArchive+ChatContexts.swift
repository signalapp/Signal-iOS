//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension BackupArchive {

    struct ChatId: Hashable {
        let value: UInt64

        init(value: UInt64) {
            self.value = value
        }

        fileprivate init(chat: BackupProto_Chat) {
            self.init(value: chat.id)
        }

        fileprivate init(chatItem: BackupProto_ChatItem) {
            self.init(value: chatItem.chatID)
        }
    }

    /// Chats only exist for group (v2) and contact threads, not story threads.
    struct ChatThread {
        enum ThreadType {
            /// Also covers Note to Self.
            case contact(TSContactThread)
            /// Instantiators are expected to validate the group is GV2.
            case groupV2(TSGroupThread)
        }

        let threadType: ThreadType
        let threadRowId: TSThread.RowId

        var tsThread: TSThread {
            switch threadType {
            case .contact(let thread):
                return thread
            case .groupV2(let thread):
                return thread
            }
        }
    }

    struct ThreadUniqueId: Hashable {
        let value: String

        init(value: String) {
            self.value = value
        }

        init(thread: TSThread) {
            self.init(value: thread.uniqueId)
        }

        init(chatThread: ChatThread) {
            self.init(thread: chatThread.tsThread)
        }

        fileprivate init(interaction: TSInteraction) {
            self.init(value: interaction.uniqueThreadId)
        }
    }

    /**
     * As we go archiving chats, we use this object to track mappings from the addressing we use in the app
     * to the ID addressing system of the backup protos.
     *
     * For example, we will assign a ``BackupArchive/ChatId`` to each ``TSThread`` as we
     * insert them. Later, when we create the ``BackupProto_ChatItem`` corresponding to the ``TSThread``,
     * we will need to add the corresponding ``BackupArchive/ChatId``, which we look up using the thread id
     * this context keeps.
     */
    class ChatArchivingContext: ArchivingContext {

        let customChatColorContext: CustomChatColorArchivingContext
        let recipientContext: RecipientArchivingContext

        private var currentChatId = ChatId(value: 1)
        private var map = [ThreadUniqueId: ChatId]()
        var gv1ThreadIds = Set<ThreadUniqueId>()
        /// IDs of our pinned threads. A single pinned recipient may map to
        /// multiple contact threads; this set disambiguates which of those
        /// threads is canonical and actually "pinned".
        var pinnedThreadRowIds = Set<TSThread.RowId>()

        enum CachedThreadInfo {
            case groupThread
            // Contact threads may be _missing_ their address, which
            // will likely cause partial failures downstream.
            case contactThread(contactAddress: BackupArchive.ContactAddress?)
            case noteToSelfThread
        }

        private var threadCache = [ChatId: CachedThreadInfo]()

        init(
            customChatColorContext: CustomChatColorArchivingContext,
            recipientContext: RecipientArchivingContext,
            localIdentifiers: LocalIdentifiers,
            startDate: Date,
            remoteConfig: RemoteConfig,
            currentUploadEra: String,
            bencher: BackupArchive.ArchiveBencher,
            includedContentFilter: IncludedContentFilter,
            perFrameAccumulator: PerFrameAccumulator,
            tx: DBReadTransaction,
        ) {
            self.customChatColorContext = customChatColorContext
            self.recipientContext = recipientContext
            super.init(
                localIdentifiers: localIdentifiers,
                startDate: startDate,
                remoteConfig: remoteConfig,
                currentUploadEra: currentUploadEra,
                bencher: bencher,
                includedContentFilter: includedContentFilter,
                perFrameAccumulator: perFrameAccumulator,
                tx: tx,
            )
        }

        func assignChatId(to thread: TSThread) -> ChatId {
            defer {
                currentChatId = ChatId(value: currentChatId.value + 1)
            }
            map[ThreadUniqueId(thread: thread)] = currentChatId
            if let contactThread = thread as? TSContactThread {
                let contactAddress = contactThread.contactAddress
                if
                    recipientContext.localIdentifiers.containsAnyOf(
                        aci: contactAddress.serviceId as? Aci,
                        phoneNumber: contactAddress.phoneNumber,
                        pni: contactAddress.serviceId as? Pni,
                    )
                {
                    threadCache[currentChatId] = .noteToSelfThread
                } else {
                    threadCache[currentChatId] = .contactThread(
                        contactAddress: contactAddress.asSingleServiceIdBackupAddress(),
                    )
                }
            } else if thread is TSGroupThread {
                threadCache[currentChatId] = .groupThread
            }
            return currentChatId
        }

        subscript(_ threadUniqueId: ThreadUniqueId) -> ChatId? {
            map[threadUniqueId]
        }

        subscript(_ chatId: ChatId) -> CachedThreadInfo? {
            threadCache[chatId]
        }
    }

    class ChatRestoringContext: RestoringContext {

        let customChatColorContext: CustomChatColorRestoringContext
        let recipientContext: RecipientRestoringContext

        private var recipientToChatMap = [RecipientId: ChatId]()

        private var contactThreadMap = [ChatId: (threadRowId: TSThread.RowId, thread: TSContactThread)]()
        private var groupIdMap = [ChatId: (threadRowId: TSThread.RowId, groupId: GroupId)]()

        init(
            customChatColorContext: CustomChatColorRestoringContext,
            recipientContext: RecipientRestoringContext,
            localIdentifiers: LocalIdentifiers,
            startDate: Date,
            remoteConfig: RemoteConfig,
            attachmentByteCounter: BackupArchiveAttachmentByteCounter,
            isPrimaryDevice: Bool,
            tx: DBWriteTransaction,
        ) {
            self.customChatColorContext = customChatColorContext
            self.recipientContext = recipientContext
            super.init(
                localIdentifiers: localIdentifiers,
                startDate: startDate,
                remoteConfig: remoteConfig,
                attachmentByteCounter: attachmentByteCounter,
                isPrimaryDevice: isPrimaryDevice,
                tx: tx,
            )
        }

        subscript(_ recipientId: RecipientId) -> ChatId? {
            recipientToChatMap[recipientId]
        }

        subscript(_ chatId: ChatId) -> ChatThread? {
            if let (rowId, contactThread) = contactThreadMap[chatId] {
                return ChatThread(threadType: .contact(contactThread), threadRowId: rowId)
            }
            if
                let (rowId, groupId) = groupIdMap[chatId],
                let groupThread = recipientContext[groupId]
            {
                return ChatThread(threadType: .groupV2(groupThread), threadRowId: rowId)
            }
            return nil
        }

        func mapChatId(
            _ chatId: ChatId,
            to thread: ChatThread,
            recipientId: RecipientId,
        ) {
            switch thread.threadType {
            case .contact(let contactThread):
                contactThreadMap[chatId] = (thread.threadRowId, contactThread)
            case .groupV2(let groupThread):
                groupIdMap[chatId] = (thread.threadRowId, BackupArchive.GroupId(groupId: groupThread.groupId))
            }
            recipientToChatMap[recipientId] = chatId
        }

        /// Given a newly encountered pinned thread, return all pinned thread ids encountered so far, in order.
        func setPinnedOrder(
            _ pinnedOrder: UInt32,
            forChatId chatId: ChatId,
        ) {
            postFrameRestoreActions[chatId, default: PostFrameRestoreActions()].pinnedOrder = pinnedOrder
        }

        // MARK: Post-Frame Restore

        struct PostFrameRestoreActions {
            var pinnedOrder: UInt32?
            var lastVisibleInteractionRowId: Int64?
            var hadAnyUnreadMessages: Bool = false

            /// Maintained for group chats only.
            /// Maps a group member's aci (including the local user's aci) to the
            /// largest timestamp for messages sent by that member.
            var groupMemberLastInteractionTimestamp = [Aci: UInt64]()

            var shouldBeMarkedVisible: Bool {
                pinnedOrder != nil || lastVisibleInteractionRowId != nil
            }
        }

        /// Represents actions that should be taken after all `Frame`s have been restored.
        private(set) var postFrameRestoreActions = [ChatId: PostFrameRestoreActions]()

        func updateLastVisibleInteractionRowId(
            interactionRowId: Int64,
            wasRead: Bool,
            chatId: ChatId,
        ) {
            var actions = postFrameRestoreActions[chatId] ?? PostFrameRestoreActions()
            if
                actions.lastVisibleInteractionRowId == nil
                // We don't _really_ need to compare as row ids are always
                // increasing, but doesn't hurt to check.
                || actions.lastVisibleInteractionRowId! < interactionRowId
            {
                actions.lastVisibleInteractionRowId = interactionRowId
            }
            actions.hadAnyUnreadMessages = actions.hadAnyUnreadMessages || !wasRead
            postFrameRestoreActions[chatId] = actions
        }

        func updateGroupMemberLastInteractionTimestamp(
            groupThread: TSGroupThread,
            chatId: ChatId,
            senderAci: Aci,
            timestamp: UInt64,
        ) {
            var actions = postFrameRestoreActions[chatId] ?? PostFrameRestoreActions()
            let oldTimestamp = actions.groupMemberLastInteractionTimestamp[senderAci]
            if
                oldTimestamp == nil
                || oldTimestamp! < timestamp
            {
                actions.groupMemberLastInteractionTimestamp[senderAci] = timestamp
                postFrameRestoreActions[chatId] = actions
            }
        }
    }

    // MARK: Custom Chat Colors

    struct CustomChatColorId: Hashable {
        let value: UInt64

        init(value: UInt64) {
            self.value = value
        }

        fileprivate init(customChatColor: BackupProto_ChatStyle.CustomChatColor) {
            self.init(value: customChatColor.id)
        }
    }

    /**
     * As we go archiving custom chat styles, we use this object to track mappings from the addressing we use in the app
     * to the ID addressing system of the backup protos.
     *
     * For example, we will assign a ``BackupArchive/CustomChatColorId`` to each ``CustomChatColor`` as we
     * insert them. Later, when we create the ``BackupProto_ChatStyle/CustomChatColor`` corresponding to the
     * ``CustomChatColor``, we will need to add the corresponding ``BackupArchive/CustomChatColorId``,
     * which we look up using the custom chat color id this context keeps.
     */
    class CustomChatColorArchivingContext: ArchivingContext {

        private var currentCustomChatColorId = CustomChatColorId(value: 1)
        private var map = [CustomChatColor.Key: CustomChatColorId]()

        func assignCustomChatColorId(to customChatColorKey: CustomChatColor.Key) -> CustomChatColorId {
            defer {
                currentCustomChatColorId = CustomChatColorId(value: currentCustomChatColorId.value + 1)
            }
            map[customChatColorKey] = currentCustomChatColorId
            return currentCustomChatColorId
        }

        subscript(_ customChatColorKey: CustomChatColor.Key) -> CustomChatColorId? {
            map[customChatColorKey]
        }
    }

    class CustomChatColorRestoringContext: RestoringContext {

        private var map = [CustomChatColorId: CustomChatColor.Key]()

        let accountDataContext: AccountDataRestoringContext

        init(
            accountDataContext: AccountDataRestoringContext,
            localIdentifiers: LocalIdentifiers,
            startDate: Date,
            remoteConfig: RemoteConfig,
            attachmentByteCounter: BackupArchiveAttachmentByteCounter,
            isPrimaryDevice: Bool,
            tx: DBWriteTransaction,
        ) {
            self.accountDataContext = accountDataContext
            super.init(
                localIdentifiers: localIdentifiers,
                startDate: startDate,
                remoteConfig: remoteConfig,
                attachmentByteCounter: attachmentByteCounter,
                isPrimaryDevice: isPrimaryDevice,
                tx: tx,
            )
        }

        subscript(_ chatColorId: CustomChatColorId) -> CustomChatColor.Key? {
            map[chatColorId]
        }

        func mapCustomChatColorId(
            _ customChatColorId: CustomChatColorId,
            to key: CustomChatColor.Key,
        ) {
            map[customChatColorId] = key
        }
    }
}

extension BackupProto_Chat {

    var chatId: BackupArchive.ChatId {
        return BackupArchive.ChatId(chat: self)
    }
}

extension BackupProto_ChatItem {

    var typedChatId: BackupArchive.ChatId {
        return BackupArchive.ChatId(chatItem: self)
    }
}

extension TSThread {

    var uniqueThreadIdentifier: BackupArchive.ThreadUniqueId {
        return BackupArchive.ThreadUniqueId(thread: self)
    }
}

extension TSInteraction {

    var uniqueThreadIdentifier: BackupArchive.ThreadUniqueId {
        return BackupArchive.ThreadUniqueId(interaction: self)
    }
}
