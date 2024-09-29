//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB
public import LibSignalClient

/// A point-in-time result of performing a lookup for a given username.
///
/// At the time this record was created, the contained username was
/// associated with the contained ACI. Note that this may have since changed,
/// and that therefore we should not assume the association is still valid.
public struct UsernameLookupRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName: String = "UsernameLookupRecord"

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case aci
        case username
    }

    // MARK: - Init

    public let aci: UUID
    public let username: String

    public init(aci: Aci, username: String) {
        self.aci = aci.rawUUID
        self.username = username
    }
}
