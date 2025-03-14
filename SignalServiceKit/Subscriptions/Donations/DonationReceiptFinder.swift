//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class DonationReceiptFinder {
    public static func hasAny(transaction: DBReadTransaction) -> Bool {
        let sql = """
            SELECT EXISTS (
                SELECT 1
                FROM \(DonationReceipt.databaseTableName)
                LIMIT 1
            )
        """
        do {
            return try Bool.fetchOne(transaction.database, sql: sql) ?? false
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to find donation receipt")
        }
    }

    public static func fetchAllInReverseDateOrder(transaction: DBReadTransaction) -> [DonationReceipt] {
        let sql = """
            SELECT *
            FROM \(DonationReceipt.databaseTableName)
            ORDER BY \(DonationReceipt.columnName(.timestamp)) DESC
        """
        do {
            return try DonationReceipt.fetchAll(transaction.database, sql: sql)
        } catch {
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFail("Failed to fetch donation receipts \(error)")
        }
    }
}
