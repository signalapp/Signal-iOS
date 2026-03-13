//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public struct AdminDeleteRecord: Codable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName: String = "AdminDelete"

    public let interactionId: Int64
    public let deleteAuthorId: SignalRecipient.RowId
    public var recipientAddressStates: [SignalServiceAddress: TSOutgoingMessageRecipientState]?

    public enum CodingKeys: String, CodingKey {
        case interactionId
        case deleteAuthorId
        case recipientAddressStates
    }

    enum Columns {
        static let interactionId = Column(CodingKeys.interactionId.rawValue)
        static let deleteAuthorId = Column(CodingKeys.deleteAuthorId.rawValue)
        static let recipientAddressStates = Column(CodingKeys.recipientAddressStates.rawValue)
    }

    public static let persistenceConflictPolicy = PersistenceConflictPolicy(
        insert: .ignore,
        update: .replace,
    )

    public init(interactionId: Int64, deleteAuthorId: SignalRecipient.RowId) {
        self.interactionId = interactionId
        self.deleteAuthorId = deleteAuthorId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.interactionId = try container.decode(Int64.self, forKey: .interactionId)
        self.deleteAuthorId = try container.decode(SignalRecipient.RowId.self, forKey: .deleteAuthorId)

        let recipientAddressData = try container.decodeIfPresent([SignalServiceAddress: Data].self, forKey: .recipientAddressStates)

        if let recipientAddressData {
            var decodedRecipientAddressStates: [SignalServiceAddress: TSOutgoingMessageRecipientState] = [:]
            for (address, recipientStateData) in recipientAddressData {
                guard
                    let recipientState = try NSKeyedUnarchiver.unarchivedObject(
                        ofClass: TSOutgoingMessageRecipientState.self,
                        from: recipientStateData,
                    )
                else {
                    owsFailDebug("Failed to decode TSOutgoingMessageRecipientState")
                    continue
                }

                decodedRecipientAddressStates[address] = recipientState
            }
            self.recipientAddressStates = decodedRecipientAddressStates
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(interactionId, forKey: .interactionId)
        try container.encode(deleteAuthorId, forKey: .deleteAuthorId)

        if let recipientAddressStates {
            let encoded = try recipientAddressStates.mapValues { value in
                try NSKeyedArchiver.archivedData(
                    withRootObject: value,
                    requiringSecureCoding: true,
                )
            }
            try container.encode(encoded, forKey: .recipientAddressStates)
        }
    }
}
