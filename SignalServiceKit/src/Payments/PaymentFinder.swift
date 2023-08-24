//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

@objc
public class PaymentFinder: NSObject {

    public class func paymentModels(paymentStates: [TSPaymentState],
                                    transaction: SDSAnyReadTransaction) -> [TSPaymentModel] {
        switch transaction.readTransaction {
        case .grdbRead(let grdbTransaction):
            return paymentModels(paymentStates: paymentStates, grdbTransaction: grdbTransaction)
        }
    }

    private class func paymentModels(paymentStates: [TSPaymentState],
                                     grdbTransaction transaction: GRDBReadTransaction) -> [TSPaymentModel] {

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

    @objc
    public class func firstUnreadPaymentModel(transaction: SDSAnyReadTransaction) -> TSPaymentModel? {
        let sql = """
        SELECT * FROM \(PaymentModelRecord.databaseTableName)
        WHERE \(paymentModelColumn: .isUnread) = 1
        LIMIT 1
        """
        return TSPaymentModel.grdbFetchOne(sql: sql,
                                           arguments: [],
                                           transaction: transaction.unwrapGrdbRead)
    }

    @objc
    public class func allUnreadPaymentModels(transaction: SDSAnyReadTransaction) -> [TSPaymentModel] {
        let sql = """
        SELECT * FROM \(PaymentModelRecord.databaseTableName)
        WHERE \(paymentModelColumn: .isUnread) = 1
        """
        do {
            return try TSPaymentModel.grdbFetchCursor(sql: sql,
                                                      arguments: [],
                                                      transaction: transaction.unwrapGrdbRead).all()
        } catch {
            owsFail("error: \(error)")
        }
    }

    @objc
    public class func unreadCount(transaction: SDSAnyReadTransaction) -> UInt {
        do {
            guard let count = try UInt.fetchOne(transaction.unwrapGrdbRead.database,
                                                sql: """
                SELECT COUNT(*)
                FROM \(PaymentModelRecord.databaseTableName)
                WHERE \(paymentModelColumn: .isUnread) = 1
                """,
                                                arguments: []) else {
                throw OWSAssertionError("count was unexpectedly nil")
            }
            return count
        } catch {
            owsFail("error: \(error)")
        }
    }

    // MARK: -

    @objc
    public class func paymentModels(forMcLedgerBlockIndex mcLedgerBlockIndex: UInt64,
                                    transaction: SDSAnyReadTransaction) -> [TSPaymentModel] {
        let sql = """
        SELECT * FROM \(PaymentModelRecord.databaseTableName)
        WHERE \(paymentModelColumn: .mcLedgerBlockIndex) = ?
        """
        do {
            return try TSPaymentModel.grdbFetchCursor(sql: sql,
                                                      arguments: [mcLedgerBlockIndex],
                                                      transaction: transaction.unwrapGrdbRead).all()
        } catch {
            owsFail("error: \(error)")
        }
    }

    @objc
    public class func paymentModels(forMcReceiptData mcReceiptData: Data,
                                    transaction: SDSAnyReadTransaction) -> [TSPaymentModel] {
        let sql = """
        SELECT * FROM \(PaymentModelRecord.databaseTableName)
        WHERE \(paymentModelColumn: .mcReceiptData) = ?
        """
        do {
            return try TSPaymentModel.grdbFetchCursor(sql: sql,
                                                      arguments: [mcReceiptData],
                                                      transaction: transaction.unwrapGrdbRead).all()
        } catch {
            owsFail("error: \(error)")
        }
    }

    @objc
    public class func paymentModels(forMcTransactionData mcTransactionData: Data,
                                    transaction: SDSAnyReadTransaction) -> [TSPaymentModel] {
        let sql = """
        SELECT * FROM \(PaymentModelRecord.databaseTableName)
        WHERE \(paymentModelColumn: .mcTransactionData) = ?
        """
        do {
            return try TSPaymentModel.grdbFetchCursor(sql: sql,
                                                      arguments: [mcTransactionData],
                                                      transaction: transaction.unwrapGrdbRead).all()
        } catch {
            owsFail("error: \(error)")
        }
    }
}
