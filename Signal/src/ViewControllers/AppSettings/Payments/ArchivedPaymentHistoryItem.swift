//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit
import SignalUI

public struct ArchivedPaymentHistoryItem: PaymentsHistoryItem {

    private let archivedPayment: ArchivedPayment
    public let displayName: String

    private let paymentInfo: TSArchivedPaymentInfo
    public let isIncoming: Bool

    public let address: SignalServiceKit.SignalServiceAddress?

    init?(
        archivedPayment: ArchivedPayment,
        address: SignalServiceAddress?,
        displayName: String,
        interaction: TSInteraction
    ) {
        self.archivedPayment = archivedPayment
        self.displayName = displayName
        self.address = address

        switch interaction {
        case let interaction as OWSIncomingArchivedPaymentMessage:
            self.isIncoming = true
            self.paymentInfo = interaction.archivedPaymentInfo
        case let interaction as OWSOutgoingArchivedPaymentMessage:
            self.isIncoming = false
            self.paymentInfo = interaction.archivedPaymentInfo
        default:
            return nil
        }
    }

    public var isOutgoing: Bool {
       !isIncoming
    }

    public var isUnidentified: Bool {
        archivedPayment.interactionUniqueId == nil
    }

    public var isFailed: Bool {
        return archivedPayment.status.isFailure
    }

    public var isDefragmentation: Bool {
        return false
    }

    public var receiptData: Data? {
        archivedPayment.receipt
    }

    public var paymentAmount: TSPaymentAmount? {
        return SUIEnvironment.shared.paymentsImplRef.unmaskReceiptAmount(
            data: archivedPayment.receipt
        )?.tsPaymentAmount
    }

    public var formattedFeeAmount: String? {
        guard let fee = paymentInfo.fee else { return nil }
        return PaymentsFormat.format(
            amountString: fee,
            withCurrencyCode: true,
            withSpace: true
        )
    }

    public var paymentType: TSPaymentType {
        isIncoming ? .incomingPayment : .outgoingPayment
    }

    public var paymentState: TSPaymentState {
        return .incomingComplete
    }

    public var ledgerBlockDate: Date? {
        guard
            let timestamp = archivedPayment.blockTimestamp,
            timestamp > 0
        else { return nil }
        return Date(millisecondsSince1970: timestamp)
    }

    public var ledgerBlockIndex: UInt64? {
        archivedPayment.blockIndex
    }

    public var isUnread: Bool {
        return false
    }

    public var memoMessage: String? {
        paymentInfo.note
    }

    public var attributedPaymentAmount: NSAttributedString? {
        guard let amount = paymentInfo.amount else { return nil }
        let formattedAmount = PaymentsFormat.format(
            amountString: amount,
            withCurrencyCode: false,
            withSpace: false,
            isIncoming: isIncoming
        )
        return PaymentsFormat.attributedFormat(mobileCoinString: formattedAmount, withSpace: false)
    }

    public var formattedPaymentAmount: String? {
        guard let amount = paymentInfo.amount else { return nil }
        return PaymentsFormat.format(
            amountString: amount,
            withCurrencyCode: true,
            withSpace: true
        )
    }

    public func statusDescription(isLongForm: Bool) -> String? {
        return archivedPayment.statusDescription(isOutgoing: isOutgoing)
    }

    /// Read status is only tracked on TSPaymentModels, so there's not really anything to do here.
    public func markAsRead(tx: SignalServiceKit.SDSAnyWriteTransaction) { }

    /// Reload is used on payment details to track updates to the TSPaymentModel.
    /// Since ArchivedPayments aren't updated, reloading here isn't necessary.
    public func reload(tx: SignalServiceKit.SDSAnyReadTransaction) -> Self? {
        return self
    }
}
