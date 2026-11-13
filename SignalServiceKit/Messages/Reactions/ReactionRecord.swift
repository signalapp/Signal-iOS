//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public struct ReactionRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName: String = "Reaction"

    public typealias RowId = Int64
    public typealias ThreadId = TSThread.RowId
    public typealias InteractionId = Int64
    public typealias RecipientId = SignalRecipient.RowId

    public let id: RowId

    /// The message that was reacted to.
    public private(set) var messageId: InteractionId

    /// The recipient who reacted to the message.
    public private(set) var reactorId: RecipientId

    /// The thread containing the message that was reacted to. Theoretically
    /// unnecessarily, though critical for efficient performance of the "mark as
    /// read" query.
    public private(set) var threadId: ThreadId

    public private(set) var emoji: String

    @DBUInt64
    public private(set) var sentTimestamp: UInt64

    public private(set) var isRead: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case messageId
        case reactorId
        case threadId
        case emoji
        case sentTimestamp
        case isRead
    }

    enum Columns {
        static let id = Column(CodingKeys.id.rawValue)
        static let messageId = Column(CodingKeys.messageId.rawValue)
        static let reactorId = Column(CodingKeys.reactorId.rawValue)
        static let threadId = Column(CodingKeys.threadId.rawValue)
        static let emoji = Column(CodingKeys.emoji.rawValue)
        static let sentTimestamp = Column(CodingKeys.sentTimestamp.rawValue)
        static let isRead = Column(CodingKeys.isRead.rawValue)
    }

    static func insertRecord(
        messageId: InteractionId,
        reactorId: RecipientId,
        threadId: ThreadId,
        emoji: String,
        timestamp: UInt64,
        isRead: Bool?,
        tx: DBWriteTransaction,
    ) -> Self {
        return failIfThrows {
            return try Self.fetchOne(
                tx.database,
                sql: """
                INSERT INTO \(Self.databaseTableName) (
                    \(Columns.messageId.name),
                    \(Columns.reactorId.name),
                    \(Columns.threadId.name),
                    \(Columns.emoji.name),
                    \(Columns.sentTimestamp.name),
                    \(Columns.isRead.name)
                ) VALUES (?, ?, ?, ?, ?, ?) RETURNING *
                """,
                arguments: [
                    messageId,
                    reactorId,
                    threadId,
                    emoji,
                    Int64(bitPattern: timestamp),
                    isRead,
                ],
            ).owsFailUnwrap("must return value or error")
        }
    }

    func delete(tx: DBWriteTransaction) {
        failIfThrows { try self.delete(tx.database) }
    }

    static func isReadableMessage(_ message: TSMessage) -> Bool {
        // Reactions to messages we send need to be manually marked as read as they
        // trigger notifications we need to clear out. Everything else doesn't
        // track "read" status.
        return message is TSOutgoingMessage
    }

    mutating func markRead(tx: DBWriteTransaction) {
        switch self.isRead {
        case nil:
            // Doesn't need to be marked read.
            return
        case true:
            // Already marked read.
            return
        case false:
            self.isRead = true
            failIfThrows { try self.update(tx.database) }
        }
    }

    mutating func setReactorId(_ reactorId: RecipientId, tx: DBWriteTransaction) {
        self.reactorId = reactorId
        failIfThrows { try self.update(tx.database) }
    }
}
