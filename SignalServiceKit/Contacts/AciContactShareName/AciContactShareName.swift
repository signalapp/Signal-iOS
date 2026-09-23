//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB

/// A name for an account that somebody else shared with us in a contact share.
///
/// It is the sharer's claim rather than the account holder's, so it ranks
/// below profile, system contact, and nickname names.
public struct AciContactShareName: Codable, FetchableRecord, PersistableRecord, Equatable {
    public static let databaseTableName: String = "AciContactShareName"

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case recipientRowID
        case givenName
        case familyName
    }

    public let recipientRowID: SignalRecipient.RowId
    public let givenName: String?
    public let familyName: String?

    public init?(recipient: SignalRecipient, givenName: String?, familyName: String?) {
        self.init(recipientRowID: recipient.id, givenName: givenName, familyName: familyName)
    }

    public init?(recipientRowID: SignalRecipient.RowId, givenName: String?, familyName: String?) {
        let givenName = givenName?.strippedOrNil
        let familyName = familyName?.strippedOrNil

        guard givenName?.isEmpty == false || familyName?.isEmpty == false else {
            return nil
        }

        self.recipientRowID = recipientRowID
        self.givenName = givenName
        self.familyName = familyName
    }
}
