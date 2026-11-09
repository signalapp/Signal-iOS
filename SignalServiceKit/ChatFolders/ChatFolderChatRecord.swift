//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

struct ChatFolderChatRecord: Equatable, Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "ChatFolderChat"

    static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .replace,
        update: .abort,
    )

    enum Chat: Equatable, Hashable {
        case contact(recipientRowId: SignalRecipient.RowId)
        case group(groupRowId: GroupRecord.RowId)
    }

    var chatFolderRowId: Int64
    var chat: Chat
    var membershipType: ChatFolder.MembershipType

    init(
        chatFolderRowId: Int64,
        chat: Chat,
        membershipType: ChatFolder.MembershipType,
    ) {
        self.chatFolderRowId = chatFolderRowId
        self.chat = chat
        self.membershipType = membershipType
    }

    enum CodingKeys: String, CodingKey {
        case chatFolderRowId
        case recipientRowId
        case groupRowId
        case membershipType
    }

    enum Columns {
        static let chatFolderRowId = Column(CodingKeys.chatFolderRowId.rawValue)
        static let recipientRowId = Column(CodingKeys.recipientRowId.rawValue)
        static let groupRowId = Column(CodingKeys.groupRowId.rawValue)
        static let membershipType = Column(CodingKeys.membershipType.rawValue)

        static func matching(_ chat: Chat) -> SQLExpression {
            switch chat {
            case .contact(let recipientRowId):
                return Columns.recipientRowId == recipientRowId
            case .group(let groupRowId):
                return Columns.groupRowId == groupRowId
            }
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.chatFolderRowId, forKey: .chatFolderRowId)

        var recipientRowId: SignalRecipient.RowId?
        var groupRowId: GroupRecord.RowId?
        switch self.chat {
        case .contact(let value):
            recipientRowId = value
        case .group(let value):
            groupRowId = value
        }
        try container.encodeIfPresent(recipientRowId, forKey: .recipientRowId)
        try container.encodeIfPresent(groupRowId, forKey: .groupRowId)

        try container.encode(self.membershipType.rawValue, forKey: .membershipType)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.chatFolderRowId = try container.decode(Int64.self, forKey: .chatFolderRowId)

        let recipientRowId = try container.decodeIfPresent(SignalRecipient.RowId.self, forKey: .recipientRowId)
        let groupRowId = try container.decodeIfPresent(GroupRecord.RowId.self, forKey: .groupRowId)
        switch (recipientRowId, groupRowId) {
        case (let recipientRowId?, nil):
            self.chat = .contact(recipientRowId: recipientRowId)
        case (nil, let groupRowId?):
            self.chat = .group(groupRowId: groupRowId)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .recipientRowId,
                in: container,
                debugDescription: "expected exactly one of recipientRowId and groupRowId",
            )
        }

        let membershipTypeRawValue = try container.decode(Int.self, forKey: .membershipType)
        guard let membershipType = ChatFolder.MembershipType(rawValue: membershipTypeRawValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: .membershipType,
                in: container,
                debugDescription: "unrecognized membershipType \(membershipTypeRawValue)",
            )
        }
        self.membershipType = membershipType
    }
}
