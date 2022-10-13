//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class DonationReceiptFinder {
    public static func hasAny(transaction: SDSAnyReadTransaction) -> Bool {
        let sql = """
            SELECT EXISTS (
                SELECT 1
                FROM \(DonationReceipt.databaseTableName)
                LIMIT 1
            )
        """
        return try! Bool.fetchOne(transaction.unwrapGrdbRead.database, sql: sql) ?? false
    }

    public static func fetchAllInReverseDateOrder(transaction: SDSAnyReadTransaction) -> [DonationReceipt] {
        let sql = """
            SELECT *
            FROM \(DonationReceipt.databaseTableName)
            ORDER BY \(DonationReceipt.columnName(.timestamp)) DESC
        """
        do {
            return try DonationReceipt.fetchAll(transaction.unwrapGrdbRead.database, sql: sql)
        } catch {
            owsFailDebug("Failed to fetch donation receipts \(error)")
            return []
        }
    }
}
