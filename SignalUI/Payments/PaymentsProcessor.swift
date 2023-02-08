//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MobileCoin

@objc
public class PaymentsProcessor: NSObject {

    @objc
    public required override init() {
        super.init()

        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            Self.databaseStorage.appendDatabaseChangeDelegate(self)
        }
        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.process()
        }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(process),
                                               name: SSKReachability.owsReachabilityDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(process),
                                               name: .OWSApplicationDidBecomeActive,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(process),
                                               name: PaymentsConstants.arePaymentsEnabledDidChange,
                                               object: nil)
    }

    private static let unfairLock = UnfairLock()

    // Each instance of PaymentProcessingOperation represents
    // an attempt to usher a payment "one step forward" in the
    // processing state machine.
    //
    // On success, a PaymentProcessingOperation will enqueue
    // a new PaymentProcessingOperation to continue the process
    // until the payment is complete or failed.
    //
    // If a PaymentProcessingOperation fails but can be retried,
    // we'll enqueue a new PaymentProcessingOperation (possibly
    // after a retry delay).
    //
    // We use this collection to ensure that we don't process
    // a payment that is already being processed via a sequence
    // of PaymentProcessingOperations.
    //
    // This should only be accessed via unfairLock.
    private var processingPaymentIds = Set<String>()

    // We use a dedicated queue for processing
    // "outgoing, not yet verified" payments.
    //
    // This ensures that they are processed serially.
    let processingQueue_outgoing: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "PaymentsProcessor.outgoing"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()
    // We use another queue for all other processing.
    let processingQueue_default: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "PaymentsProcessor.default"
        // We want a concurrency level high enough to ensure that
        // high-priority operations are processed in a timely manner.
        operationQueue.maxConcurrentOperationCount = 3
        return operationQueue
    }()

    private func processingQueue(forPaymentModel paymentModel: TSPaymentModel) -> OperationQueue {
        if paymentModel.isOutgoing,
           !paymentModel.isVerified {
            return processingQueue_outgoing
        } else {
            return processingQueue_default
        }
    }

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
    @objc
    public func process() {
        DispatchQueue.global().async {
            guard !CurrentAppContext().isRunningTests else {
                return
            }
            guard Self.paymentsHelper.arePaymentsEnabled else {
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

            // Kick of processing for any payments that need
            // processing but are not yet being processed.
            self.buildProcessingOperations()
        }
    }

    private func buildProcessingOperations() {

        // Find all unresolved payment records.
        var paymentModels: [TSPaymentModel] = Self.databaseStorage.read { transaction in
            PaymentFinder.paymentModels(paymentStates: Array(Self.paymentStatesToProcess),
                                        transaction: transaction)
        }

        paymentModels.sort { (left, right) -> Bool in
            left.sortDate.compare(right.sortDate) == .orderedAscending
        }

        // Create a new operation for any payment that needs to be
        // processed that we're not already processing.
        let delegate: PaymentProcessingOperationDelegate = self
        Self.unfairLock.withLock {
            for paymentModel in paymentModels {
                let paymentId = paymentModel.uniqueId
                // Don't add an operation if we're already processing this payment model.
                guard !self.processingPaymentIds.contains(paymentId) else {
                    continue
                }
                self.processingPaymentIds.insert(paymentId)
                Logger.verbose("Start processing: \(paymentId) \(paymentModel.descriptionForLogs)")
                let operation = PaymentProcessingOperation(delegate: delegate,
                                                           paymentModel: paymentModel)
                processingQueue(forPaymentModel: paymentModel).addOperation(operation)
            }
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
            .outgoingSent,
            .incomingUnverified,
            .incomingVerified
        ])
    }

    // MARK: - RetryScheduler

    // Retries occur after a fixed delay (e.g. per exponential backoff)
    // but this should short-circuit if reachability becomes available.
    @objc
    fileprivate class RetryScheduler: NSObject {

        private let paymentModel: TSPaymentModel
        private let nextRetryDelayInteral: TimeInterval
        private weak var delegate: PaymentProcessingOperationDelegate?
        private let hasScheduled = AtomicBool(false)
        private var timer: Timer?

        var paymentId: String { paymentModel.uniqueId }

        init(paymentModel: TSPaymentModel,
             retryDelayInteral: TimeInterval,
             nextRetryDelayInteral: TimeInterval,
             delegate: PaymentProcessingOperationDelegate) {

            self.paymentModel = paymentModel
            self.nextRetryDelayInteral = nextRetryDelayInteral
            self.delegate = delegate

            super.init()

            DispatchQueue.global().asyncAfter(deadline: .now() + retryDelayInteral) { [weak self] in
                self?.tryToSchedule()
            }
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(reachabilityChanged),
                                                   name: SSKReachability.owsReachabilityDidChange,
                                                   object: nil)
        }

        @objc
        private func reachabilityChanged() {
            AssertIsOnMainThread()

            guard reachabilityManager.isReachable else {
                return
            }

            tryToSchedule()
        }

        private func tryToSchedule() {
            guard hasScheduled.tryToSetFlag() else {
                return
            }

            timer?.invalidate()
            timer = nil

            delegate?.retryProcessing(paymentModel: paymentModel,
                                      nextRetryDelayInteral: nextRetryDelayInteral)
        }
    }

    private var retrySchedulerMap = [String: RetryScheduler]()

    private func add(retryScheduler: RetryScheduler) {
        Self.unfairLock.withLock {
            retrySchedulerMap[retryScheduler.paymentId] = retryScheduler
        }
    }

    private func remove(retryScheduler: RetryScheduler) {
        Self.unfairLock.withLock {
            _ = retrySchedulerMap.removeValue(forKey: retryScheduler.paymentId)
        }
    }
}

// MARK: -

extension PaymentsProcessor: DatabaseChangeDelegate {

    public func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        guard databaseChanges.didUpdateModel(collection: TSPaymentModel.collection()) else {
            return
        }

        process()
    }

    public func databaseChangesDidUpdateExternally() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        process()
    }

    public func databaseChangesDidReset() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        process()
    }
}

// MARK: - PaymentProcessingOperationDelegate

extension PaymentsProcessor: PaymentProcessingOperationDelegate {

    static func canBeProcessed(paymentModel: TSPaymentModel) -> Bool {
        guard !paymentModel.isUnidentified,
              !paymentModel.isComplete,
              !paymentModel.isFailed else {
            return false
        }
        return true
    }

    func continueProcessing(paymentModel: TSPaymentModel) {
        tryToScheduleProcessingOperation(paymentModel: paymentModel,
                                         label: "Continue processing",
                                         retryDelayInteral: nil)
    }

    func retryProcessing(paymentModel: TSPaymentModel, nextRetryDelayInteral: TimeInterval) {
        tryToScheduleProcessingOperation(paymentModel: paymentModel,
                                         label: "Retry processing",
                                         retryDelayInteral: nextRetryDelayInteral)
    }

    private func tryToScheduleProcessingOperation(paymentModel: TSPaymentModel,
                                                  label: String,
                                                  retryDelayInteral: TimeInterval?) {
        let paymentId = paymentModel.uniqueId

        Self.unfairLock.withLock {
            owsAssertDebug(processingPaymentIds.contains(paymentId))
        }

        guard Self.canBeProcessed(paymentModel: paymentModel) else {
            self.endProcessing(paymentModel: paymentModel)
            return
        }

        Logger.verbose("\(label): \(paymentId)")

        let operation = PaymentProcessingOperation(delegate: self,
                                                   paymentModel: paymentModel,
                                                   retryDelayInteral: retryDelayInteral)
        processingQueue(forPaymentModel: paymentModel).addOperation(operation)
    }

    func scheduleRetryProcessing(paymentModel: TSPaymentModel,
                                 retryDelayInteral: TimeInterval,
                                 nextRetryDelayInteral: TimeInterval) {
        let paymentId = paymentModel.uniqueId
        Logger.verbose("schedule retry: \(paymentId), retryDelayInteral: \(retryDelayInteral), nextRetryDelayInteral: \(nextRetryDelayInteral)")
        add(retryScheduler: RetryScheduler(paymentModel: paymentModel,
                                           retryDelayInteral: retryDelayInteral,
                                           nextRetryDelayInteral: nextRetryDelayInteral,
                                           delegate: self))
    }

    func endProcessing(paymentModel: TSPaymentModel) {
        endProcessing(paymentId: paymentModel.uniqueId)
    }

    func endProcessing(paymentId: String) {
        Logger.verbose("End processing: \(paymentId)")
        Self.unfairLock.withLock {
            owsAssertDebug(processingPaymentIds.contains(paymentId))
            processingPaymentIds.remove(paymentId)
        }
    }
}

// MARK: -

private protocol PaymentProcessingOperationDelegate: AnyObject {
    func continueProcessing(paymentModel: TSPaymentModel)
    func retryProcessing(paymentModel: TSPaymentModel,
                         nextRetryDelayInteral: TimeInterval)
    func scheduleRetryProcessing(paymentModel: TSPaymentModel,
                                 retryDelayInteral: TimeInterval,
                                 nextRetryDelayInteral: TimeInterval)
    func endProcessing(paymentModel: TSPaymentModel)
    func endProcessing(paymentId: String)
}

// MARK: -

// See comments on PaymentsProcessor.process().
private class PaymentProcessingOperation: OWSOperation {

    private weak var delegate: PaymentProcessingOperationDelegate?
    private let paymentId: String
    private let retryDelayInteral: TimeInterval

    private static let defaultRetryDelayInteral: TimeInterval = 1 * kSecondInterval

    init(delegate: PaymentProcessingOperationDelegate,
         paymentModel: TSPaymentModel,
         retryDelayInteral: TimeInterval? = nil) {
        self.delegate = delegate
        self.paymentId = paymentModel.uniqueId
        self.retryDelayInteral = retryDelayInteral ?? Self.defaultRetryDelayInteral

        super.init()

        self.queuePriority = queuePriority(forPaymentModel: paymentModel)
    }

    private func queuePriority(forPaymentModel paymentModel: TSPaymentModel) -> Operation.QueuePriority {
        switch paymentModel.paymentState {
        case .outgoingUnsubmitted,
             .outgoingUnverified:
            return .veryHigh
        case .outgoingVerified,
            .outgoingSending,
            .outgoingSent:
            return .normal
        case .incomingUnverified,
             .incomingVerified:
            return .high
        case .outgoingComplete,
             .incomingComplete,
             .outgoingFailed,
             .incomingFailed:
            owsFailDebug("Unexpected paymentState: \(paymentModel.paymentState.formatted)")
            return .normal
        @unknown default:
            owsFailDebug("Invalid paymentState: \(paymentModel.paymentState.formatted)")
            return .normal
        }
    }

    override public func run() {
        firstly {
            processStep()
        }.done {
            self.reportSuccess()
        }.catch { error in
            // processStep() should never fail.
            owsFailDebug("Unexpected error: \(error)")
            self.reportError(SSKUnretryableError.paymentsProcessingFailure)
        }
    }

    // It's important that every operation completes in a reasonable
    // period of time, to ensure that the operation queue doesn't
    // stall and payments are processed in a timely manner.
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

    // Try to usher a payment "one step forward" in the processing
    // state machine.
    //
    // We need to user transactions/payments through the various
    // steps of the state machine as quickly as possible, retry when
    // necessary, and avoid getting stuck in a tight retry loop.
    // Therefore retries are throttled and/or do backoff - but retry
    // behavior depends on the type of operation.
    private func processStep() -> Guarantee<Void> {
        // When this promise chain completes, we must call continueProcessing()
        // or endProcessing().
        firstly(on: DispatchQueue.global()) { () -> Promise<TSPaymentModel> in
            self.processStep(paymentModel: self.loadPaymentModelWithSneakyTransaction())
        }.timeout(seconds: Self.timeoutDuration, description: "process") { () -> Error in
            PaymentsError.timeout
        }.done(on: DispatchQueue.global()) { paymentModel in
            self.delegate?.continueProcessing(paymentModel: paymentModel)
        }.recover(on: DispatchQueue.global()) { (error: Error) -> Guarantee<Void> in
            switch error {
            case let paymentsError as PaymentsError:
                switch paymentsError {
                case .notEnabled,
                     .userNotRegisteredOrAppNotReady,
                     .userHasNoPublicAddress,
                     .invalidCurrency,
                     .invalidWalletKey,
                     .invalidAmount,
                     .invalidFee,
                     .insufficientFunds,
                     .invalidModel,
                     .tooOldToSubmit,
                     .indeterminateState,
                     .unknownSDKError,
                     .invalidInput,
                     .invalidServerResponse,
                     .attestationVerificationFailed,
                     .outdatedClient,
                     .serverRateLimited,
                     .serializationError,
                     .missingModel,
                     .connectionFailure,
                     .timeout,
                     .invalidTransaction,
                     .inputsAlreadySpent,
                     .defragmentationFailed,
                     .invalidPassphrase,
                     .invalidEntropy,
                     .killSwitch,
                     .fogOutOfSync,
                     .outgoingVerificationTakingTooLong,
                     .missingMemo:
                    owsFailDebugUnlessMCNetworkFailure(error)
                case .authorizationFailure:
                    owsFailDebugUnlessMCNetworkFailure(error)
                case .verificationStatusUnknown,
                     .ledgerBlockTimestampUnknown:
                    // These errors are expected.
                    Logger.info("Error: \(error)")
                case .defragmentationRequired:
                    // These errors are expected but should be very rare.
                    owsFailDebugUnlessMCNetworkFailure(error)
                }
            default:
                owsFailDebugUnlessMCNetworkFailure(error)
            }

            guard let paymentModel = self.loadPaymentModelWithSneakyTransaction() else {
                owsFailDebug("Could not reload payment model.")
                self.delegate?.endProcessing(paymentId: self.paymentId)
                return Guarantee.value(())
            }
            self.handleProcessingError(paymentModel: paymentModel, error: error)
            return Guarantee.value(())
        }
    }

    private func handleProcessingError(paymentModel: TSPaymentModel, error: Error) {
        switch error {
        case let paymentsError as PaymentsError:
            switch paymentsError {
            case .notEnabled,
                 .userNotRegisteredOrAppNotReady,
                 .userHasNoPublicAddress,
                 .invalidCurrency,
                 .invalidWalletKey,
                 .invalidAmount,
                 .invalidFee,
                 .insufficientFunds,
                 .invalidModel,
                 .tooOldToSubmit,
                 .indeterminateState,
                 .unknownSDKError,
                 .invalidInput,
                 .authorizationFailure,
                 .invalidServerResponse,
                 .attestationVerificationFailed,
                 .outdatedClient,
                 .serializationError,
                 .missingModel,
                 .invalidTransaction,
                 .inputsAlreadySpent,
                 .defragmentationFailed,
                 .invalidPassphrase,
                 .invalidEntropy,
                 .killSwitch,
                 .outgoingVerificationTakingTooLong,
                 .missingMemo:
                // Do not retry these errors.
                delegate?.endProcessing(paymentId: self.paymentId)
            case .serverRateLimited:
                // Exponential backoff of at least 30 seconds.
                //
                // TODO: Revisit when FOG rate limiting behavior is well-defined.
                let retryDelayInteral = 30 + self.retryDelayInteral
                let nextRetryDelayInteral = self.retryDelayInteral * 2
                delegate?.scheduleRetryProcessing(paymentModel: paymentModel,
                                                  retryDelayInteral: retryDelayInteral,
                                                  nextRetryDelayInteral: nextRetryDelayInteral)
            case .connectionFailure,
                 .fogOutOfSync,
                 .timeout:
                // Vanilla exponential backoff.
                let retryDelayInteral = self.retryDelayInteral
                let nextRetryDelayInteral = self.retryDelayInteral * 2
                delegate?.scheduleRetryProcessing(paymentModel: paymentModel,
                                                  retryDelayInteral: retryDelayInteral,
                                                  nextRetryDelayInteral: nextRetryDelayInteral)
            case .verificationStatusUnknown,
                 .ledgerBlockTimestampUnknown:
                // Exponential backoff.
                //
                // If the payment _has_ already been verified, we're just trying to fill
                // in a missing ledger timestamp.  That is low priority and we can
                // backoff aggressively.
                //
                // If the payment _hasn't_  been verified yet, we want to retry fairly
                // aggressively.
                let backoffFactor: TimeInterval = paymentModel.isVerified ? 4 : 1.5
                var retryDelayInteral = self.retryDelayInteral
                if paymentModel.isVerified {
                    // Don't try to fill in a missing ledger timestamp more than once per hour.
                    // Things work reasonably well without this extra info, it's not clear
                    // how long a missing ledger timestamp might take to appear, and we might
                    // have a large number of payments without this info.
                    retryDelayInteral += kHourInterval * 1
                }
                let nextRetryDelayInteral = self.retryDelayInteral * backoffFactor
                delegate?.scheduleRetryProcessing(paymentModel: paymentModel,
                                                  retryDelayInteral: retryDelayInteral,
                                                  nextRetryDelayInteral: nextRetryDelayInteral)
            case .defragmentationRequired:
                // Vanilla exponential backoff.
                let retryDelayInteral = self.retryDelayInteral
                let nextRetryDelayInteral = self.retryDelayInteral * 2
                delegate?.scheduleRetryProcessing(paymentModel: paymentModel,
                                                  retryDelayInteral: retryDelayInteral,
                                                  nextRetryDelayInteral: nextRetryDelayInteral)
            }
        default:
            // Do not retry assertion errors.
            delegate?.endProcessing(paymentId: self.paymentId)
        }
    }

    private func loadPaymentModelWithSneakyTransaction() -> TSPaymentModel? {
        Self.databaseStorage.read { transaction in
            TSPaymentModel.anyFetch(uniqueId: self.paymentId, transaction: transaction)
        }
    }

    private static let timeoutDuration: TimeInterval = 60

    private func processStep(paymentModel: TSPaymentModel?) -> Promise<TSPaymentModel> {
        guard let paymentModel = paymentModel else {
            return Promise(error: OWSAssertionError("Could not reload the payment record."))
        }

        let paymentStateBeforeProcessing = paymentModel.paymentState

        return firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
            let formattedState = paymentModel.descriptionForLogs

            guard PaymentsProcessor.canBeProcessed(paymentModel: paymentModel) else {
                throw OWSAssertionError("Cannot process: \(formattedState)")
            }

            owsAssertDebug(paymentModel.isValid)

            let paymentId = paymentModel.uniqueId
            Logger.verbose("Trying to process: \(paymentId), \(formattedState)")

            switch paymentModel.paymentState {
            case .outgoingUnsubmitted:
                return self.submitOutgoingPayment(paymentModel: paymentModel)
            case .outgoingUnverified:
                return self.verifyOutgoingPayment(paymentModel: paymentModel)
            case .outgoingVerified:
                return self.sendPaymentNotificationMessage(paymentModel: paymentModel)
            case .outgoingSending,
                 .outgoingSent:
                return Self.updatePaymentStatePromise(paymentModel: paymentModel,
                                                      fromState: paymentModel.paymentState,
                                                      toState: .outgoingComplete)
            case .incomingUnverified:
                return self.verifyIncomingPayment(paymentModel: paymentModel)
            case .incomingVerified:
                return Self.updatePaymentStatePromise(paymentModel: paymentModel,
                                                      fromState: .incomingVerified,
                                                      toState: .incomingComplete)
            case .outgoingComplete,
                 .incomingComplete,
                 .outgoingFailed,
                 .incomingFailed:
                throw OWSAssertionError("Cannot process: \(formattedState)")
            @unknown default:
                throw OWSAssertionError("Unknown paymentState: \(formattedState)")
            }
        }.map {
            guard let latestModel = self.loadPaymentModelWithSneakyTransaction() else {
                owsFailDebug("Could not reload payment model.")
                throw PaymentsError.missingModel
            }

            let paymentStateAfterProcessing = latestModel.paymentState
            if paymentStateBeforeProcessing == paymentStateAfterProcessing {
                owsFailDebug("Payment state did not change after successful processing step: \(latestModel.descriptionForLogs)")
            }

            return latestModel
        }
    }

    private func submitOutgoingPayment(paymentModel: TSPaymentModel) -> Promise<Void> {
        owsAssertDebug(paymentModel.paymentState == .outgoingUnsubmitted)

        Logger.verbose("")

        guard !payments.isKillSwitchActive else {
            do {
                try Self.databaseStorage.write { transaction in
                    try paymentModel.updatePaymentModelState(fromState: .outgoingUnsubmitted,
                                                             toState: .outgoingUnverified,
                                                             transaction: transaction)
                }
            } catch {
                owsFailDebug("Error: \(error)")
            }
            return Promise(error: PaymentsError.killSwitch)
        }

        if DebugFlags.paymentsSkipSubmissionAndOutgoingVerification.get() {
            return Self.updatePaymentStatePromise(paymentModel: paymentModel,
                                                  fromState: .outgoingUnsubmitted,
                                                  toState: .outgoingUnverified)
        }

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
            Self.paymentsImpl.getMobileCoinAPI()
        }.then(on: DispatchQueue.global()) { (mobileCoinAPI: MobileCoinAPI) -> Promise<Void> in
            return mobileCoinAPI.submitTransaction(transaction: transaction)
        }.then(on: DispatchQueue.global()) { _ in
            Self.updatePaymentStatePromise(paymentModel: paymentModel,
                                           fromState: .outgoingUnsubmitted,
                                           toState: .outgoingUnverified)
        }.recover(on: DispatchQueue.global()) { (error: Error) -> Promise<Void> in
            if case PaymentsError.inputsAlreadySpent = error {
                // e.g. if we double-submit a transaction, it should become unverified,
                // not stuck in unsubmitted.
                return Self.updatePaymentStatePromise(paymentModel: paymentModel,
                                                      fromState: .outgoingUnsubmitted,
                                                      toState: .outgoingUnverified)
            } else {
                throw error
            }
        }
    }

    private func verifyOutgoingPayment(paymentModel: TSPaymentModel) -> Promise<Void> {
        owsAssertDebug(paymentModel.paymentState == .outgoingUnverified)

        Logger.verbose("")

        if DebugFlags.paymentsSkipSubmissionAndOutgoingVerification.get() {
            return firstly(on: DispatchQueue.global()) { () -> Void in
                try Self.databaseStorage.write { transaction in
                    guard let paymentModel = TSPaymentModel.anyFetch(uniqueId: paymentModel.uniqueId,
                                                                     transaction: transaction) else {
                        throw OWSAssertionError("Missing TSPaymentModel.")
                    }
                    paymentModel.update(mcLedgerBlockIndex: 111, transaction: transaction)
                    paymentModel.update(paymentState: .outgoingVerified, transaction: transaction)
                }
            }
        }

        return firstly { () -> Promise<MobileCoinAPI> in
            Self.paymentsImpl.getMobileCoinAPI()
        }.then(on: DispatchQueue.global()) { (mobileCoinAPI: MobileCoinAPI) -> Promise<Void> in
            firstly { () -> Promise<MCOutgoingTransactionStatus> in
                guard let mcTransactionData = paymentModel.mcTransactionData,
                      mcTransactionData.count > 0,
                      let transaction = MobileCoin.Transaction(serializedData: mcTransactionData) else {

                    Self.handleIndeterminatePayment(paymentModel: paymentModel)

                    throw PaymentsError.indeterminateState
                }

                return mobileCoinAPI.getOutgoingTransactionStatus(transaction: transaction)
            }.map { (transactionStatus: MCOutgoingTransactionStatus) in
                Logger.verbose("transactionStatus: \(transactionStatus)")

                try Self.databaseStorage.write { transaction in
                    switch transactionStatus.transactionStatus {
                    case .unknown:
                        throw PaymentsError.verificationStatusUnknown
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
                        Self.paymentsImpl.updateCurrentPaymentBalance()
                    case .failed:
                        Self.markAsFailed(paymentModel: paymentModel,
                                          paymentFailure: .validationFailed,
                                          paymentState: .outgoingFailed,
                                          transaction: transaction)
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

        return firstly(on: DispatchQueue.global()) { () -> Void in
            try Self.databaseStorage.write { transaction in
                guard let paymentModel = TSPaymentModel.anyFetch(uniqueId: paymentModel.uniqueId, transaction: transaction) else {
                    throw OWSAssertionError("Missing paymentModel.")
                }
                guard paymentModel.paymentState == .outgoingVerified else {
                    throw OWSAssertionError("Unexpected paymentState: \(paymentModel.descriptionForLogs).")
                }
                do {
                    let notify = {
                        if paymentModel.isDefragmentation {
                            PaymentsImpl.sendDefragmentationSyncMessage(paymentModel: paymentModel,
                                                                        transaction: transaction)
                        } else {
                            _ = try PaymentsImpl.sendPaymentNotificationMessage(paymentModel: paymentModel,
                                                                                transaction: transaction)
                            PaymentsImpl.sendOutgoingPaymentSyncMessage(paymentModel: paymentModel,
                                                                        transaction: transaction)
                        }
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
            Self.paymentsImpl.getMobileCoinAPI()
        }.then(on: DispatchQueue.global()) { (mobileCoinAPI: MobileCoinAPI) -> Promise<MCIncomingReceiptStatus> in

            guard let mcReceiptData = paymentModel.mcReceiptData,
                  let receipt = MobileCoin.Receipt(serializedData: mcReceiptData) else {

                Self.handleIndeterminatePayment(paymentModel: paymentModel)

                return Promise(error: PaymentsError.indeterminateState)
            }

            return mobileCoinAPI.getIncomingReceiptStatus(receipt: receipt)
        }.map { (receiptStatus: MCIncomingReceiptStatus) in
            Logger.verbose("receiptStatus: \(receiptStatus)")

            try Self.databaseStorage.write { transaction in
                switch receiptStatus.receiptStatus {
                case .unknown:
                    throw PaymentsError.verificationStatusUnknown
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
                    Self.paymentsImpl.updateCurrentPaymentBalance()
                case .failed:
                    Self.markAsFailed(paymentModel: paymentModel,
                                      paymentFailure: .validationFailed,
                                      paymentState: .incomingFailed,
                                      transaction: transaction)
                }
            }
        }
    }

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

    private static func updatePaymentStatePromise(paymentModel: TSPaymentModel,
                                                  fromState: TSPaymentState,
                                                  toState: TSPaymentState) -> Promise<Void> {
        owsAssertDebug(paymentModel.paymentState == fromState)

        return firstly(on: DispatchQueue.global()) { () -> Void in
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
}
