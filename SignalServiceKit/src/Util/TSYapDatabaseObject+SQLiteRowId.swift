//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public extension TSYapDatabaseObject {
    var sqliteRowId: Int64? {
        return grdbId?.int64Value
    }
}
