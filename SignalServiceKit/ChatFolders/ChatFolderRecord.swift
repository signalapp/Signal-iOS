//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public struct ChatFolderRecord: Equatable, Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName: String = "ChatFolder"

    public enum FolderType: Int, Codable, Sendable {
        /// Default all chats folder
        case all = 1
        case custom = 2

        public init(from decoder: any Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(Int.self)
            if let folderType = FolderType(rawValue: rawValue) {
                self = folderType
            } else {
                Logger.warn("Interpreting unrecognized folderType \(rawValue) as custom.")
                self = .custom
            }
        }
    }

    public static let deletedPosition: UInt32 = .max

    public let id: Int64

    /// Stable ID shared across devices
    public let chatFolderId: UUID
    public let folderType: FolderType
    /// Will be empty for the all chats folder
    public var name: String
    public internal(set) var position: UInt32
    public var showOnlyUnread: Bool
    public var showMutedChats: Bool
    public var includeAllIndividualChats: Bool
    public var includeAllGroupChats: Bool
    public internal(set) var deletedAtTimestampMs: Int64

    public var isDeleted: Bool { deletedAtTimestampMs != 0 }

    static func insertRecord(
        chatFolderId: UUID,
        folderType: FolderType,
        name: String,
        position: UInt32,
        showOnlyUnread: Bool,
        showMutedChats: Bool,
        includeAllIndividualChats: Bool,
        includeAllGroupChats: Bool,
        deletedAtTimestampMs: Int64,
        tx: DBWriteTransaction,
    ) throws -> Self {
        return try Self.fetchOne(
            tx.database,
            sql: """
            INSERT INTO \(Self.databaseTableName) (
                \(Columns.chatFolderId.name),
                \(Columns.folderType.name),
                \(Columns.name.name),
                \(Columns.position.name),
                \(Columns.showOnlyUnread.name),
                \(Columns.showMutedChats.name),
                \(Columns.includeAllIndividualChats.name),
                \(Columns.includeAllGroupChats.name),
                \(Columns.deletedAtTimestampMs.name)
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) RETURNING *
            """,
            arguments: [
                chatFolderId,
                folderType.rawValue,
                name,
                position,
                showOnlyUnread,
                showMutedChats,
                includeAllIndividualChats,
                includeAllGroupChats,
                deletedAtTimestampMs,
            ],
        ).owsFailUnwrap("must return value or error")
    }

    mutating func markDeleted(atTimestampMs timestampMs: Int64) {
        self.deletedAtTimestampMs = timestampMs
        self.position = Self.deletedPosition
    }

    // MARK: - Codable

    public enum CodingKeys: String, CodingKey {
        case id
        case chatFolderId
        case folderType
        case name
        case position
        case showOnlyUnread
        case showMutedChats
        case includeAllIndividualChats
        case includeAllGroupChats
        case deletedAtTimestampMs
    }

    public enum Columns {
        public static let id = Column(CodingKeys.id.rawValue)
        public static let chatFolderId = Column(CodingKeys.chatFolderId.rawValue)
        public static let folderType = Column(CodingKeys.folderType.rawValue)
        public static let name = Column(CodingKeys.name.rawValue)
        public static let position = Column(CodingKeys.position.rawValue)
        public static let showOnlyUnread = Column(CodingKeys.showOnlyUnread.rawValue)
        public static let showMutedChats = Column(CodingKeys.showMutedChats.rawValue)
        public static let includeAllIndividualChats = Column(CodingKeys.includeAllIndividualChats.rawValue)
        public static let includeAllGroupChats = Column(CodingKeys.includeAllGroupChats.rawValue)
        public static let deletedAtTimestampMs = Column(CodingKeys.deletedAtTimestampMs.rawValue)
    }
}
