//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public struct PollRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName: String = "Poll"

    public var id: Int64?
    public let interactionId: Int64
    public var isEnded: Bool = false
    public let allowsMultiSelect: Bool

    public mutating func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }

    public init(
        interactionId: Int64,
        allowsMultiSelect: Bool,
    ) {
        self.interactionId = interactionId
        self.allowsMultiSelect = allowsMultiSelect
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case interactionId
        case isEnded
        case allowsMultiSelect
    }

    enum Columns {
        static let id = Column(CodingKeys.id.rawValue)
        static let interactionId = Column(CodingKeys.interactionId.rawValue)
        static let allowsMultiSelect = Column(CodingKeys.allowsMultiSelect.rawValue)
        static let isEnded = Column(CodingKeys.isEnded.rawValue)
    }
}
