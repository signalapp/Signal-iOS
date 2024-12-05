//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension MessageBackup {

    public struct ChatId: Hashable, MessageBackupLoggableId {
        let value: UInt64

        public init(value: UInt64) {
            self.value = value
        }

        fileprivate init(chat: BackupProto_Chat) {
            self.init(value: chat.id)
        }

        fileprivate init(chatItem: BackupProto_ChatItem) {
            self.init(value: chatItem.chatID)
        }

        // MARK: MessageBackupLoggableId

        public var typeLogString: String { "BackupProto_Chat" }
        public var idLogString: String { "\(value)" }
    }

    /// Chats only exist for group (v2) and contact threads, not story threads.
    public struct ChatThread {
        public enum ThreadType {
            /// Also covers Note to Self.
            case contact(TSContactThread)
            /// Instantiators are expected to validate the group is GV2.
            case groupV2(TSGroupThread)
        }

        public let threadType: ThreadType
        public let threadRowId: Int64

        public var tsThread: TSThread {
            switch threadType {
            case .contact(let thread):
                return thread
            case .groupV2(let thread):
                return thread
            }
        }
    }

    public struct ThreadUniqueId: Hashable, MessageBackupLoggableId {
        let value: String

        public init(value: String) {
            self.value = value
        }

        public init(thread: TSThread) {
            self.init(value: thread.uniqueId)
        }

        public init(chatThread: ChatThread) {
            self.init(thread: chatThread.tsThread)
        }

        fileprivate init(interaction: TSInteraction) {
            self.init(value: interaction.uniqueThreadId)
        }

        // MARK: MessageBackupLoggableId

        public var typeLogString: String { "TSThread" }
        public var idLogString: String { value }
    }

    /**
     * As we go archiving chats, we use this object to track mappings from the addressing we use in the app
     * to the ID addressing system of the backup protos.
     *
     * For example, we will assign a ``MessageBackup/ChatId`` to each ``TSThread`` as we
     * insert them. Later, when we create the ``BackupProto_ChatItem`` corresponding to the ``TSThread``,
     * we will need to add the corresponding ``MessageBackup/ChatId``, which we look up using the thread id
     * this context keeps.
     */
    public class ChatArchivingContext: ArchivingContext {

        public let customChatColorContext: CustomChatColorArchivingContext
        public let recipientContext: RecipientArchivingContext

        private var currentChatId = ChatId(value: 1)
        private let map = SharedMap<ThreadUniqueId, ChatId>()
        public var gv1ThreadIds = Set<ThreadUniqueId>()

        public enum CachedThreadInfo {
            case groupThread
            // Contact threads may be _missing_ their address, which
            // will likely cause partial failures downstream.
            case contactThread(contactAddress: MessageBackup.ContactAddress?)
        }

        private let threadCache = SharedMap<ChatId, CachedThreadInfo>()

        internal init(
            backupPurpose: MessageBackupPurpose,
            currentBackupAttachmentUploadEra: String?,
            backupAttachmentUploadManager: BackupAttachmentUploadManager,
            customChatColorContext: CustomChatColorArchivingContext,
            recipientContext: RecipientArchivingContext,
            tx: DBWriteTransaction
        ) {
            self.customChatColorContext = customChatColorContext
            self.recipientContext = recipientContext
            super.init(
                backupPurpose: backupPurpose,
                currentBackupAttachmentUploadEra: currentBackupAttachmentUploadEra,
                backupAttachmentUploadManager: backupAttachmentUploadManager,
                tx: tx
            )
        }

        internal func assignChatId(to thread: TSThread) -> ChatId {
            defer {
                currentChatId = ChatId(value: currentChatId.value + 1)
            }
            map[ThreadUniqueId(thread: thread)] = currentChatId
            if let contactThread = thread as? TSContactThread {
                threadCache[currentChatId] = .contactThread(
                    contactAddress: contactThread.contactAddress.asSingleServiceIdBackupAddress()
                )
            } else if thread is TSGroupThread {
                threadCache[currentChatId] = .groupThread
            }
            return currentChatId
        }

        internal subscript(_ threadUniqueId: ThreadUniqueId) -> ChatId? {
            // swiftlint:disable:next implicit_getter
            get { map[threadUniqueId] }
        }

        internal subscript(_ chatId: ChatId) -> CachedThreadInfo? {
            // swiftlint:disable:next implicit_getter
            get { threadCache[chatId] }
        }
    }

    public class ChatRestoringContext: RestoringContext {

        public let customChatColorContext: CustomChatColorRestoringContext
        public let recipientContext: RecipientRestoringContext

        private let recipientToChatMap = SharedMap<RecipientId, ChatId>()

        private let contactThreadMap = SharedMap<ChatId, (Int64, TSContactThread)>()
        private let groupIdMap = SharedMap<ChatId, (Int64, GroupId)>()
        private let pinnedThreadIndexMap = SharedMap<ThreadUniqueId, UInt32>()

        internal init(
            customChatColorContext: CustomChatColorRestoringContext,
            recipientContext: RecipientRestoringContext,
            tx: DBWriteTransaction
        ) {
            self.customChatColorContext = customChatColorContext
            self.recipientContext = recipientContext
            super.init(tx: tx)
        }

        internal subscript(_ recipientId: RecipientId) -> ChatId? {
            // swiftlint:disable:next implicit_getter
            get { recipientToChatMap[recipientId] }
        }

        internal subscript(_ chatId: ChatId) -> ChatThread? {
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

        internal func mapChatId(
            _ chatId: ChatId,
            to thread: ChatThread,
            recipientId: RecipientId
        ) {
            switch thread.threadType {
            case .contact(let tSContactThread):
                contactThreadMap[chatId] = (thread.threadRowId, tSContactThread)
            case .groupV2(let tSGroupThread):
                groupIdMap[chatId] = (thread.threadRowId, MessageBackup.GroupId(groupModel: tSGroupThread.groupModel))
            }
            recipientToChatMap[recipientId] = chatId
        }

        /// Given a newly encountered pinned thread, return all pinned thread ids encountered so far, in order.
        internal func pinnedThreadOrder(
            newPinnedThreadId: ThreadUniqueId,
            newPinnedThreadChatId: ChatId,
            newPinnedThreadIndex: UInt32
        ) -> [ThreadUniqueId] {
            pinnedThreadIndexMap[newPinnedThreadId] = newPinnedThreadIndex
            setChatIsPinned(chatId: newPinnedThreadChatId)
            return pinnedThreadIndexMap
                .keys
                .lazy
                .compactMap { (key: ThreadUniqueId) -> (ThreadUniqueId, UInt32)? in
                    guard let value = self.pinnedThreadIndexMap[key] else {
                        return nil
                    }
                    return (key, value)
                }
                .sorted(by: { (lhs, rhs) in
                    let lhsSortIndex: UInt32 = lhs.1
                    let rhsSortIndex: UInt32 = rhs.1
                    return lhsSortIndex < rhsSortIndex
                })
                .map(\.0)
        }

        // MARK: Post-Frame Restore

        public struct PostFrameRestoreActions {
            var isPinned: Bool
            var lastVisibleInteractionRowId: Int64?
            var hadAnyUnreadMessages: Bool = false

            /// Maintained for group chats only.
            /// Maps a group member's aci (including the local user's aci) to the
            /// largest timestamp for messages sent by that member.
            var groupMemberLastInteractionTimestamp = SharedMap<Aci, UInt64>()

            var shouldBeMarkedVisible: Bool {
                isPinned || lastVisibleInteractionRowId != nil
            }

            static var `default`: Self {
                return .init(isPinned: false, lastVisibleInteractionRowId: nil)
            }
        }

        /// Represents actions that should be taken after all `Frame`s have been restored.
        private(set) var postFrameRestoreActions = SharedMap<ChatId, PostFrameRestoreActions>()

        func setChatIsPinned(chatId: ChatId) {
            var actions = postFrameRestoreActions[chatId] ?? .default
            actions.isPinned = true
            postFrameRestoreActions[chatId] = actions
        }

        func updateLastVisibleInteractionRowId(
            interactionRowId: Int64,
            wasRead: Bool,
            chatId: ChatId
        ) {
            var actions = postFrameRestoreActions[chatId] ?? .default
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
            timestamp: UInt64
        ) {
            let actions = postFrameRestoreActions[chatId] ?? .default
            let oldTimestamp = actions.groupMemberLastInteractionTimestamp[senderAci]
            if
                oldTimestamp == nil
                || oldTimestamp! < timestamp
            {
                actions.groupMemberLastInteractionTimestamp[senderAci] = timestamp
            }
        }
    }

    // MARK: Custom Chat Colors

    public struct CustomChatColorId: Hashable, MessageBackupLoggableId {
        let value: UInt64

        public init(value: UInt64) {
            self.value = value
        }

        fileprivate init(customChatColor: BackupProto_ChatStyle.CustomChatColor) {
            self.init(value: customChatColor.id)
        }

        // MARK: MessageBackupLoggableId

        public var typeLogString: String { "BackupProto_ChatStyle.CustomChatColor" }
        public var idLogString: String { "\(value)" }
    }

    /**
     * As we go archiving custom chat styles, we use this object to track mappings from the addressing we use in the app
     * to the ID addressing system of the backup protos.
     *
     * For example, we will assign a ``MessageBackup/CustomChatColorId`` to each ``CustomChatColor`` as we
     * insert them. Later, when we create the ``BackupProto_ChatStyle/CustomChatColor`` corresponding to the
     * ``CustomChatColor``, we will need to add the corresponding ``MessageBackup/CustomChatColorId``,
     * which we look up using the custom chat color id this context keeps.
     */
    public class CustomChatColorArchivingContext: ArchivingContext {

        private var currentCustomChatColorId = CustomChatColorId(value: 1)
        private let map = SharedMap<CustomChatColor.Key, CustomChatColorId>()

        internal override init(
            backupPurpose: MessageBackupPurpose,
            currentBackupAttachmentUploadEra: String?,
            backupAttachmentUploadManager: BackupAttachmentUploadManager,
            tx: DBWriteTransaction
        ) {
            super.init(
                backupPurpose: backupPurpose,
                currentBackupAttachmentUploadEra: currentBackupAttachmentUploadEra,
                backupAttachmentUploadManager: backupAttachmentUploadManager,
                tx: tx
            )
        }

        internal func assignCustomChatColorId(to customChatColorKey: CustomChatColor.Key) -> CustomChatColorId {
            defer {
                currentCustomChatColorId = CustomChatColorId(value: currentCustomChatColorId.value + 1)
            }
            map[customChatColorKey] = currentCustomChatColorId
            return currentCustomChatColorId
        }

        internal subscript(_ customChatColorKey: CustomChatColor.Key) -> CustomChatColorId? {
            // swiftlint:disable:next implicit_getter
            get { map[customChatColorKey] }
        }
    }

    public class CustomChatColorRestoringContext: RestoringContext {

        private let map = SharedMap<CustomChatColorId, CustomChatColor.Key>()

        /// Will only be nil if there was no earier AccountData frame to set it, which
        /// should be treated as an error at read time when processing all subsequent frames.
        var uploadEra: RestoredAttachmentUploadEra?

        internal override init(tx: DBWriteTransaction) {
            super.init(tx: tx)
        }

        internal subscript(_ chatColorId: CustomChatColorId) -> CustomChatColor.Key? {
            map[chatColorId]
        }

        internal func mapCustomChatColorId(
            _ customChatColorId: CustomChatColorId,
            to key: CustomChatColor.Key
        ) {
            map[customChatColorId] = key
        }
    }
}

extension BackupProto_Chat {

    public var chatId: MessageBackup.ChatId {
        return MessageBackup.ChatId(chat: self)
    }
}

extension BackupProto_ChatItem {

    public var typedChatId: MessageBackup.ChatId {
        return MessageBackup.ChatId(chatItem: self)
    }
}

extension TSThread {

    public var uniqueThreadIdentifier: MessageBackup.ThreadUniqueId {
        return MessageBackup.ThreadUniqueId(thread: self)
    }
}

extension TSInteraction {

    public var uniqueThreadIdentifier: MessageBackup.ThreadUniqueId {
        return MessageBackup.ThreadUniqueId(interaction: self)
    }
}

extension CustomChatColor.Key: MessageBackupLoggableId {

    public var typeLogString: String { "CustomChatColor.Key" }

    public var idLogString: String { rawValue }
}
