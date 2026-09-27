//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

extension TableRecord {
    /// Performs SELECT DISTINCT column FROM table.
    ///
    /// Runs in O(results.count * ln(n)) time when `table` has an index that
    /// starts with `column`. Callers must ensure a suitable index exists.
    static func selectDistinct<T: DatabaseValueConvertible & StatementColumnConvertible>(
        _ column: GRDB.Column,
        as type: T.Type,
        tx: DBReadTransaction,
    ) throws -> [T] {
        let baseQuery = Self.all().order(column).select(column, as: type)
        var currQuery = baseQuery
        var results = [T]()
        while let result = try currQuery.fetchOne(tx.database) {
            results.append(result)
            currQuery = baseQuery.filter(column > result)
        }
        return results
    }
}
