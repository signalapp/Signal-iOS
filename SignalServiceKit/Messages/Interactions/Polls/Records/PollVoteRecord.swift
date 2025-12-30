//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public enum VoteState: Int, Codable {
    // Option was previously voted for but has been unvoted for.
    // This is necessary to track to preserve ordering of votes.
    case unvote = 0

    // Option is currently voted for.
    case vote = 1

    // A user has tapped "unvote" but the unvote has not yet sent.
    // Should only appear for the local aci.
    case pendingUnvote = 2

    // A user has tapped "vote" but the vote has not yet sent.
    // Should only appear for the local aci.
    case pendingVote = 3

    public func isUnvote() -> Bool {
        switch self {
        case .unvote, .pendingUnvote:
            return true
        default:
            return false
        }
    }

    public func isPending() -> Bool {
        switch self {
        case .pendingVote, .pendingUnvote:
            return true
        default:
            return false
        }
    }
}

public struct PollVoteRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName: String = "PollVote"

    public var id: Int64?
    public let optionId: Int64
    public let voteAuthorId: Int64
    public let voteCount: Int32
    public var voteState: VoteState

    public mutating func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }

    public init(
        optionId: Int64,
        voteAuthorId: Int64,
        voteCount: Int32,
        voteState: VoteState,
    ) {
        self.optionId = optionId
        self.voteAuthorId = voteAuthorId
        self.voteCount = voteCount
        self.voteState = voteState
    }

    enum CodingKeys: String, CodingKey {
        case id
        case optionId
        case voteAuthorId
        case voteCount
        case voteState
    }

    enum Columns {
        static let id = Column(CodingKeys.id.rawValue)
        static let optionId = Column(CodingKeys.optionId.rawValue)
        static let voteAuthorId = Column(CodingKeys.voteAuthorId.rawValue)
        static let voteCount = Column(CodingKeys.voteCount.rawValue)
        static let voteState = Column(CodingKeys.voteState.rawValue)
    }

    public static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .replace,
    )
}
