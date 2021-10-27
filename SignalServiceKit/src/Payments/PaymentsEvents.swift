//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol PaymentsEvents: AnyObject {
    func willInsertPayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction)
    func willUpdatePayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction)

    func clearState(transaction: SDSAnyWriteTransaction)
}

// MARK: -

@objc
public class PaymentsEventsNoop: NSObject, PaymentsEvents {
    public func willInsertPayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction) {}
    public func willUpdatePayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction) {}
    
    public func clearState(transaction: SDSAnyWriteTransaction) {}
}

// MARK: -

@objc
public class PaymentsEventsAppExtension: NSObject, PaymentsEvents {
    public func willInsertPayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction) {}
    public func willUpdatePayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction) {}

    public func clearState(transaction: SDSAnyWriteTransaction) {
        paymentsHelperSwift.clearState(transaction: transaction)
    }
}
