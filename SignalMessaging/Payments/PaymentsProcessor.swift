//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import MobileCoin

@objc
public class PaymentsProcessor: NSObject {

    // MARK: - Dependencies

    private static var databaseStorage: SDSDatabaseStorage {
        SDSDatabaseStorage.shared
    }

    private static var tsAccountManager: TSAccountManager {
        TSAccountManager.shared()
    }

    private static var payments: PaymentsImpl {
        SSKEnvironment.shared.payments as! PaymentsImpl
    }

    // MARK: -

    @objc
    public required override init() {
        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            Self.databaseStorage.appendUIDatabaseSnapshotDelegate(self)
        }
        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.process()
        }

        NotificationCenter.default.addObserver(forName: SSKReachability.owsReachabilityDidChange,
                                               object: nil, queue: nil) { [weak self] _ in
            self?.process()
        }
        NotificationCenter.default.addObserver(forName: .OWSApplicationDidBecomeActive,
                                               object: nil, queue: nil) { [weak self] _ in
            self?.process()
        }
        NotificationCenter.default.addObserver(forName: PaymentsImpl.arePaymentsEnabledDidChange,
                                               object: nil, queue: nil) { [weak self] _ in
            self?.process()
        }
    }

    private let isProcessing = AtomicBool(false)
    private let hasPendingWork = AtomicBool(false)
    private let batchCounter = AtomicUInt()

    let processingQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "PaymentsProcessor"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    // This method tries to process every "unresolved" transaction.
    //
    // For incoming transactions, this involves verification.
    //
    // For outgoing transactions, this involves verification,
    // sending a notification message, etc.
    //
    // We need to ensure that there's only one operation for a given
    // payment record at a time. This processor works in batches.
    // A given payment record's operation will make a best effort to
    // resolve that payment record until it is complete or failed,
    // although the operations may fail to do so.
    public func process() {
        DispatchQueue.global().async {
            guard !CurrentAppContext().isRunningTests else {
                return
            }
            guard FeatureFlags.payments,
                  Self.payments.arePaymentsEnabled else {
                return
            }
            guard AppReadiness.isAppReady,
                  CurrentAppContext().isMainAppAndActive,
                  Self.tsAccountManager.isRegisteredAndReady else {
                return
            }
            guard !DebugFlags.paymentsHaltProcessing.get() else {
                return
            }
            guard self.isProcessing.tryToSetFlag() else {
                // We're already processing a batch, wait for completion.
                self.hasPendingWork.set(true)
                return
            }
            self.hasPendingWork.set(false)
            let batchIndex = self.batchCounter.increment()

            let operations = self.buildOperationsForBatch()
            guard !operations.isEmpty else {
                // No work to do, exit early.
                guard self.isProcessing.tryToClearFlag() else {
                    owsFailDebug("Could not clear flag.")
                    return
                }
                return
            }

            let batchCompleteOperation = BlockOperation { [weak self] in
                guard let self = self else {
                    return
                }
                Logger.verbose("Batch complete: \(batchIndex)")
                guard self.isProcessing.tryToClearFlag() else {
                    owsFailDebug("Could not clear flag.")
                    return
                }
                if self.hasPendingWork.get() {
                    self.process()
                }
            }
            for operation in operations {
                batchCompleteOperation.addDependency(operation)
                self.processingQueue.addOperation(operation)
            }
            self.processingQueue.addOperation(batchCompleteOperation)
        }
    }

    // The list of payment states that _do not_ need processing.
    private static var paymentStatesToIgnore: Set<TSPaymentState> {
        Set([
            .outgoingComplete,
            .outgoingFailed,
            .incomingComplete,
            .incomingFailed
        ])
    }

    // The list of payment states that _do_ need processing.
    private static var paymentStatesToProcess: Set<TSPaymentState> {
        Set([
            .outgoingUnsubmitted,
            .outgoingUnverified,
            .outgoingVerified,
            .outgoingSending,
            //            .outgoingSendFailed,
            .outgoingSent,
            .outgoingMissingLedgerTimestamp,
            .incomingUnverified,
            .incomingVerified,
            .incomingMissingLedgerTimestamp
        ])
    }

    // PAYMENTS TODO: Add concept rate limiting of retry.
    private func buildOperationsForBatch() -> [Operation] {
        var operations = [Operation]()

        Self.databaseStorage.read { transaction in
            // Find all unresolved payment records.
            let paymentStatesToProcess = Array(Self.paymentStatesToProcess)
            let paymentModels = PaymentFinder.paymentModels(paymentStates: paymentStatesToProcess,
                                                            transaction: transaction)
            for paymentModel in paymentModels {
                let operation = PaymentProcessingOperation(paymentModel: paymentModel)
                operations.append(operation)
            }
        }

        return operations
    }
}

// MARK: -

extension PaymentsProcessor: UIDatabaseSnapshotDelegate {

    public func uiDatabaseSnapshotWillUpdate() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)
    }

    public func uiDatabaseSnapshotDidUpdate(databaseChanges: UIDatabaseChanges) {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        guard databaseChanges.didUpdateModel(collection: TSPaymentModel.collection()) else {
            return
        }

        process()
    }

    public func uiDatabaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        process()
    }

    public func uiDatabaseSnapshotDidReset() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        process()
    }
}

// MARK: -

// See comments on PaymentsProcessor.process().
class PaymentProcessingOperation: OWSOperation {

    // MARK: - Dependencies

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private static var payments: PaymentsImpl {
        SSKEnvironment.shared.payments as! PaymentsImpl
    }

    // MARK: -

    private let paymentModelUniqueId: String

    @objc
    public init(paymentModel: TSPaymentModel) {
        self.paymentModelUniqueId = paymentModel.uniqueId

        super.init()
    }

    override public func run() {
        firstly {
            process()
        }.done {
            self.reportSuccess()
        }.catch { error in
            self.reportError(error.asUnretryableError)
        }
    }

    // It's important that every operation completes in a reasonable
    // period of time, since we process in batches and can only have
    // one batch in flight at a time. If there is a new incoming or
    // outgoing transaction, we want to start processing it in a
    // reasonable amount of time. Therefore all operations in a given
    // batch should
    fileprivate static let maxInterval: TimeInterval = kSecondInterval * 30

    fileprivate static func buildBadDataError(_ message: String,
                                              file: String = #file,
                                              function: String = #function,
                                              line: Int = #line) -> Error {
        if DebugFlags.paymentsIgnoreBadData.get() {
            return OWSGenericError(message)
        } else {
            return OWSAssertionError(message, file: file, function: function, line: line)
        }
    }

    // Returns a process that will process payments, one step at a time.
    // The process will resolve when processing succeeds or fails.
    //
    // The key thing is that we need to user transactions/payments
    // through the various steps of the state machine as quickly as
    // possible, retry when necessary, and never get stuck in a retry
    // loop.  Additionally it's important that retries are throttled
    // and/or do backoff - but that depends on the type of operation.    
    private func process() -> Promise<Void> {

        let latestPaymentModel = { () -> TSPaymentModel? in
            Self.databaseStorage.read { transaction in
                TSPaymentModel.anyFetch(uniqueId: self.paymentModelUniqueId, transaction: transaction)
            }
        }
        guard let paymentModel = latestPaymentModel() else {
            Logger.verbose("Could not to process: \(paymentModelUniqueId)")
            return Promise(error: OWSAssertionError("Could not reload the payment record."))
        }
        guard !paymentModel.isUnidentified,
              !paymentModel.isOutgoingTransfer else {
            owsFailDebug("Invalid paymentModel: \(paymentModel.descriptionForLogs)")
            return Promise.value(())
        }

        owsAssertDebug(paymentModel.isValid)

        let formattedState = paymentModel.descriptionForLogs
        Logger.verbose("Trying to process: \(paymentModelUniqueId), \(formattedState)")

        switch paymentModel.paymentState {
        case .outgoingUnsubmitted:
            return firstly {
                self.submitOutgoingPayment(paymentModel: paymentModel)
            }.then(on: .global()) {
                // Proceed to the next steps of processing.
                self.process()
            }
        case .outgoingUnverified:
            return firstly {
                self.verifyOutgoingPayment(paymentModel: paymentModel)
            }.then(on: .global()) {
                // Proceed to the next steps of processing.
                self.process()
            }
        case .outgoingVerified:
            return firstly {
                self.sendPaymentNotificationMessage(paymentModel: paymentModel)
            }.then(on: .global()) {
                // Proceed to the next steps of processing.
                self.process()
            }
        case .outgoingSending,
             .outgoingSent:
            // After sending, make sure that the ledger timestamp is filled in.
            return Self.updatePaymentStatePromise(paymentModel: paymentModel,
                                                  fromState: paymentModel.paymentState,
                                                  toState: .outgoingMissingLedgerTimestamp)
        case .outgoingMissingLedgerTimestamp:
            if Self.canFillInMissingLedgerTimestamp(paymentModel: paymentModel) {
                return firstly {
                    Self.fillInMissingLedgerTimestampOutgoing(paymentModel: paymentModel)
                }.then(on: .global()) {
                    // Proceed to the next steps of processing.
                    self.process()
                }
            } else {
                return Promise.value(())
            }
        case .incomingUnverified:
            return firstly {
                self.verifyIncomingPayment(paymentModel: paymentModel)
            }.then(on: .global()) {
                // Proceed to the next steps of processing.
                self.process()
            }
        case .incomingVerified:
            // After verifying, make sure that the ledger timestamp is filled in.
            return Self.updatePaymentStatePromise(paymentModel: paymentModel,
                                                  fromState: .incomingVerified,
                                                  toState: .incomingMissingLedgerTimestamp)
        case .incomingMissingLedgerTimestamp:
            if Self.canFillInMissingLedgerTimestamp(paymentModel: paymentModel) {
                return firstly {
                    Self.fillInMissingLedgerTimestampIncoming(paymentModel: paymentModel)
                }.then(on: .global()) {
                    // Proceed to the next steps of processing.
                    self.process()
                }
            } else {
                return Promise.value(())
            }
        case .outgoingComplete,
             .incomingComplete:
            return Promise.value(())
        case .outgoingFailed,
             .incomingFailed:
            Logger.warn("Payment failed: \(formattedState)")
            return Promise.value(())
        @unknown default:
            return Promise(error: OWSAssertionError("Unknown paymentState: \(formattedState)"))
        }
    }

    private func submitOutgoingPayment(paymentModel: TSPaymentModel) -> Promise<Void> {
        owsAssertDebug(paymentModel.paymentState == .outgoingUnsubmitted)

        Logger.verbose("")

        // Only try to submit transactions within the first N minutes of them
        // being initiated.  If the app is terminated right after a transaction
        // is initiated (before transaction it can be submitted), we don't want
        // to submit it if the app is opened much later.
        let submissionInterval = kMinuteInterval * 5
        let createdDate = paymentModel.createdDate
        let isRecentEnoughToSubmit = abs(createdDate.timeIntervalSinceNow) <= submissionInterval

        guard isRecentEnoughToSubmit else {
            // We mark the payment as "unverified", not "failed". It's conceivable
            // that the transaction was submitted but the record was never marked
            // as such (due to a race around app being terminated).
            do {
                try Self.databaseStorage.write { transaction in
                    try paymentModel.updatePaymentModelState(fromState: .outgoingUnsubmitted,
                                                             toState: .outgoingUnverified,
                                                             transaction: transaction)
                }
            } catch {
                owsFailDebug("Error: \(error)")
            }
            Logger.warn("Not recent enough to submit.")
            return Promise(error: PaymentsError.tooOldToSubmit)
        }

        guard let mcTransactionData = paymentModel.mcTransactionData,
              mcTransactionData.count > 0,
              let transaction = MobileCoin.Transaction(serializedData: mcTransactionData) else {

            Self.handleIndeterminatePayment(paymentModel: paymentModel)

            return Promise(error: PaymentsError.indeterminateState)
        }

        return firstly { () -> Promise<MobileCoinAPI> in
            Self.payments.getMobileCoinAPI()
        }.then(on: .global()) { (mobileCoinAPI: MobileCoinAPI) -> Promise<Void> in
            return mobileCoinAPI.submitTransaction(transaction: transaction)
        }.map(on: .global()) { _ in
            try Self.databaseStorage.write { transaction in
                try paymentModel.updatePaymentModelState(fromState: .outgoingUnsubmitted,
                                                         toState: .outgoingUnverified,
                                                         transaction: transaction)
            }
        }.recover(on: .global()) { (error: Error) -> Promise<Void> in
            // Payments TODO: We need to handle certain errors here.
            // e.g. if we double-submit a transaction, it should become unverified,
            // not stuck in unsubmitted.
            //
            // Other errors might make this failed?
            throw error
        }
    }

    private func verifyOutgoingPayment(paymentModel: TSPaymentModel) -> Promise<Void> {
        owsAssertDebug(paymentModel.paymentState == .outgoingUnverified)

        Logger.verbose("")

        return firstly { () -> Promise<MobileCoinAPI> in
            Self.payments.getMobileCoinAPI()
        }.then(on: .global()) { (mobileCoinAPI: MobileCoinAPI) -> Promise<Void> in
            firstly { () -> Promise<MCOutgoingTransactionStatus> in
                Self.blockUntilOutgoingPaymentIsConfirmed(mobileCoinAPI: mobileCoinAPI,
                                                          paymentModel: paymentModel)
            }.map { (transactionStatus: MCOutgoingTransactionStatus) in
                Logger.verbose("transactionStatus: \(transactionStatus)")

                try Self.databaseStorage.write { transaction in
                    switch transactionStatus.transactionStatus {
                    case .unknown, .pending:
                        // TODO: Throw an error that we can catch and handle.
                        throw OWSAssertionError("Could not verify outgoing transaction.")
                    case .accepted(let block):
                        if !paymentModel.hasMCLedgerBlockIndex {
                            paymentModel.update(mcLedgerBlockIndex: block.index, transaction: transaction)
                        }
                        if let ledgerBlockDate = block.timestamp,
                           !paymentModel.hasMCLedgerBlockTimestamp {
                            paymentModel.update(mcLedgerBlockTimestamp: ledgerBlockDate.ows_millisecondsSince1970,
                                                transaction: transaction)
                        }
                        try paymentModel.updatePaymentModelState(fromState: .outgoingUnverified,
                                                                 toState: .outgoingVerified,
                                                                 transaction: transaction)

                        // If we've verified a payment, our balance may have changed.
                        Self.payments.updateCurrentPaymentBalance()
                    case .failed:
                        try paymentModel.updatePaymentModelState(fromState: .outgoingUnverified,
                                                                 toState: .outgoingFailed,
                                                                 transaction: transaction)
                        // TODO: Throw an error that we can catch and handle.
                        throw Self.buildBadDataError("Could not verify outgoing transaction.")
                    }
                }
            }
        }
    }

    private class func markAsFailedPromise(paymentModel: TSPaymentModel,
                                           paymentFailure: TSPaymentFailure,
                                           paymentState: TSPaymentState) -> Promise<Void> {
        Self.databaseStorage.write(.promise) { transaction in
            markAsFailed(paymentModel: paymentModel,
                         paymentFailure: paymentFailure,
                         paymentState: paymentState,
                         transaction: transaction)
        }
    }

    private class func markAsFailed(paymentModel: TSPaymentModel,
                                    paymentFailure: TSPaymentFailure,
                                    paymentState: TSPaymentState) {
        Self.databaseStorage.write { transaction in
            markAsFailed(paymentModel: paymentModel,
                         paymentFailure: paymentFailure,
                         paymentState: paymentState,
                         transaction: transaction)
        }
    }

    private class func markAsFailed(paymentModel: TSPaymentModel,
                                    paymentFailure: TSPaymentFailure,
                                    paymentState: TSPaymentState,
                                    transaction: SDSAnyWriteTransaction) {
        paymentModel.update(withPaymentFailure: paymentFailure,
                            paymentState: paymentState,
                            transaction: transaction)
    }

    private func sendPaymentNotificationMessage(paymentModel: TSPaymentModel) -> Promise<Void> {
        owsAssertDebug(paymentModel.paymentState == .outgoingVerified)

        Logger.verbose("")

        guard !paymentModel.isOutgoingTransfer else {
            // No need to notify for "transfer out" transactions.
            return Self.updatePaymentStatePromise(paymentModel: paymentModel,
                                                  fromState: .outgoingVerified,
                                                  toState: .outgoingSent)
        }

        return firstly(on: .global()) { () -> Void in
            try Self.databaseStorage.write { transaction in
                guard let paymentModel = TSPaymentModel.anyFetch(uniqueId: paymentModel.uniqueId, transaction: transaction) else {
                    throw OWSAssertionError("Missing paymentModel.")
                }
                guard paymentModel.paymentState == .outgoingVerified else {
                    throw OWSAssertionError("Unexpected paymentState: \(paymentModel.descriptionForLogs).")
                }
                do {
                    let notify = {
                        _ = try PaymentsImpl.sendPaymentNotificationMessage(paymentModel: paymentModel,
                                                                            transaction: transaction)
                        PaymentsImpl.sendOutgoingPaymentSyncMessage(paymentModel: paymentModel,
                                                                    transaction: transaction)
                    }

                    try notify()

                    if DebugFlags.paymentsDoubleNotify.get() {
                        // Notify again.
                        try notify()
                    }

                    try paymentModel.updatePaymentModelState(fromState: .outgoingVerified,
                                                             toState: .outgoingSending,
                                                             transaction: transaction)
                } catch {
                    if case PaymentsError.invalidModel = error {
                        try paymentModel.updatePaymentModelState(fromState: .outgoingVerified,
                                                                 toState: .outgoingComplete,
                                                                 transaction: transaction)
                    }
                    throw error
                }
            }
        }.asVoid()
    }

    private func verifyIncomingPayment(paymentModel: TSPaymentModel) -> Promise<Void> {
        owsAssertDebug(paymentModel.paymentState == .incomingUnverified)

        Logger.verbose("")

        return firstly { () -> Promise<MobileCoinAPI> in
            Self.payments.getMobileCoinAPI()
        }.then(on: .global()) { (mobileCoinAPI: MobileCoinAPI) -> Promise<MCIncomingReceiptStatus> in
            Self.blockUntilIncomingPaymentIsConfirmed(mobileCoinAPI: mobileCoinAPI,
                                                      paymentModel: paymentModel)
        }.map { (receiptStatus: MCIncomingReceiptStatus) in
            Logger.verbose("receiptStatus: \(receiptStatus)")

            try Self.databaseStorage.write { transaction in
                switch receiptStatus.receiptStatus {
                case .unknown:
                    // TODO: Throw an error that we can catch and handle.
                    throw OWSAssertionError("Could not verify incoming receipt.")
                case .received(let block):
                    paymentModel.update(mcLedgerBlockIndex: block.index,
                                        transaction: transaction)
                    if let ledgerBlockDate = block.timestamp {
                        paymentModel.update(mcLedgerBlockTimestamp: ledgerBlockDate.ows_millisecondsSince1970,
                                            transaction: transaction)
                    } else {
                        Logger.warn("Missing ledgerBlockDate.")
                    }
                    paymentModel.update(withPaymentAmount: receiptStatus.paymentAmount,
                                        transaction: transaction)
                    try paymentModel.updatePaymentModelState(fromState: .incomingUnverified,
                                                             toState: .incomingVerified,
                                                             transaction: transaction)

                    // If we've verified a payment, our balance may have changed.
                    Self.payments.updateCurrentPaymentBalance()
                case .failed:
                    // PAYMENTS TODO: Distinguish retryable and unretryable failures.
                    let paymentFailure: TSPaymentFailure = .validationFailed
                    Self.markAsFailed(paymentModel: paymentModel,
                                      paymentFailure: paymentFailure,
                                      paymentState: .incomingFailed,
                                      transaction: transaction)
                    // TODO: Throw an error that we can catch and handle.
                    throw OWSGenericError("Invalid incoming receipt.")
                }
            }
        }
        // TODO: Here and in other steps of the processor we need to catch/recover from errors
        //       and update the model state/failure state appropriately.
    }
}

// MARK: -

fileprivate extension PaymentProcessingOperation {

    class func handleIndeterminatePayment(paymentModel: TSPaymentModel) {
        owsFailDebug("Indeterminate payment: \(paymentModel.descriptionForLogs)")

        // A payment is indeterminate if we don't know if it exists
        // in the ledger and have no way to resolve that.  For example,
        // a user might submit a payment, then scrub the payment before
        // it is verified.  In this case, the only way to recover is
        // to discard the payment record and reconcile using the transaction
        // history.  Presumably this should only be possible if the user
        // scrubs an unverified payment.

        databaseStorage.write { transaction in
            paymentModel.anyRemove(transaction: transaction)

            Self.payments.scheduleReconciliationNow(transaction: transaction)
        }
    }

    // TODO: Remove the blockUntil...() methods.
    class func blockUntilOutgoingPaymentIsConfirmed(mobileCoinAPI: MobileCoinAPI,
                                                    paymentModel: TSPaymentModel) -> Promise<MCOutgoingTransactionStatus> {
        let maxWaitInterval: TimeInterval = PaymentProcessingOperation.maxInterval

        guard let mcTransactionData = paymentModel.mcTransactionData,
              mcTransactionData.count > 0,
              let transaction = MobileCoin.Transaction(serializedData: mcTransactionData) else {

            Self.handleIndeterminatePayment(paymentModel: paymentModel)

            return Promise(error: PaymentsError.indeterminateState)
        }

        return firstly(on: .global()) { () -> Promise<MCOutgoingTransactionStatus> in
            let lastTryDate = Date().addingTimeInterval(maxWaitInterval)
            return self.blockUntilOutgoingPaymentIsConfirmed(mobileCoinAPI: mobileCoinAPI,
                                                             transaction: transaction,
                                                             lastTryDate: lastTryDate)
        }.timeout(seconds: maxWaitInterval, description: "blockUntilOutgoingPaymentIsConfirmed") { () -> Error in
            PaymentsError.timeout
        }
    }

    class func blockUntilOutgoingPaymentIsConfirmed(mobileCoinAPI: MobileCoinAPI,
                                                    transaction: MobileCoin.Transaction,
                                                    lastTryDate: Date) -> Promise<MCOutgoingTransactionStatus> {
        firstly {
            mobileCoinAPI.getOutgoingTransactionStatus(transaction: transaction)
        }.then(on: .global()) { (transactionStatus: MCOutgoingTransactionStatus) -> Promise<MCOutgoingTransactionStatus> in
            switch transactionStatus.transactionStatus {
            case .unknown, .pending:
                Logger.verbose("timeIntervalSinceNow: \(lastTryDate.timeIntervalSinceNow)")
                guard lastTryDate.timeIntervalSinceNow > 0 else {
                    Logger.warn("Could not confirm transaction status.")
                    throw PaymentsError.timeout
                }
                Logger.warn("Retrying.")
                return firstly {
                    // Wait before retrying.
                    after(seconds: 1)
                }.then(on: .global()) { () -> Promise<MCOutgoingTransactionStatus> in
                    return self.blockUntilOutgoingPaymentIsConfirmed(mobileCoinAPI: mobileCoinAPI,
                                                                     transaction: transaction,
                                                                     lastTryDate: lastTryDate)
                }
            case .accepted, .failed:
                return Promise.value(transactionStatus)
            }
        }.recover(on: .global()) { (error: Error) -> Promise<MCOutgoingTransactionStatus> in
            // TODO: We need to handle more errors here.
            // TODO: Maybe we should stop retrying if Reachability thinks we have
            //       no connection.
            if error as? MobileCoin.ConnectionFailure != nil {
                Logger.verbose("timeIntervalSinceNow: \(lastTryDate.timeIntervalSinceNow)")
                guard lastTryDate.timeIntervalSinceNow > 0 else {
                    throw error
                }
                // Retry
                Logger.warn("Error: \(error)")
                return self.blockUntilOutgoingPaymentIsConfirmed(mobileCoinAPI: mobileCoinAPI,
                                                                 transaction: transaction,
                                                                 lastTryDate: lastTryDate)
            } else {
                throw error
            }
        }
    }

    class func blockUntilIncomingPaymentIsConfirmed(mobileCoinAPI: MobileCoinAPI,
                                                    paymentModel: TSPaymentModel) -> Promise<MCIncomingReceiptStatus> {
        let maxWaitInterval: TimeInterval = PaymentProcessingOperation.maxInterval

        guard let mcReceiptData = paymentModel.mcReceiptData,
              let receipt = MobileCoin.Receipt(serializedData: mcReceiptData) else {

            Self.handleIndeterminatePayment(paymentModel: paymentModel)

            return Promise(error: PaymentsError.indeterminateState)
        }

        return firstly(on: .global()) { () -> Promise<MCIncomingReceiptStatus> in
            let lastTryDate = Date().addingTimeInterval(maxWaitInterval)
            return self.blockUntilIncomingPaymentIsConfirmed(mobileCoinAPI: mobileCoinAPI,
                                                             receipt: receipt,
                                                             lastTryDate: lastTryDate)
        }.timeout(seconds: maxWaitInterval, description: "blockUntilIncomingPaymentIsConfirmed") { () -> Error in
            PaymentsError.timeout
        }
    }

    class func blockUntilIncomingPaymentIsConfirmed(mobileCoinAPI: MobileCoinAPI,
                                                    receipt: MobileCoin.Receipt,
                                                    lastTryDate: Date) -> Promise<MCIncomingReceiptStatus> {
        firstly {
            mobileCoinAPI.getIncomingReceiptStatus(receipt: receipt)
        }.then(on: .global()) { (receiptStatus: MCIncomingReceiptStatus) -> Promise<MCIncomingReceiptStatus> in
            switch receiptStatus.receiptStatus {
            case .unknown:
                Logger.verbose("timeIntervalSinceNow: \(lastTryDate.timeIntervalSinceNow)")
                guard lastTryDate.timeIntervalSinceNow > 0 else {
                    Logger.warn("Could not confirm transaction status.")
                    throw PaymentsError.timeout
                }
                Logger.warn("Retrying.")
                return firstly {
                    // Wait before retrying.
                    after(seconds: 1)
                }.then(on: .global()) { () -> Promise<MCIncomingReceiptStatus> in
                    return self.blockUntilIncomingPaymentIsConfirmed(mobileCoinAPI: mobileCoinAPI,
                                                                     receipt: receipt,
                                                                     lastTryDate: lastTryDate)
                }
            case .received, .failed:
                return Promise.value(receiptStatus)
            }
        }.recover(on: .global()) { (error: Error) -> Promise<MCIncomingReceiptStatus> in
            // TODO: We need to handle more errors here.
            // TODO: Maybe we should stop retrying if Reachability thinks we have
            //       no connection.
            if error as? MobileCoin.ConnectionFailure != nil {
                Logger.verbose("timeIntervalSinceNow: \(lastTryDate.timeIntervalSinceNow)")
                guard lastTryDate.timeIntervalSinceNow > 0 else {
                    throw error
                }
                // Retry
                Logger.warn("Error: \(error)")
                return self.blockUntilIncomingPaymentIsConfirmed(mobileCoinAPI: mobileCoinAPI,
                                                                 receipt: receipt,
                                                                 lastTryDate: lastTryDate)
            } else {
                throw error
            }
        }
    }

    // MARK: -

    private static let unfairLock = UnfairLock()
    private static var fillInMissingLedgerTimestampDateMap = [String: Date]()

    static func canFillInMissingLedgerTimestamp(paymentModel: TSPaymentModel) -> Bool {
        unfairLock.withLock {
            guard !paymentModel.hasMCLedgerBlockTimestamp else {
                // The ledger timestamp isn't missing, we just need to update
                // the payment state to reflect that.
                Logger.verbose("ledgerBlockDate already present; just need to mark it as such.")
                return true
            }
            guard let lastAttemptDate = fillInMissingLedgerTimestampDateMap[paymentModel.uniqueId] else {
                Logger.verbose("No previous attempt.")
                return true
            }
            // Only try to fill in missing ledger timestamps once per hour.
            let maxAttemptFrequency: TimeInterval = kHourInterval
            Logger.verbose("Last attempt: \(abs(lastAttemptDate.timeIntervalSinceNow)).")
            return abs(lastAttemptDate.timeIntervalSinceNow) > maxAttemptFrequency
        }
    }

    private static func updatePaymentStatePromise(paymentModel: TSPaymentModel,
                                                  fromState: TSPaymentState,
                                                  toState: TSPaymentState) -> Promise<Void> {
        owsAssertDebug(paymentModel.paymentState == fromState)

        return firstly(on: .global()) { () -> Void in
            try Self.databaseStorage.write { transaction in
                guard let paymentModel = TSPaymentModel.anyFetch(uniqueId: paymentModel.uniqueId,
                                                                 transaction: transaction) else {
                    throw OWSAssertionError("Missing TSPaymentModel.")
                }
                guard paymentModel.paymentState == fromState else {
                    throw OWSAssertionError("Unexpected paymentState: \(paymentModel.paymentState.formatted) != \(fromState.formatted).")
                }
                paymentModel.update(paymentState: toState, transaction: transaction)
            }
        }
    }

    private static func fillInMissingLedgerTimestampIncoming(paymentModel: TSPaymentModel) -> Promise<Void> {
        owsAssertDebug(paymentModel.paymentState == .incomingMissingLedgerTimestamp)

        guard !paymentModel.hasMCLedgerBlockTimestamp else {
            // The ledger timestamp isn't missing, we just need to update
            // the payment state to reflect that.
            return updatePaymentStatePromise(paymentModel: paymentModel,
                                             fromState: .incomingMissingLedgerTimestamp,
                                             toState: .incomingComplete)
        }

        unfairLock.withLock {
            fillInMissingLedgerTimestampDateMap[paymentModel.uniqueId] = Date()
        }

        Logger.verbose("")

        return firstly { () -> Promise<MobileCoinAPI> in
            Self.payments.getMobileCoinAPI()
        }.then(on: .global()) { (mobileCoinAPI: MobileCoinAPI) -> Promise<MCIncomingReceiptStatus> in
            guard let mcReceiptData = paymentModel.mcReceiptData,
                  let receipt = MobileCoin.Receipt(serializedData: mcReceiptData) else {
                // We'll never be able to fill in the missing ledger timestamp
                // without the receipt, so skip to complete.
                try Self.databaseStorage.write { transaction in
                    try paymentModel.updatePaymentModelState(fromState: .incomingMissingLedgerTimestamp,
                                                             toState: .incomingComplete,
                                                             transaction: transaction)
                }
                throw Self.buildBadDataError("Missing or invalid mcReceiptData.")
            }
            return mobileCoinAPI.getIncomingReceiptStatus(receipt: receipt)
        }.map { (receiptStatus: MCIncomingReceiptStatus) -> Void in
            Logger.verbose("receiptStatus: \(receiptStatus.receiptStatus)")

            switch receiptStatus.receiptStatus {
            case .unknown:
                throw OWSGenericError("Receipt status: unknown.")
            case .received(let block):
                guard let ledgerBlockDate = block.timestamp else {
                    Logger.warn("Could not fill in ledger timestamp for transaction.")
                    return
                }
                try Self.databaseStorage.write { transaction in
                    paymentModel.update(mcLedgerBlockTimestamp: ledgerBlockDate.ows_millisecondsSince1970,
                                        transaction: transaction)
                    // This will throw if the fromState is unexpected.
                    try paymentModel.updatePaymentModelState(fromState: .incomingMissingLedgerTimestamp,
                                                             toState: .incomingComplete,
                                                             transaction: transaction)
                }
            case .failed:
                // This should never happen, since we've already verified the receipt.
                Self.markAsFailed(paymentModel: paymentModel,
                                  paymentFailure: .validationFailed,
                                  paymentState: .incomingFailed)
                throw OWSAssertionError("Receipt status: failed.")
            }
        }
    }

    private static func fillInMissingLedgerTimestampOutgoing(paymentModel: TSPaymentModel) -> Promise<Void> {
        owsAssertDebug(paymentModel.paymentState == .outgoingMissingLedgerTimestamp)

        guard !paymentModel.hasMCLedgerBlockTimestamp else {
            // The ledger timestamp isn't missing, we just need to update
            // the payment state to reflect that.
            Logger.verbose("ledgerBlockDate already present; just need to mark it as such.")
            return updatePaymentStatePromise(paymentModel: paymentModel,
                                             fromState: .outgoingMissingLedgerTimestamp,
                                             toState: .outgoingComplete)
        }

        unfairLock.withLock {
            fillInMissingLedgerTimestampDateMap[paymentModel.uniqueId] = Date()
        }

        Logger.verbose("")

        return firstly { () -> Promise<MobileCoinAPI> in
            Self.payments.getMobileCoinAPI()
        }.then(on: .global()) { (mobileCoinAPI: MobileCoinAPI) -> Promise<MCOutgoingTransactionStatus> in
            guard let mcTransactionData = paymentModel.mcTransactionData,
                  let transaction = MobileCoin.Transaction(serializedData: mcTransactionData) else {
                // We'll never be able to fill in the missing ledger timestamp
                // without the transaction, so skip to complete.
                try Self.databaseStorage.write { transaction in
                    try paymentModel.updatePaymentModelState(fromState: .outgoingMissingLedgerTimestamp,
                                                             toState: .outgoingComplete,
                                                             transaction: transaction)
                }
                throw Self.buildBadDataError("Missing or invalid mcTransactionData.")
            }
            return mobileCoinAPI.getOutgoingTransactionStatus(transaction: transaction)
        }.map { (transactionStatus: MCOutgoingTransactionStatus) -> Void in
            Logger.verbose("transactionStatus: \(transactionStatus)")

            switch transactionStatus.transactionStatus {
            case .unknown:
                throw OWSGenericError("Receipt status: unknown.")
            case .pending:
                throw OWSGenericError("Receipt status: pending.")
            case .accepted(let block):
                guard let ledgerBlockDate = block.timestamp else {
                    Logger.warn("Could not fill in ledger timestamp for transaction.")
                    return
                }
                try Self.databaseStorage.write { transaction in
                    paymentModel.update(mcLedgerBlockTimestamp: ledgerBlockDate.ows_millisecondsSince1970,
                                        transaction: transaction)
                    // This will throw if the fromState is unexpected.
                    try paymentModel.updatePaymentModelState(fromState: .outgoingMissingLedgerTimestamp,
                                                             toState: .outgoingComplete,
                                                             transaction: transaction)
                }
            case .failed:
                // This should never happen since we've already verified the transaction.
                Self.markAsFailed(paymentModel: paymentModel,
                                  paymentFailure: .invalid,
                                  paymentState: .outgoingFailed)
                throw OWSAssertionError("Receipt status: failed.")
            }
        }
    }
}
