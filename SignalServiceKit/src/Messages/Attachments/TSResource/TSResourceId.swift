//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Identifies either a legacy or (eventually) a v2 attachment.
/// Legacy attachments use `uniqueId`, and thus can be referenced before being
/// inserted into the database.
/// V2 attachments always use their sqlite row id, and as such cannot be referenced
/// until they have been inserted into the database.
public enum TSResourceId: Hashable, Equatable {
    case legacy(uniqueId: String)

    // TODO: add `case v2(rowId: Int64)`
}

extension TSResourceId {

    // TODO: remove this before defining v2
    var bridgeUniqueId: String {
        switch self {
        case .legacy(let uniqueId):
            return uniqueId
        }
    }
}
