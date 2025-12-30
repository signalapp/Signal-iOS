//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol PaymentsHelper: AnyObject {

    func warmCaches()

    var keyValueStore: KeyValueStore { get }

    var isKillSwitchActive: Bool { get }
    var hasValidPhoneNumberForPayments: Bool { get }
    var canEnablePayments: Bool { get }

    var isPaymentsVersionOutdated: Bool { get }
    func setPaymentsVersionOutdated(_ value: Bool)

    func setArePaymentsEnabled(for serviceId: ServiceId, hasPaymentsEnabled: Bool, transaction: DBWriteTransaction)
    func arePaymentsEnabled(for address: SignalServiceAddress, transaction: DBReadTransaction) -> Bool

    var arePaymentsEnabled: Bool { get }
    func arePaymentsEnabled(tx: DBReadTransaction) -> Bool
    var paymentsEntropy: Data? { get }
    func enablePayments(transaction: DBWriteTransaction)
    func enablePayments(withPaymentsEntropy: Data, transaction: DBWriteTransaction) -> Bool
    func disablePayments(transaction: DBWriteTransaction)

    func setLastKnownLocalPaymentAddressProtoData(_ data: Data?, transaction: DBWriteTransaction)
    func lastKnownLocalPaymentAddressProtoData(transaction: DBWriteTransaction) -> Data?

    func processIncomingPaymentSyncMessage(
        _ paymentProto: SSKProtoSyncMessageOutgoingPayment,
        messageTimestamp: UInt64,
        transaction: DBWriteTransaction,
    )

    func processIncomingPaymentNotification(
        thread: TSThread,
        paymentNotification: TSPaymentNotification,
        senderAci: Aci,
        transaction: DBWriteTransaction,
    )

    func processIncomingPaymentsActivationRequest(
        thread: TSThread,
        senderAci: Aci,
        transaction: DBWriteTransaction,
    )

    func processIncomingPaymentsActivatedMessage(
        thread: TSThread,
        senderAci: Aci,
        transaction: DBWriteTransaction,
    )

    func processReceivedTranscriptPaymentNotification(
        thread: TSThread,
        paymentNotification: TSPaymentNotification,
        messageTimestamp: UInt64,
        transaction: DBWriteTransaction,
    )

    func tryToInsertPaymentModel(
        _ paymentModel: TSPaymentModel,
        transaction: DBWriteTransaction,
    ) throws
}

// MARK: -

public protocol PaymentsHelperSwift: PaymentsHelper {

    var paymentsState: PaymentsState { get }
    func setPaymentsState(
        _ value: PaymentsState,
        originatedLocally: Bool,
        transaction: DBWriteTransaction,
    )
    func clearState(transaction: DBWriteTransaction)
}

// MARK: -

public enum PaymentsState: Equatable {

    case disabled
    case disabledWithPaymentsEntropy(paymentsEntropy: Data)
    case enabled(paymentsEntropy: Data)

    // We should almost always construct instances of PaymentsState
    // using this method.  It enforces important invariants.
    //
    // * paymentsEntropy is not discarded.
    // * Payments are only enabled if paymentsEntropy is valid.
    // * Payments are only enabled if paymentsEntropy has valid length.
    public static func build(
        arePaymentsEnabled: Bool,
        paymentsEntropy: Data?,
    ) -> PaymentsState {
        guard let paymentsEntropy else {
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

    public static func ==(lhs: PaymentsState, rhs: PaymentsState) -> Bool {
        return lhs.isEnabled == rhs.isEnabled &&
            lhs.paymentsEntropy == rhs.paymentsEntropy
    }
}

// MARK: -

public class MockPaymentsHelper {}

// MARK: -

extension MockPaymentsHelper: PaymentsHelperSwift, PaymentsHelper {

    public var isKillSwitchActive: Bool { false }
    public var hasValidPhoneNumberForPayments: Bool { false }
    public var canEnablePayments: Bool { false }

    public var isPaymentsVersionOutdated: Bool { false }
    public func setPaymentsVersionOutdated(_ value: Bool) {}

    fileprivate static let keyValueStore = KeyValueStore(collection: "MockPayments")
    public var keyValueStore: KeyValueStore { Self.keyValueStore }

    public func warmCaches() {}

    public func setArePaymentsEnabled(for serviceId: ServiceId, hasPaymentsEnabled: Bool, transaction: DBWriteTransaction) {
        // Do nothing.
    }

    public func arePaymentsEnabled(for address: SignalServiceAddress, transaction: DBReadTransaction) -> Bool {
        owsFail("Not implemented.")
    }

    public var arePaymentsEnabled: Bool {
        owsFail("Not implemented.")
    }

    public func arePaymentsEnabled(tx: DBReadTransaction) -> Bool {
        owsFail("Not implemented.")
    }

    public var paymentsEntropy: Data? {
        owsFail("Not implemented.")
    }

    public func enablePayments(transaction: DBWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func enablePayments(withPaymentsEntropy: Data, transaction: DBWriteTransaction) -> Bool {
        owsFail("Not implemented.")
    }

    public func disablePayments(transaction: DBWriteTransaction) {
        owsFail("Not implemented.")
    }

    public var paymentsState: PaymentsState { .disabled }

    public func setPaymentsState(
        _ value: PaymentsState,
        originatedLocally: Bool,
        transaction: DBWriteTransaction,
    ) {
        owsFail("Not implemented.")
    }

    public func clearState(transaction: DBWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func setLastKnownLocalPaymentAddressProtoData(_ data: Data?, transaction: DBWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func lastKnownLocalPaymentAddressProtoData(transaction: DBWriteTransaction) -> Data? {
        owsFail("Not implemented.")
    }

    public func processIncomingPaymentNotification(
        thread: TSThread,
        paymentNotification: TSPaymentNotification,
        senderAci: Aci,
        transaction: DBWriteTransaction,
    ) {
        owsFail("Not implemented.")
    }

    public func processIncomingPaymentsActivationRequest(
        thread: TSThread,
        senderAci: Aci,
        transaction: DBWriteTransaction,
    ) {
        owsFail("Not implemented.")
    }

    public func processIncomingPaymentsActivatedMessage(
        thread: TSThread,
        senderAci: Aci,
        transaction: DBWriteTransaction,
    ) {
        owsFail("Not implemented.")
    }

    public func processReceivedTranscriptPaymentNotification(
        thread: TSThread,
        paymentNotification: TSPaymentNotification,
        messageTimestamp: UInt64,
        transaction: DBWriteTransaction,
    ) {
        owsFail("Not implemented.")
    }

    public func processIncomingPaymentSyncMessage(
        _ paymentProto: SSKProtoSyncMessageOutgoingPayment,
        messageTimestamp: UInt64,
        transaction: DBWriteTransaction,
    ) {
        owsFail("Not implemented.")
    }

    public func tryToInsertPaymentModel(
        _ paymentModel: TSPaymentModel,
        transaction: DBWriteTransaction,
    ) throws {
        owsFail("Not implemented.")
    }
}
