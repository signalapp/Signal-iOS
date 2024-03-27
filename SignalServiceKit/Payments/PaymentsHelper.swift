//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public protocol PaymentsHelper: AnyObject {

    func warmCaches()

    var keyValueStore: SDSKeyValueStore { get }

    var isKillSwitchActive: Bool { get }
    var hasValidPhoneNumberForPayments: Bool { get }
    var canEnablePayments: Bool { get }

    var isPaymentsVersionOutdated: Bool { get }
    func setPaymentsVersionOutdated(_ value: Bool)

    func setArePaymentsEnabled(for serviceId: ServiceIdObjC, hasPaymentsEnabled: Bool, transaction: SDSAnyWriteTransaction)
    func arePaymentsEnabled(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool

    var arePaymentsEnabled: Bool { get }
    func arePaymentsEnabled(tx: SDSAnyReadTransaction) -> Bool
    var paymentsEntropy: Data? { get }
    func enablePayments(transaction: SDSAnyWriteTransaction)
    func enablePayments(withPaymentsEntropy: Data, transaction: SDSAnyWriteTransaction) -> Bool
    func disablePayments(transaction: SDSAnyWriteTransaction)

    func setLastKnownLocalPaymentAddressProtoData(_ data: Data?, transaction: SDSAnyWriteTransaction)
    func lastKnownLocalPaymentAddressProtoData(transaction: SDSAnyWriteTransaction) -> Data?

    func processIncomingPaymentSyncMessage(_ paymentProto: SSKProtoSyncMessageOutgoingPayment,
                                           messageTimestamp: UInt64,
                                           transaction: SDSAnyWriteTransaction)

    func processIncomingPaymentNotification(thread: TSThread,
                                            paymentNotification: TSPaymentNotification,
                                            senderAci: AciObjC,
                                            transaction: SDSAnyWriteTransaction)

    func processIncomingPaymentsActivationRequest(
        thread: TSThread,
        senderAci: AciObjC,
        transaction: SDSAnyWriteTransaction
    )

    func processIncomingPaymentsActivatedMessage(
        thread: TSThread,
        senderAci: AciObjC,
        transaction: SDSAnyWriteTransaction
    )

    func processReceivedTranscriptPaymentNotification(thread: TSThread,
                                                      paymentNotification: TSPaymentNotification,
                                                      messageTimestamp: UInt64,
                                                      transaction: SDSAnyWriteTransaction)

    func tryToInsertPaymentModel(_ paymentModel: TSPaymentModel,
                                 transaction: SDSAnyWriteTransaction) throws
}

// MARK: -

public protocol PaymentsHelperSwift: PaymentsHelper {

    var paymentsState: PaymentsState { get }
    func setPaymentsState(_ value: PaymentsState,
                          originatedLocally: Bool,
                          transaction: SDSAnyWriteTransaction)
    func clearState(transaction: SDSAnyWriteTransaction)
}

// MARK: -

public enum PaymentsState: Equatable, Dependencies {

    case disabled
    case disabledWithPaymentsEntropy(paymentsEntropy: Data)
    case enabled(paymentsEntropy: Data)

    // We should almost always construct instances of PaymentsState
    // using this method.  It enforces important invariants.
    //
    // * paymentsEntropy is not discarded.
    // * Payments are only enabled if paymentsEntropy is valid.
    // * Payments are only enabled if paymentsEntropy has valid length.
    public static func build(arePaymentsEnabled: Bool,
                             paymentsEntropy: Data?) -> PaymentsState {
        guard let paymentsEntropy = paymentsEntropy else {
            return .disabled
        }
        guard paymentsEntropy.count == PaymentsConstants.paymentsEntropyLength else {
            owsFailDebug("paymentsEntropy has invalid length: \(paymentsEntropy.count) != \(PaymentsConstants.paymentsEntropyLength).")
            return .disabled
        }
        if arePaymentsEnabled {
            return .enabled(paymentsEntropy: paymentsEntropy)
        } else {
            return .disabledWithPaymentsEntropy(paymentsEntropy: paymentsEntropy)
        }
    }

    public var isEnabled: Bool {
        switch self {
        case .enabled:
            return true
        case .disabled, .disabledWithPaymentsEntropy:
            return false
        }
    }

    public var paymentsEntropy: Data? {
        switch self {
        case .enabled(let paymentsEntropy):
            return paymentsEntropy
        case .disabled:
            return nil
        case .disabledWithPaymentsEntropy(let paymentsEntropy):
            return paymentsEntropy
        }
    }

    // MARK: Equatable

    public static func == (lhs: PaymentsState, rhs: PaymentsState) -> Bool {
        return (lhs.isEnabled == rhs.isEnabled &&
                lhs.paymentsEntropy == rhs.paymentsEntropy)
    }
}

// MARK: -

public class MockPaymentsHelper: NSObject {
}

// MARK: -

extension MockPaymentsHelper: PaymentsHelperSwift, PaymentsHelper {

    public var isKillSwitchActive: Bool { false }
    public var hasValidPhoneNumberForPayments: Bool { false }
    public var canEnablePayments: Bool { false }

    public var isPaymentsVersionOutdated: Bool { false }
    public func setPaymentsVersionOutdated(_ value: Bool) {}

    fileprivate static let keyValueStore = SDSKeyValueStore(collection: "MockPayments")
    public var keyValueStore: SDSKeyValueStore { Self.keyValueStore}

    public func warmCaches() {}

    public func setArePaymentsEnabled(for serviceId: ServiceIdObjC, hasPaymentsEnabled: Bool, transaction: SDSAnyWriteTransaction) {
        // Do nothing.
    }

    public func arePaymentsEnabled(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        owsFail("Not implemented.")
    }

    public var arePaymentsEnabled: Bool {
        owsFail("Not implemented.")
    }

    public func arePaymentsEnabled(tx: SDSAnyReadTransaction) -> Bool {
        owsFail("Not implemented.")
    }

    public var paymentsEntropy: Data? {
        owsFail("Not implemented.")
    }

    public func enablePayments(transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func enablePayments(withPaymentsEntropy: Data, transaction: SDSAnyWriteTransaction) -> Bool {
        owsFail("Not implemented.")
    }

    public func disablePayments(transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public var paymentsState: PaymentsState { .disabled }

    public func setPaymentsState(_ value: PaymentsState,
                                 originatedLocally: Bool,
                                 transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func clearState(transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func setLastKnownLocalPaymentAddressProtoData(_ data: Data?, transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func lastKnownLocalPaymentAddressProtoData(transaction: SDSAnyWriteTransaction) -> Data? {
        owsFail("Not implemented.")
    }

    public func processIncomingPaymentNotification(thread: TSThread,
                                                   paymentNotification: TSPaymentNotification,
                                                   senderAci: AciObjC,
                                                   transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func processIncomingPaymentsActivationRequest(
        thread: TSThread,
        senderAci: AciObjC,
        transaction: SDSAnyWriteTransaction
    ) {
        owsFail("Not implemented.")
    }

    public func processIncomingPaymentsActivatedMessage(
        thread: TSThread,
        senderAci: AciObjC,
        transaction: SDSAnyWriteTransaction
    ) {
        owsFail("Not implemented.")
    }

    public func processReceivedTranscriptPaymentNotification(thread: TSThread,
                                                             paymentNotification: TSPaymentNotification,
                                                             messageTimestamp: UInt64,
                                                             transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func processIncomingPaymentSyncMessage(_ paymentProto: SSKProtoSyncMessageOutgoingPayment,
                                                  messageTimestamp: UInt64,
                                                  transaction: SDSAnyWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func tryToInsertPaymentModel(_ paymentModel: TSPaymentModel,
                                        transaction: SDSAnyWriteTransaction) throws {
        owsFail("Not implemented.")
    }
}
