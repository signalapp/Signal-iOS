//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

public struct NicknameRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    public static let databaseTableName: String = "NicknameRecord"

    enum CodingKeys: String, CodingKey, ColumnExpression {
        case recipientRowID
        case givenName
        case familyName
        case note
    }

    public let recipientRowID: SignalRecipient.RowId
    public let givenName: String?
    public let familyName: String?
    public let note: String?

    public init(recipient: SignalRecipient, givenName: String?, familyName: String?, note: String?) {
        self.init(recipientRowID: recipient.id, givenName: givenName, familyName: familyName, note: note)
    }

    public init(recipientRowID: SignalRecipient.RowId, givenName: String?, familyName: String?, note: String?) {
        self.recipientRowID = recipientRowID
        self.givenName = givenName
        self.familyName = familyName
        self.note = note
    }
}
