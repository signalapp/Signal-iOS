//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class PaymentFinder {

    public class func paymentModels(
        paymentStates: [TSPaymentState],
        transaction: DBReadTransaction,
    ) -> [TSPaymentModel] {
        return paymentModels(paymentStates: paymentStates, grdbTransaction: transaction)
    }

    private class func paymentModels(
        paymentStates: [TSPaymentState],
        grdbTransaction transaction: DBReadTransaction,
    ) -> [TSPaymentModel] {

        let paymentStatesToLookup = paymentStates.compactMap { $0.rawValue }.map { "\($0)" }.joined(separator: ",")

        let sql = """
        SELECT * FROM \(PaymentModelRecord.databaseTableName)
        WHERE \(paymentModelColumn: .paymentState) IN (\(paymentStatesToLookup))
        """
        let cursor = TSPaymentModel.grdbFetchCursor(sql: sql, arguments: [], transaction: transaction)

        var paymentModels = [TSPaymentModel]()
        do {
            while let paymentModel = try cursor.next() {
                paymentModels.append(paymentModel)
            }
        } catch {
            owsFailDebug("unexpected error \(error)")
        }
        return paymentModels
    }

    public class func firstUnreadPaymentModel(transaction: DBReadTransaction) -> TSPaymentModel? {
        let sql = """
        SELECT * FROM \(PaymentModelRecord.databaseTableName)
        WHERE \(paymentModelColumn: .isUnread) = 1
        LIMIT 1
        """
        return TSPaymentModel.grdbFetchOne(
            sql: sql,
            arguments: [],
            transaction: transaction,
        )
    }

    public class func allUnreadPaymentModels(transaction: DBReadTransaction) -> [TSPaymentModel] {
        let sql = """
        SELECT * FROM \(PaymentModelRecord.databaseTableName)
        WHERE \(paymentModelColumn: .isUnread) = 1
        """
        do {
            return try TSPaymentModel.grdbFetchCursor(
                sql: sql,
                arguments: [],
                transaction: transaction,
            ).all()
        } catch {
            owsFail("error: \(error)")
        }
    }

    public class func unreadCount(transaction: DBReadTransaction) -> UInt {
        do {
            guard
                let count = try UInt.fetchOne(
                    transaction.database,
                    sql: """
                    SELECT COUNT(*)
                    FROM \(PaymentModelRecord.databaseTableName)
                    WHERE \(paymentModelColumn: .isUnread) = 1
                    """,
                    arguments: [],
                )
            else {
                throw OWSAssertionError("count was unexpectedly nil")
            }
            return count
        } catch {
            owsFail("error: \(error)")
        }
    }

    // MARK: -

    public class func paymentModels(
        forMcLedgerBlockIndex mcLedgerBlockIndex: UInt64,
        transaction: DBReadTransaction,
    ) -> [TSPaymentModel] {
        let sql = """
        SELECT * FROM \(PaymentModelRecord.databaseTableName)
        WHERE \(paymentModelColumn: .mcLedgerBlockIndex) = ?
        """
        do {
            return try TSPaymentModel.grdbFetchCursor(
                sql: sql,
                arguments: [mcLedgerBlockIndex],
                transaction: transaction,
            ).all()
        } catch {
            owsFail("error: \(error)")
        }
    }

    public class func paymentModels(
        forMcReceiptData mcReceiptData: Data,
        transaction: DBReadTransaction,
    ) -> [TSPaymentModel] {
        let sql = """
        SELECT * FROM \(PaymentModelRecord.databaseTableName)
        WHERE \(paymentModelColumn: .mcReceiptData) = ?
        """
        do {
            return try TSPaymentModel.grdbFetchCursor(
                sql: sql,
                arguments: [mcReceiptData],
                transaction: transaction,
            ).all()
        } catch {
            owsFail("error: \(error)")
        }
    }

    public class func paymentModels(
        forMcTransactionData mcTransactionData: Data,
        transaction: DBReadTransaction,
    ) -> [TSPaymentModel] {
        let sql = """
        SELECT * FROM \(PaymentModelRecord.databaseTableName)
        WHERE \(paymentModelColumn: .mcTransactionData) = ?
        """
        do {
            return try TSPaymentModel.grdbFetchCursor(
                sql: sql,
                arguments: [mcTransactionData],
                transaction: transaction,
            ).all()
        } catch {
            owsFail("error: \(error)")
        }
    }
}
