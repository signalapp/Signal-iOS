//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

extension MessageBackup {

}

extension MessageBackup {

    public struct ChatId: ExpressibleByIntegerLiteral, Hashable {

        public typealias IntegerLiteralType = UInt64

        internal let value: UInt64

        public init(integerLiteral value: UInt64) {
            self.value = value
        }

        fileprivate init(_ value: UInt64) {
            self.value = value
        }
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
            return .init(self.thread.uniqueId)
        }
    }

    public struct ThreadUniqueId: ExpressibleByStringLiteral, Hashable {
        public typealias StringLiteralType = String

        internal let value: String

        public init(stringLiteral value: String) {
            self.value = value
        }

        public init(_ value: String) {
            self.value = value
        }
    }

    /**
     * As we go archiving chats, we use this object to track mappings from the addressing we use in the app
     * to the ID addressing system of the backup protos.
     *
     * For example, we will assign a ``BackupChatId`` to each ``TSThread`` as we
     * insert them. Later, when we create the ``BackupProtoChatItem`` corresponding to the ``TSThread``,
     * we will need to add the corresponding ``BackupChatId``, which we look up using the thread id
     * this context keeps.
     */
    public class ChatArchivingContext {

        public let recipientContext: RecipientArchivingContext

        private var currentChatId: ChatId = 1
        private let map = SharedMap<ThreadUniqueId, ChatId>()

        /// The order of pinned threads is represented by an "order" value on the ``BackupProtoChat``.
        /// TODO: assigning this sequentially right now, which isn't correct. Investigate doing this correctly.
        var pinnedThreadOrder: UInt32 = 1

        internal init(recipientContext: RecipientArchivingContext) {
            self.recipientContext = recipientContext
        }

        internal func assignChatId(to threadUniqueId: ThreadUniqueId) -> ChatId {
            defer {
                currentChatId = ChatId(currentChatId.value + 1)
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

        internal init(recipientContext: RecipientRestoringContext) {
            self.recipientContext = recipientContext
        }

        internal subscript(_ chatId: ChatId) -> ThreadUniqueId? {
            get { map[chatId] }
            set(newValue) { map[chatId] = newValue }
        }
    }
}

extension BackupProtoChat {

    public var chatId: MessageBackup.ChatId {
        return .init(id)
    }
}

extension BackupProtoChatItem {

    public var chatId: MessageBackup.ChatId {
        return .init(chatID)
    }
}

extension TSInteraction {

    public var uniqueThreadIdentifier: MessageBackup.ThreadUniqueId {
        return .init(self.uniqueThreadId)
    }
}
