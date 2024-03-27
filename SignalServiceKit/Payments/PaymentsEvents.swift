//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public protocol PaymentsEvents: AnyObject {
    func willInsertPayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction)
    func willUpdatePayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction)

    func updateLastKnownLocalPaymentAddressProtoData(transaction: SDSAnyWriteTransaction)

    func paymentsStateDidChange()

    func clearState(transaction: SDSAnyWriteTransaction)
}

// MARK: -

@objc
public class PaymentsEventsNoop: NSObject, PaymentsEvents {
    public func willInsertPayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction) {}
    public func willUpdatePayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction) {}

    public func updateLastKnownLocalPaymentAddressProtoData(transaction: SDSAnyWriteTransaction) {}

    public func paymentsStateDidChange() {}

    public func clearState(transaction: SDSAnyWriteTransaction) {}
}

// MARK: -

@objc
public class PaymentsEventsAppExtension: NSObject, PaymentsEvents {
    public func willInsertPayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction) {}
    public func willUpdatePayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction) {}

    public func updateLastKnownLocalPaymentAddressProtoData(transaction: SDSAnyWriteTransaction) {}

    public func paymentsStateDidChange() {}

    public func clearState(transaction: SDSAnyWriteTransaction) {
        paymentsHelperSwift.clearState(transaction: transaction)
    }
}
