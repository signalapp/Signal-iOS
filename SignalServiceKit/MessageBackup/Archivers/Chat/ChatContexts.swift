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

        fileprivate init(chat: BackupProto.Chat) {
            self.init(value: chat.id)
        }

        fileprivate init(chatItem: BackupProto.ChatItem) {
            self.init(value: chatItem.chatId)
        }

        // MARK: MessageBackupLoggableId

        public var typeLogString: String { "BackupProto.Chat" }
        public var idLogString: String { "\(value)" }
    }

    /// Chats only exist for group (v2) and contact threads, not story threads.
    public enum ChatThread {
        /// Note: covers note to self as well.
        case contact(TSContactThread)
        /// Instantiators are expected to validate the group is gv2.
        case groupV2(TSGroupThread)

        public var thread: TSThread {
            switch self {
            case .contact(let thread):
                return thread
            case .groupV2(let thread):
                return thread
            }
        }

        public var uniqueId: MessageBackup.ThreadUniqueId {
            return .init(chatThread: self)
        }
    }

    public struct ThreadUniqueId: Hashable, MessageBackupLoggableId {
        let value: String

        public init(value: String) {
            self.value = value
        }

        fileprivate init(thread: TSThread) {
            self.init(value: thread.uniqueId)
        }

        fileprivate init(interaction: TSInteraction) {
            self.init(value: interaction.uniqueThreadId)
        }

        fileprivate init(chatThread: ChatThread) {
            self.init(thread: chatThread.thread)
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
     * insert them. Later, when we create the ``BackupProto.ChatItem`` corresponding to the ``TSThread``,
     * we will need to add the corresponding ``MessageBackup/ChatId``, which we look up using the thread id
     * this context keeps.
     */
    public class ChatArchivingContext {

        public let recipientContext: RecipientArchivingContext

        private var currentChatId = ChatId(value: 1)
        private let map = SharedMap<ThreadUniqueId, ChatId>()

        internal init(recipientContext: RecipientArchivingContext) {
            self.recipientContext = recipientContext
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

    public class ChatRestoringContext {

        public let recipientContext: RecipientRestoringContext

        private let map = SharedMap<ChatId, ThreadUniqueId>()
        private let pinnedThreadIndexMap = SharedMap<ThreadUniqueId, UInt32>()

        internal init(recipientContext: RecipientRestoringContext) {
            self.recipientContext = recipientContext
        }

        internal subscript(_ chatId: ChatId) -> ThreadUniqueId? {
            map[chatId]
        }

        internal func mapChatId(
            _ chatId: ChatId,
            to thread: ChatThread
        ) {
            map[chatId] = thread.uniqueId
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
}

extension BackupProto.Chat {

    public var chatId: MessageBackup.ChatId {
        return MessageBackup.ChatId(chat: self)
    }
}

extension BackupProto.ChatItem {

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
