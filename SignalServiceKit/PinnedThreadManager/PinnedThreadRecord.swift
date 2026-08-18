//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public enum PinnedThreadId: Equatable, Hashable, CustomStringConvertible {
    case groupId(Data)
    case recipientId(SignalRecipient.RowId)
    case releaseNotes

    // MARK: - CustomStringConvertible

    public var description: String {
        switch self {
        case .groupId(let groupId):
            return "groupId(\(groupId.hexadecimalString))"
        case .recipientId(let recipientId):
            return "recipientId(\(recipientId))"
        case .releaseNotes:
            return "releaseNotes"
        }
    }
}

/// Stores which "threads" should be pinned.
///
/// We may have entries for threads that don't yet exist (e.g., a group we
/// learned about via storage service that we're trying to restore).
struct PinnedThreadRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "PinnedThread"

    typealias RowId = Int64

    /// Specifies the order of the pinned threads.
    let id: RowId
    private(set) var constantId: ConstantId?
    private(set) var groupId: Data?
    private(set) var recipientId: SignalRecipient.RowId?

    enum ConstantId: Int64, Codable {
        case releaseNotes = 0
    }

    enum CodingKeys: String, CodingKey {
        case id
        case constantId
        case groupId
        case recipientId
    }

    enum Columns {
        static let id = Column(CodingKeys.id.rawValue)
        static let constantId = Column(CodingKeys.constantId.rawValue)
        static let groupId = Column(CodingKeys.groupId.rawValue)
        static let recipientId = Column(CodingKeys.recipientId.rawValue)
    }

    var threadId: PinnedThreadId {
        get {
            if let constantId {
                owsPrecondition(groupId == nil)
                owsPrecondition(recipientId == nil)
                switch constantId {
                case .releaseNotes:
                    return .releaseNotes
                }
            }
            if let groupId {
                owsPrecondition(recipientId == nil)
                return .groupId(groupId)
            }
            if let recipientId {
                return .recipientId(recipientId)
            }
            owsFail("must specify exactly one value")
        }
        set {
            // Clear all the existing values.
            self.constantId = nil
            self.groupId = nil
            self.recipientId = nil

            // Then set exactly one to the new value.
            switch newValue {
            case .releaseNotes:
                self.constantId = .releaseNotes
            case .groupId(let value):
                self.groupId = value
            case .recipientId(let value):
                self.recipientId = value
            }
        }
    }

    /// Inserts a record at the end of the list.
    static func insertRecord(
        threadId: PinnedThreadId,
        tx: DBWriteTransaction,
    ) -> Self {
        var constantId: ConstantId?
        var groupId: Data?
        var recipientId: SignalRecipient.RowId?
        switch threadId {
        case .releaseNotes:
            constantId = .releaseNotes
        case .groupId(let value):
            groupId = value
        case .recipientId(let value):
            recipientId = value
        }
        return failIfThrows {
            return try Self.fetchOne(
                tx.database,
                sql: """
                INSERT INTO \(Self.databaseTableName) (
                    \(Columns.id.name),
                    \(Columns.constantId.name),
                    \(Columns.groupId.name),
                    \(Columns.recipientId.name)
                ) VALUES (
                    (SELECT MAX(\(Columns.id.name))+1 FROM \(Self.databaseTableName)), ?, ?, ?
                ) RETURNING *
                """,
                arguments: [
                    constantId?.rawValue,
                    groupId,
                    recipientId,
                ],
            ).owsFailUnwrap("must return value or error")
        }
    }
}
