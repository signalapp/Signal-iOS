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

        internal init(
            currentBackupAttachmentUploadEra: String?,
            backupAttachmentUploadManager: BackupAttachmentUploadManager,
            customChatColorContext: CustomChatColorArchivingContext,
            recipientContext: RecipientArchivingContext,
            tx: DBWriteTransaction
        ) {
            self.customChatColorContext = customChatColorContext
            self.recipientContext = recipientContext
            super.init(
                currentBackupAttachmentUploadEra: currentBackupAttachmentUploadEra,
                backupAttachmentUploadManager: backupAttachmentUploadManager,
                tx: tx
            )
        }

        internal func assignChatId(to threadUniqueId: ThreadUniqueId) -> ChatId {
            defer {
                currentChatId = ChatId(value: currentChatId.value + 1)
            }
            map[threadUniqueId] = currentChatId
            return currentChatId
        }

        internal subscript(_ threadUniqueId: ThreadUniqueId) -> ChatId? {
            // swiftlint:disable:next implicit_getter
            get { map[threadUniqueId] }
        }
    }

    public class ChatRestoringContext: RestoringContext {

        public let customChatColorContext: CustomChatColorRestoringContext
        public let recipientContext: RecipientRestoringContext

        private let map = SharedMap<ChatId, ThreadUniqueId>()
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

        internal subscript(_ chatId: ChatId) -> ThreadUniqueId? {
            map[chatId]
        }

        internal func mapChatId(
            _ chatId: ChatId,
            to thread: ChatThread
        ) {
            map[chatId] = ThreadUniqueId(chatThread: thread)
        }

        /// Given a newly encountered pinned thread, return all pinned thread ids encountered so far, in order.
        internal func pinnedThreadOrder(
            newPinnedThreadId: ThreadUniqueId,
            newPinnedThreadIndex: UInt32
        ) -> [ThreadUniqueId] {
            pinnedThreadIndexMap[newPinnedThreadId] = newPinnedThreadIndex
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
            currentBackupAttachmentUploadEra: String?,
            backupAttachmentUploadManager: BackupAttachmentUploadManager,
            tx: DBWriteTransaction
        ) {
            super.init(
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
