//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MobileCoin
public import SignalServiceKit

public class PaymentsProcessor: NSObject {

    private let appReadiness: AppReadiness

    public init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
        super.init()

        appReadiness.runNowOrWhenAppDidBecomeReadySync {
            DependenciesBridge.shared.databaseChangeObserver.appendDatabaseChangeDelegate(self)
        }
        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
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

    private let highPriorityProcessingQueue = SerialTaskQueue()
    private let defaultProcessingQueue = SerialTaskQueue()

    private func processingQueue(forPaymentModel paymentModel: TSPaymentModel) -> SerialTaskQueue {
        if paymentModel.isOutgoing, !paymentModel.isVerified {
            return highPriorityProcessingQueue
        } else {
            return defaultProcessingQueue
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
        DispatchQueue.global().async { [appReadiness] in
            guard !CurrentAppContext().isRunningTests else {
                return
            }
            guard SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled else {
                return
            }
            guard
                appReadiness.isAppReady,
                CurrentAppContext().isMainAppAndActive,
                DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
            else {
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
        var paymentModels: [TSPaymentModel] = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            PaymentFinder.paymentModels(paymentStates: Array(Self.paymentStatesToProcess),
                                        transaction: transaction)
        }

        paymentModels.sort { (left, right) -> Bool in
            left.sortDate.compare(right.sortDate) == .orderedAscending
        }

        // Create a new operation for any payment that needs to be
        // processed that we're not already processing.
        let delegate: PaymentProcessingOperationDelegate = self
        Self.unfairLock.withLock { [paymentModels] in
            for paymentModel in paymentModels {
                let paymentId = paymentModel.uniqueId
                // Don't add an operation if we're already processing this payment model.
                guard !self.processingPaymentIds.contains(paymentId) else {
                    continue
                }
                self.processingPaymentIds.insert(paymentId)
                let operation = PaymentProcessingOperation(delegate: delegate, paymentModel: paymentModel)
                processingQueue(forPaymentModel: paymentModel).enqueue { await operation.run() }
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
    fileprivate class RetryScheduler: NSObject {

        private let paymentModel: TSPaymentModel
        private let nextRetryDelayInteral: TimeInterval
        private weak var delegate: PaymentProcessingOperationDelegate?
        private let hasScheduled = AtomicBool(false, lock: .sharedGlobal)
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

            guard SSKEnvironment.shared.reachabilityManagerRef.isReachable else {
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
        owsAssertDebug(appReadiness.isAppReady)

        guard databaseChanges.didUpdate(tableName: TSPaymentModel.table.tableName) else {
            return
        }

        process()
    }

    public func databaseChangesDidUpdateExternally() {
        owsAssertDebug(appReadiness.isAppReady)

        process()
    }

    public func databaseChangesDidReset() {
        owsAssertDebug(appReadiness.isAppReady)

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

        let operation = PaymentProcessingOperation(delegate: self, paymentModel: paymentModel, retryDelayInteral: retryDelayInteral)
        processingQueue(forPaymentModel: paymentModel).enqueue { await operation.run() }
    }

    func scheduleRetryProcessing(
        paymentModel: TSPaymentModel,
        retryDelayInteral: TimeInterval,
        nextRetryDelayInteral: TimeInterval
    ) {
        add(retryScheduler: RetryScheduler(
            paymentModel: paymentModel,
            retryDelayInteral: retryDelayInteral,
            nextRetryDelayInteral: nextRetryDelayInteral,
            delegate: self
        ))
    }

    func endProcessing(paymentModel: TSPaymentModel) {
        endProcessing(paymentId: paymentModel.uniqueId)
    }

    func endProcessing(paymentId: String) {
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
private class PaymentProcessingOperation {
    private weak var delegate: PaymentProcessingOperationDelegate?
    private let paymentId: String
    private let retryDelayInteral: TimeInterval

    private static let defaultRetryDelayInteral: TimeInterval = .second

    init(delegate: PaymentProcessingOperationDelegate,
         paymentModel: TSPaymentModel,
         retryDelayInteral: TimeInterval? = nil) {
        self.delegate = delegate
        self.paymentId = paymentModel.uniqueId
        self.retryDelayInteral = retryDelayInteral ?? Self.defaultRetryDelayInteral
    }

    func run() async {
        await processStep()
    }

    // Try to usher a payment "one step forward" in the processing
    // state machine.
    //
    // We need to user transactions/payments through the various
    // steps of the state machine as quickly as possible, retry when
    // necessary, and avoid getting stuck in a tight retry loop.
    // Therefore retries are throttled and/or do backoff - but retry
    // behavior depends on the type of operation.
    private func processStep() async {
        // When this promise chain completes, we must call continueProcessing()
        // or endProcessing().
        do {
            let paymentModel = try await Promise.wrapAsync {
                return try await self.processStep(paymentModel: self.loadPaymentModelWithSneakyTransaction())
            }.timeout(seconds: Self.timeoutDuration, description: "process") { () -> Error in
                return PaymentsError.timeout
            }.awaitable()
            self.delegate?.continueProcessing(paymentModel: paymentModel)
        } catch {
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

            if let paymentModel = self.loadPaymentModelWithSneakyTransaction() {
                self.handleProcessingError(paymentModel: paymentModel, error: error)
            } else {
                owsFailDebug("Could not reload payment model.")
                self.delegate?.endProcessing(paymentId: self.paymentId)
            }
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
                    retryDelayInteral += .hour
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
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            TSPaymentModel.anyFetch(uniqueId: self.paymentId, transaction: transaction)
        }
    }

    private static let timeoutDuration: TimeInterval = 60

    private func processStep(paymentModel: TSPaymentModel?) async throws -> TSPaymentModel {
        guard let paymentModel = paymentModel else {
            throw OWSAssertionError("Could not reload the payment record.")
        }

        let paymentStateBeforeProcessing = paymentModel.paymentState

        let formattedState = paymentModel.descriptionForLogs

        guard PaymentsProcessor.canBeProcessed(paymentModel: paymentModel) else {
            throw OWSAssertionError("Cannot process: \(formattedState)")
        }

        owsAssertDebug(paymentModel.isValid)

        switch paymentModel.paymentState {
        case .outgoingUnsubmitted:
            try await self.submitOutgoingPayment(paymentModel: paymentModel)
        case .outgoingUnverified:
            try await self.verifyOutgoingPayment(paymentModel: paymentModel)
        case .outgoingVerified:
            try await self.sendPaymentNotificationMessage(paymentModel: paymentModel)
        case .outgoingSending, .outgoingSent:
            try await Self.updatePaymentStatePromise(paymentModel: paymentModel, fromState: paymentModel.paymentState, toState: .outgoingComplete)
        case .incomingUnverified:
            try await self.verifyIncomingPayment(paymentModel: paymentModel)
        case .incomingVerified:
            try await Self.updatePaymentStatePromise(paymentModel: paymentModel, fromState: .incomingVerified, toState: .incomingComplete)
        case .outgoingComplete, .incomingComplete, .outgoingFailed, .incomingFailed:
            throw OWSAssertionError("Cannot process: \(formattedState)")
        @unknown default:
            throw OWSAssertionError("Unknown paymentState: \(formattedState)")
        }

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

    private func submitOutgoingPayment(paymentModel: TSPaymentModel) async throws {
        owsAssertDebug(paymentModel.paymentState == .outgoingUnsubmitted)

        if SUIEnvironment.shared.paymentsRef.isKillSwitchActive {
            do {
                try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                    try paymentModel.updatePaymentModelState(fromState: .outgoingUnsubmitted, toState: .outgoingUnverified, transaction: transaction)
                }
            } catch {
                owsFailDebug("Error: \(error)")
            }
            throw PaymentsError.killSwitch
        }

        if DebugFlags.paymentsSkipSubmissionAndOutgoingVerification.get() {
            try await Self.updatePaymentStatePromise(paymentModel: paymentModel, fromState: .outgoingUnsubmitted, toState: .outgoingUnverified)
            return
        }

        // Only try to submit transactions within the first N minutes of them
        // being initiated.  If the app is terminated right after a transaction
        // is initiated (before transaction it can be submitted), we don't want
        // to submit it if the app is opened much later.
        let submissionInterval: TimeInterval = .minute * 5
        let createdDate = paymentModel.createdDate
        let isRecentEnoughToSubmit = abs(createdDate.timeIntervalSinceNow) <= submissionInterval

        guard isRecentEnoughToSubmit else {
            // We mark the payment as "unverified", not "failed". It's conceivable
            // that the transaction was submitted but the record was never marked
            // as such (due to a race around app being terminated).
            do {
                try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                    try paymentModel.updatePaymentModelState(fromState: .outgoingUnsubmitted, toState: .outgoingUnverified, transaction: transaction)
                }
            } catch {
                owsFailDebug("Error: \(error)")
            }
            Logger.warn("Not recent enough to submit.")
            throw PaymentsError.tooOldToSubmit
        }

        guard
            let mcTransactionData = paymentModel.mcTransactionData,
            mcTransactionData.count > 0,
            let transaction = MobileCoin.Transaction(serializedData: mcTransactionData)
        else {
            await Self.handleIndeterminatePayment(paymentModel: paymentModel)
            throw PaymentsError.indeterminateState
        }

        do {
            let mobileCoinAPI = try await SUIEnvironment.shared.paymentsImplRef.getMobileCoinAPI()
            _ = try await mobileCoinAPI.submitTransaction(transaction: transaction)
            try await Self.updatePaymentStatePromise(paymentModel: paymentModel, fromState: .outgoingUnsubmitted, toState: .outgoingUnverified)
        } catch PaymentsError.inputsAlreadySpent {
            // e.g. if we double-submit a transaction, it should become unverified,
            // not stuck in unsubmitted.
            try await Self.updatePaymentStatePromise(paymentModel: paymentModel, fromState: .outgoingUnsubmitted, toState: .outgoingUnverified)
        }
    }

    private func verifyOutgoingPayment(paymentModel: TSPaymentModel) async throws {
        owsAssertDebug(paymentModel.paymentState == .outgoingUnverified)

        if DebugFlags.paymentsSkipSubmissionAndOutgoingVerification.get() {
            try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                guard let paymentModel = TSPaymentModel.anyFetch(uniqueId: paymentModel.uniqueId, transaction: transaction) else {
                    throw OWSAssertionError("Missing TSPaymentModel.")
                }
                paymentModel.update(mcLedgerBlockIndex: 111, transaction: transaction)
                paymentModel.update(paymentState: .outgoingVerified, transaction: transaction)
            }
            return
        }

        let mobileCoinAPI = try await SUIEnvironment.shared.paymentsImplRef.getMobileCoinAPI()

        guard
            let mcTransactionData = paymentModel.mcTransactionData,
            mcTransactionData.count > 0,
            let transaction = MobileCoin.Transaction(serializedData: mcTransactionData)
        else {
            await Self.handleIndeterminatePayment(paymentModel: paymentModel)
            throw PaymentsError.indeterminateState
        }

        let transactionStatus = try await mobileCoinAPI.getOutgoingTransactionStatus(transaction: transaction)

        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            switch transactionStatus.transactionStatus {
            case .unknown:
                throw PaymentsError.verificationStatusUnknown
            case .accepted(let block):
                if !paymentModel.hasMCLedgerBlockIndex {
                    paymentModel.update(mcLedgerBlockIndex: block.index, transaction: transaction)
                }
                if let ledgerBlockDate = block.timestamp,
                   !paymentModel.hasMCLedgerBlockTimestamp {
                    paymentModel.update(mcLedgerBlockTimestamp: ledgerBlockDate.ows_millisecondsSince1970, transaction: transaction)
                }
                try paymentModel.updatePaymentModelState(fromState: .outgoingUnverified, toState: .outgoingVerified, transaction: transaction)

                // If we've verified a payment, our balance may have changed.
                SUIEnvironment.shared.paymentsImplRef.updateCurrentPaymentBalance()
            case .failed:
                Self.markAsFailed(paymentModel: paymentModel, paymentFailure: .validationFailed, paymentState: .outgoingFailed, transaction: transaction)
            }
        }
    }

    private class func markAsFailed(paymentModel: TSPaymentModel, paymentFailure: TSPaymentFailure, paymentState: TSPaymentState) async {
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            markAsFailed(paymentModel: paymentModel, paymentFailure: paymentFailure, paymentState: paymentState, transaction: transaction)
        }
    }

    private class func markAsFailed(paymentModel: TSPaymentModel, paymentFailure: TSPaymentFailure, paymentState: TSPaymentState, transaction: DBWriteTransaction) {
        paymentModel.update(withPaymentFailure: paymentFailure, paymentState: paymentState, transaction: transaction)
    }

    private func sendPaymentNotificationMessage(paymentModel: TSPaymentModel) async throws {
        owsAssertDebug(paymentModel.paymentState == .outgoingVerified)

        guard !paymentModel.isOutgoingTransfer else {
            // No need to notify for "transfer out" transactions.
            try await Self.updatePaymentStatePromise(paymentModel: paymentModel, fromState: .outgoingVerified, toState: .outgoingSent)
            return
        }

        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            guard let paymentModel = TSPaymentModel.anyFetch(uniqueId: paymentModel.uniqueId, transaction: transaction) else {
                throw OWSAssertionError("Missing paymentModel.")
            }
            guard paymentModel.paymentState == .outgoingVerified else {
                throw OWSAssertionError("Unexpected paymentState: \(paymentModel.descriptionForLogs).")
            }
            do {
                let notify = {
                    if paymentModel.isDefragmentation {
                        PaymentsImpl.sendDefragmentationSyncMessage(paymentModel: paymentModel, transaction: transaction)
                    } else {
                        _ = try PaymentsImpl.sendPaymentNotificationMessage(paymentModel: paymentModel, transaction: transaction)
                        PaymentsImpl.sendOutgoingPaymentSyncMessage(paymentModel: paymentModel, transaction: transaction)
                    }
                }

                try notify()

                if DebugFlags.paymentsDoubleNotify.get() {
                    // Notify again.
                    try notify()
                }

                try paymentModel.updatePaymentModelState(fromState: .outgoingVerified, toState: .outgoingSending, transaction: transaction)
            } catch {
                if case PaymentsError.invalidModel = error {
                    try paymentModel.updatePaymentModelState(fromState: .outgoingVerified, toState: .outgoingComplete, transaction: transaction)
                }
                throw error
            }
        }
    }

    private func verifyIncomingPayment(paymentModel: TSPaymentModel) async throws {
        owsAssertDebug(paymentModel.paymentState == .incomingUnverified)

        let mobileCoinAPI = try await SUIEnvironment.shared.paymentsImplRef.getMobileCoinAPI()

        guard let mcReceiptData = paymentModel.mcReceiptData, let receipt = MobileCoin.Receipt(serializedData: mcReceiptData) else {
            await Self.handleIndeterminatePayment(paymentModel: paymentModel)
            throw PaymentsError.indeterminateState
        }

        let receiptStatus = try await mobileCoinAPI.getIncomingReceiptStatus(receipt: receipt).awaitable()

        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            switch receiptStatus.receiptStatus {
            case .unknown:
                throw PaymentsError.verificationStatusUnknown
            case .received(let block):
                paymentModel.update(mcLedgerBlockIndex: block.index, transaction: transaction)
                if let ledgerBlockDate = block.timestamp {
                    paymentModel.update(mcLedgerBlockTimestamp: ledgerBlockDate.ows_millisecondsSince1970, transaction: transaction)
                } else {
                    Logger.warn("Missing ledgerBlockDate.")
                }
                paymentModel.update(withPaymentAmount: receiptStatus.paymentAmount, transaction: transaction)
                try paymentModel.updatePaymentModelState(fromState: .incomingUnverified, toState: .incomingVerified, transaction: transaction)

                // If we've verified a payment, our balance may have changed.
                SUIEnvironment.shared.paymentsImplRef.updateCurrentPaymentBalance()
            case .failed:
                Self.markAsFailed(paymentModel: paymentModel, paymentFailure: .validationFailed, paymentState: .incomingFailed, transaction: transaction)
            }
        }
    }

    class func handleIndeterminatePayment(paymentModel: TSPaymentModel) async {
        owsFailDebug("Indeterminate payment: \(paymentModel.descriptionForLogs)")

        // A payment is indeterminate if we don't know if it exists
        // in the ledger and have no way to resolve that.  For example,
        // a user might submit a payment, then scrub the payment before
        // it is verified.  In this case, the only way to recover is
        // to discard the payment record and reconcile using the transaction
        // history.  Presumably this should only be possible if the user
        // scrubs an unverified payment.

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            paymentModel.anyRemove(transaction: transaction)

            SUIEnvironment.shared.paymentsRef.scheduleReconciliationNow(transaction: transaction)
        }
    }

    private static func updatePaymentStatePromise(paymentModel: TSPaymentModel, fromState: TSPaymentState, toState: TSPaymentState) async throws {
        owsAssertDebug(paymentModel.paymentState == fromState)

        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            guard let paymentModel = TSPaymentModel.anyFetch(uniqueId: paymentModel.uniqueId, transaction: transaction) else {
                throw OWSAssertionError("Missing TSPaymentModel.")
            }
            guard paymentModel.paymentState == fromState else {
                throw OWSAssertionError("Unexpected paymentState: \(paymentModel.paymentState.formatted) != \(fromState.formatted).")
            }
            paymentModel.update(paymentState: toState, transaction: transaction)
        }
    }
}
