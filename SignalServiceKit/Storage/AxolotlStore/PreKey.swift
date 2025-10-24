//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

// TODO: Rename to PreKeyRecord when decodeDeprecatedPreKeys is turned off.
struct PreKey: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "PreKey"

    let rowId: Int64

    // The combination of these three fields must be UNIQUE -- keyIds must not
    // be reused within a namespace for a particular identity.

    let identity: OWSIdentity
    let namespace: Namespace
    let keyId: UInt32

    /// Is this a one-time or signed/last-resort pre key?
    ///
    /// "One-time" elliptic curve pre keys are stored in a separate namespace
    /// from "signed/last-resort" elliptic curve pre keys, so this value is
    /// redundant for elliptic curve pre keys. Both types of Kyber pre keys are
    /// stored in the same namespace, so this field is load bearing for them.
    let isOneTime: Bool

    /// The Unix timestamp when the key was replaced/became obsolete.
    let replacedAt: Int64?

    /// The key itself.
    let serializedRecord: Data?

    enum Namespace: Int64, Codable {
        case oneTime = 0
        case signed = 2
        case kyber = 1
    }

    enum CodingKeys: String, CodingKey {
        case rowId
        case identity
        case namespace
        case keyId
        case isOneTime
        case replacedAt
        case serializedRecord
    }

    static func baseQuery(in namespace: PreKey.Namespace, identity: OWSIdentity) -> QueryInterfaceRequest<PreKey> {
        return PreKey
            .filter(Column(PreKey.CodingKeys.identity.rawValue) == identity.rawValue)
            .filter(Column(PreKey.CodingKeys.namespace.rawValue) == namespace.rawValue)
    }
}
