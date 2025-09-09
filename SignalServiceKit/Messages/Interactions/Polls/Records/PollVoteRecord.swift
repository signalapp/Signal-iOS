//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public struct PollVoteRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName: String = "PollVote"

    public var id: Int64?
    public let optionId: Int64
    public let voteAuthorId: Int64
    public let voteCount: Int32

    mutating public func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }

    public init(
        optionId: Int64,
        voteAuthorId: Int64,
        voteCount: Int32
    ) {
        self.optionId = optionId
        self.voteAuthorId = voteAuthorId
        self.voteCount = voteCount
    }

    enum CodingKeys: String, CodingKey {
        case id
        case optionId
        case voteAuthorId
        case voteCount
    }

    enum Columns {
        static let id = Column(CodingKeys.id.rawValue)
        static let optionId = Column(CodingKeys.optionId.rawValue)
        static let voteAuthorId = Column(CodingKeys.voteAuthorId.rawValue)
        static let voteCount = Column(CodingKeys.voteCount.rawValue)
    }
}
