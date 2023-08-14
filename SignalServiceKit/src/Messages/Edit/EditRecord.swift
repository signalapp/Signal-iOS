//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// An EditRecord represent a 1:N relationship between a the current version of a message and
/// any prior versions of the message.  Both `latestRevisionId` and `pastRevisionId` refer
/// to the row id of an entry in the Interaction table
///
/// `latestRevisionId` always refers to the latest (visible) row id of the message in the Interaction
/// table.  The id is stable and doesn't change between revisions of a message.
///
/// `pastRevisionId` is the new id created when a copy of the original edited message is inserted
/// into the Interactions table.
public struct EditRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName: String = "EditRecord"

    public var id: Int64?
    public let latestRevisionId: Int64
    public let pastRevisionId: Int64
    public var read: Bool = false

    mutating public func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }

    public init(
        latestRevisionId: Int64,
        pastRevisionId: Int64,
        read: Bool = false
    ) {
        self.latestRevisionId = latestRevisionId
        self.pastRevisionId = pastRevisionId
        self.read = read
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(Int64.self, forKey: .id)
        self.latestRevisionId = try container.decode(Int64.self, forKey: .latestRevisionId)
        self.pastRevisionId = try container.decode(Int64.self, forKey: .pastRevisionId)
        self.read = try container.decodeIfPresent(Bool.self, forKey: .read) ?? false
    }
}
