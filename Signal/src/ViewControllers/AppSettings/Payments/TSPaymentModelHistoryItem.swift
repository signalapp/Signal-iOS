//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit
import SignalUI

public struct PaymentsHistoryModelItem: PaymentsHistoryItem {
    public let paymentModel: TSPaymentModel

    public let displayName: String

    init(paymentModel: TSPaymentModel, displayName: String) {
        self.paymentModel = paymentModel
        self.displayName = displayName
    }

    public var address: SignalServiceAddress? {
        paymentModel.senderOrRecipientAci.map { SignalServiceAddress($0.wrappedAciValue) }
    }

    public var isIncoming: Bool {
        paymentModel.isIncoming
    }

    public var isOutgoing: Bool {
        paymentModel.isOutgoing
    }

    public var isUnidentified: Bool {
        paymentModel.isUnidentified
    }

    public var isFailed: Bool {
        paymentModel.isFailed
    }

    public var isDefragmentation: Bool {
        paymentModel.isDefragmentation
    }

    public var receiptData: Data? {
        paymentModel.mobileCoin?.receiptData
    }

    public var paymentAmount: TSPaymentAmount? {
        paymentModel.paymentAmount
    }

    public var formattedFeeAmount: String? {
        guard let fee = paymentModel.mobileCoin?.feeAmount else { return nil }
        return PaymentsFormat.format(
            paymentAmount: fee,
            isShortForm: false,
            withCurrencyCode: true,
            withSpace: true)
    }

    public var paymentType: TSPaymentType {
        paymentModel.paymentType
    }

    public var paymentState: TSPaymentState {
        paymentModel.paymentState
    }

    public var createdDate: Date {
        paymentModel.createdDate
    }

    public var ledgerBlockDate: Date? {
        paymentModel.mcLedgerBlockDate
    }

    public var ledgerBlockIndex: UInt64? {
        paymentModel.mcLedgerBlockIndex
    }

    public var isUnread: Bool {
        paymentModel.isUnread
    }

    public var memoMessage: String? {
        paymentModel.memoMessage
    }

    public var attributedPaymentAmount: NSAttributedString? {
        let amount: TSPaymentAmount
        if let paymentAmount = paymentModel.paymentAmount {
            amount = paymentAmount
        } else if let unwrappedAmount = SUIEnvironment.shared.paymentsImplRef.unmaskReceiptAmount(data: receiptData)?.tsPaymentAmount {
            amount = unwrappedAmount
        } else {
            return nil
        }

        return PaymentsFormat.attributedFormat(
            paymentAmount: amount,
            isShortForm: false,
            paymentType: paymentType
        )
    }

    public var formattedPaymentAmount: String? {
        guard
            let paymentAmount = paymentModel.paymentAmount,
            !paymentAmount.isZero
        else {
            return nil
        }
        var totalAmount = paymentAmount
        if let feeAmount = paymentModel.mobileCoin?.feeAmount {
            totalAmount = totalAmount.plus(feeAmount)
        }
        return PaymentsFormat.format(
            paymentAmount: totalAmount,
            isShortForm: true,
            withCurrencyCode: true,
            withSpace: false,
            withPaymentType: paymentModel.paymentType
        )
    }

    public func statusDescription(isLongForm: Bool) -> String? {
        paymentModel.statusDescription(isLongForm: isLongForm)
    }

    public func markAsRead(tx: SDSAnyWriteTransaction) {
        PaymentsViewUtils.markPaymentAsRead(paymentModel, transaction: tx)
    }

    public func reload(tx: SDSAnyReadTransaction) -> Self? {
        guard let newPaymentModel = TSPaymentModel.anyFetch(
            uniqueId: paymentModel.uniqueId,
            transaction: tx
        ) else { return nil }

        return .init(paymentModel: newPaymentModel, displayName: displayName)
    }
}
