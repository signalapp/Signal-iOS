//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public protocol PaymentsEvents: AnyObject {
    func willInsertPayment(_ paymentModel: TSPaymentModel, transaction: DBWriteTransaction)
    func willUpdatePayment(_ paymentModel: TSPaymentModel, transaction: DBWriteTransaction)

    func updateLastKnownLocalPaymentAddressProtoData(transaction: DBWriteTransaction)

    func paymentsStateDidChange()

    func clearState(transaction: DBWriteTransaction)
}

// MARK: -

@objc
public class PaymentsEventsNoop: NSObject, PaymentsEvents {
    public func willInsertPayment(_ paymentModel: TSPaymentModel, transaction: DBWriteTransaction) {}
    public func willUpdatePayment(_ paymentModel: TSPaymentModel, transaction: DBWriteTransaction) {}

    public func updateLastKnownLocalPaymentAddressProtoData(transaction: DBWriteTransaction) {}

    public func paymentsStateDidChange() {}

    public func clearState(transaction: DBWriteTransaction) {}
}

// MARK: -

@objc
public class PaymentsEventsAppExtension: NSObject, PaymentsEvents {
    public func willInsertPayment(_ paymentModel: TSPaymentModel, transaction: DBWriteTransaction) {}
    public func willUpdatePayment(_ paymentModel: TSPaymentModel, transaction: DBWriteTransaction) {}

    public func updateLastKnownLocalPaymentAddressProtoData(transaction: DBWriteTransaction) {}

    public func paymentsStateDidChange() {}

    public func clearState(transaction: DBWriteTransaction) {
        SSKEnvironment.shared.paymentsHelperRef.clearState(transaction: transaction)
    }
}
