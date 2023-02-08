//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MobileCoin
import SignalMessaging

public class PaymentsReconciliation: Dependencies {

    private var refreshEvent: RefreshEvent?

    public required init() {
        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            // Note: this isn't how often we perform reconciliation, it's how often we
            // check whether we should perform reconciliation.
            //
            // TODO: Tune.
            let refreshCheckInterval = kMinuteInterval * 5
            self.refreshEvent = RefreshEvent(refreshInterval: refreshCheckInterval) { [weak self] in
                self?.reconcileIfNecessary()
            }
        }
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reconcileIfNecessary),
                                               name: PaymentsConstants.arePaymentsEnabledDidChange,
                                               object: nil)
    }

    @objc
    private func reconcileIfNecessary() {
        if CurrentAppContext().isNSE {
            return
        }
        operationQueue.addOperation(PaymentsReconciliationOperation())
    }

    let operationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "PaymentsReconciliation"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    public class PaymentsReconciliationOperation: OWSOperation {
        override public func run() {
            firstly(on: DispatchQueue.global()) {
                PaymentsReconciliation.reconciliationPromise()
            }.done(on: DispatchQueue.global()) { _ in
                self.reportSuccess()
            }.catch(on: DispatchQueue.global()) { error in
                owsFailDebugUnlessMCNetworkFailure(error)
                let error = SSKUnretryableError.paymentsReconciliationFailure
                self.reportError(error)
            }
        }
    }

    private static var shouldReconcile: Bool {
        guard !CurrentAppContext().isRunningTests else {
            return false
        }
        guard Self.paymentsHelper.arePaymentsEnabled else {
            return false
        }
        guard AppReadiness.isAppReady,
              CurrentAppContext().isMainAppAndActive,
              Self.tsAccountManager.isRegisteredAndReady else {
            return false
        }
        guard shouldReconcileByDateWithSneakyTransaction() else {
            return false
        }
        return true
    }

    private static func reconciliationPromise() -> Promise<Void> {
        owsAssertDebug(!Thread.isMainThread)

        guard shouldReconcile else {
            return Promise.value(())
        }
        return firstly { () -> Promise<MobileCoinAPI> in
            Self.paymentsImpl.getMobileCoinAPI()
        }.then(on: DispatchQueue.global()) { (mobileCoinAPI: MobileCoinAPI) -> Promise<MobileCoin.AccountActivity> in
            mobileCoinAPI.getAccountActivity()
        }.map(on: DispatchQueue.global()) { (accountActivity: MobileCoin.AccountActivity) -> Void in
            Self.reconcileIfNecessary(transactionHistory: accountActivity)
        }
    }

    private static let schedulingStore = SDSKeyValueStore(collection: "PaymentsReconciliation.schedulingStore")
    private static let successDateKey = "successDateKey"
    private static let lastKnownBlockCountKey = "lastKnownBlockCountKey"
    private static let lastKnownReceivedTXOCountKey = "lastKnownReceivedTXOCountKey"
    private static let lastKnownSpentTXOCountKey = "lastKnownSpentTXOCountKey"

    private static func shouldReconcileByDateWithSneakyTransaction() -> Bool {
        Self.databaseStorage.read { transaction in
            Self.shouldReconcileByDate(transaction: transaction)
        }
    }

    private static func shouldReconcileByDate(transaction: SDSAnyReadTransaction) -> Bool {
        guard let date = Self.schedulingStore.getDate(Self.successDateKey, transaction: transaction) else {
            return true
        }
        let reconciliationInterval = kHourInterval * 1
        return abs(date.timeIntervalSinceNow) >= reconciliationInterval
    }

    private static func shouldReconcileWithSneakyTransaction(transactionHistory: MCTransactionHistory) -> Bool {
        Self.databaseStorage.read { transaction in
            Self.shouldReconcile(transaction: transaction,
                                 transactionHistory: transactionHistory)
        }
    }

    private static func shouldReconcile(transaction: SDSAnyReadTransaction,
                                        transactionHistory: MCTransactionHistory) -> Bool {

        // Ledger state monotonically increases, so its sufficient
        // to do change detection by comparing these values.
        let lastKnownBlockCount = transactionHistory.blockCount
        let spentTXOCount = transactionHistory.spentItems.count
        let receivedTXOCount = transactionHistory.receivedItems.count

        guard lastKnownBlockCount == Self.schedulingStore.getUInt64(Self.lastKnownBlockCountKey,
                                                                    defaultValue: 0,
                                                                    transaction: transaction) else {
            return true
        }
        guard spentTXOCount == Self.schedulingStore.getUInt(Self.lastKnownSpentTXOCountKey,
                                                            defaultValue: 0,
                                                            transaction: transaction) else {
            return true
        }
        guard receivedTXOCount == Self.schedulingStore.getUInt(Self.lastKnownReceivedTXOCountKey,
                                                               defaultValue: 0,
                                                               transaction: transaction) else {
            return true
        }
        return false
    }

    private static func reconciliationDidSucceed(transaction: SDSAnyWriteTransaction,
                                                 transactionHistory: MCTransactionHistory) {
        // TODO: Until reconciliation testing is complete, don't mark reconciliation as complete.
        #if TESTABLE_BUILD
        #else
        Self.schedulingStore.setDate(Date(), key: Self.successDateKey, transaction: transaction)

        let lastKnownBlockCount = transactionHistory.blockCount
        let spentItemsCount = transactionHistory.spentItems.count
        let receivedItemsCount = transactionHistory.receivedItems.count

        Self.schedulingStore.setUInt64(lastKnownBlockCount,
                                       key: Self.lastKnownBlockCountKey,
                                       transaction: transaction)
        Self.schedulingStore.setInt(spentItemsCount,
                                    key: Self.lastKnownSpentTXOCountKey,
                                    transaction: transaction)
        Self.schedulingStore.setInt(receivedItemsCount,
                                    key: Self.lastKnownReceivedTXOCountKey,
                                    transaction: transaction)
        #endif
    }

    public func scheduleReconciliationNow(transaction: SDSAnyWriteTransaction) {
        Self.schedulingStore.removeAll(transaction: transaction)

        transaction.addAsyncCompletionOffMain {
            self.reconcileIfNecessary()
        }
    }

    enum ReconciliationError: Error {
        case unsavedChanges
    }

    private static func reconcileIfNecessary(transactionHistory: MCTransactionHistory) {

        // We should skip reconciliation if accountActivity hasn't changed
        // since the last reconciliation.
        guard shouldReconcileWithSneakyTransaction(transactionHistory: transactionHistory) else {
            return
        }

        // Reconciliation is expensive. We need to load into memory our entire transaction
        // history from the SDK (MobileCoin.AccountActivity) and our payment history from
        // the database (PaymentsDatabaseState) and reconcile them which involves a bunch of
        // computation and some queries.  We need to be able to safely perform reconciliation
        // often, even if a user has an extensive transaction history.
        //
        // For consistency, all db reads & writes must be done within a single write
        // transaction so the risk is of a long-running write transaction.
        //
        // Therefore we perform the reconciliation in a read transaction.  If any db writes
        // are necessary, we throw ReconciliationError.unsavedChanges. We then re-perform
        // reconciliation with a write transaction.  Most reconciliations don't need to
        // perform any db writes, so in this way we can avoid write transactions unless
        // necessary.
        do {
            try databaseStorage.read { transaction in
                let databaseState = Self.buildPaymentsDatabaseState(transaction: transaction)

                try reconcile(transactionHistory: transactionHistory,
                              databaseState: databaseState,
                              transaction: transaction)

                try cleanUpDatabase(transaction: transaction)
            }
            databaseStorage.write { transaction in
                reconciliationDidSucceed(transaction: transaction,
                                         transactionHistory: transactionHistory)
            }
        } catch {
            if case ReconciliationError.unsavedChanges = error {
                Logger.info("Reconciliation has unsaved changes.")

                do {
                    try databaseStorage.write { transaction in
                        let databaseState = Self.buildPaymentsDatabaseState(transaction: transaction)

                        try reconcile(transactionHistory: transactionHistory,
                                      databaseState: databaseState,
                                      transaction: transaction)

                        try cleanUpDatabase(transaction: transaction)

                        reconciliationDidSucceed(transaction: transaction,
                                                 transactionHistory: transactionHistory)
                    }
                } catch {
                    owsFailDebug("Error: \(error)")
                }
            } else {
                owsFailDebug("Error: \(error)")
            }
        }
    }

    // This method performs the core of the reconciliation.
    //
    // We review the MobileCoin.AccountActivity and identify any
    // "unaccounted-for" MC TXOs from the SDK transaction which don't
    // correspond to a TSPaymentModel in the database. We account for
    // them by creating "unidentified" TSPaymentModels.
    //
    // For a given block we want to track the following:
    //
    // * Received TXOs (public keys)
    //   * SDK transaction history contains this.
    // * Spent TXOs (public keys)
    //   * SDK transaction history contains this.
    // * Spent TXOs (key images)
    //   * MC Transaction model entity contains this; SDK transaction history does not.
    // * Output TXOs (public keys)
    //   * MC Transaction model has all of these for identified payments.
    //   * MC Receipt model has the public key for the recipient TXO, but not any change TXOs.
    //
    // Identifying a change TXO if you have Receipt/Transaction models for this block:
    //
    // * Will be in output TXO list and received TXOs list.
    // * Those TXOs will match value and TXO public key.
    // * Will not match the Receipt recipient TXO public key.
    //
    // Identifying a change TXO without (or partial) Receipt/Transaction models for this block:
    //
    // * There will be received and outgoing (NOT spent) TXOs match in value.
    // * Sum of values of total change TXOs will be less than sum of values of total spent TXIs.
    //
    // * Multiple "unaccounted for" incoming TXOs in a block should be rare.
    // * Multiple "unaccounted for" outgoing TXOs in a block should be very rare.
    // * Well-behaved payments should only have 1-2 outgoing TXOs (change is optional).
    // * But we can't meaningfully group "unaccounted for" outgoing TXOs, so
    //   group all "unaccounted for" outgoing TXOs into a single payment.
    //
    // NOTE: There's no reliable way to identify defrag transactions.
    internal static func reconcile(transactionHistory: MCTransactionHistory,
                                   databaseState: PaymentsDatabaseState,
                                   transaction: SDSAnyReadTransaction) throws {

        Logger.info("")

        // Fill in/reconcile incoming transactions.
        Logger.verbose("transactionHistory: \(transactionHistory.blockCount)")
        Logger.verbose("items: \(transactionHistory.safeItems.count) / \(transactionHistory.items.count)")

        let items: [MCTransactionHistoryItem] = transactionHistory.safeItems.sortedByBlockIndex(descending: false)

        // 1. Collate transactions by block: Block Activity
        var blockActivityMap = [UInt64: BlockActivity]()
        func blockActivity(forBlockIndex blockIndex: UInt64) -> BlockActivity {
            let blockActivity = blockActivityMap[blockIndex] ?? BlockActivity(blockIndex: blockIndex)
            blockActivityMap[blockIndex] = blockActivity
            return blockActivity
        }
        for item in items {
            // Incoming
            blockActivity(forBlockIndex: item.receivedBlockIndex).addReceived(item: item)

            // Outgoing
            if let spentBlock = item.spentBlock {
                blockActivity(forBlockIndex: spentBlock.index).addSpent(item: item)
            }
        }
        let blockActivities = Array(blockActivityMap.values).sortedByBlockIndex(descending: false)

        // 2. Fill in missing unidentified transactions.
        //
        // We account for all unidentified transactions with a single payment model.
        // This might "lump together" incoming (received) and outgoing (spent)
        // transactions into a single "omnibus" payment model.
        //
        // It's definitely possible for a user to receive multiple incoming
        // payments in a given ledger block.
        //
        // Hypothetically the local user might also have more than one outgoing
        // transaction in a given block.  Well-behaved clients should prevent
        // this, but a user might send two payments from linked devices at
        // the same time.
        //
        // There's no reliable way to separate this activity into multiple
        // "unidentified payments", so we just create one "omnibus
        // unidentified" payment model.
        //
        // Because we're making an "omnibus" payment, we _CANNOT_ assume that
        // MC transaction limitations apply:
        //
        // * max 16 TXIs
        // * max 16 TXOs
        // * usually 1-2 TXOs (one for recipient, one for change)
        // * max 1 change TXO?
        //
        // If we later learn of identified activity in that block (via sync
        // message), we'll recover by discarding all "unidentified" payments
        // in the block and re-reconcile.
        for blockActivity in blockActivities {
            // For each ledger block, we first try to identify any blocks with
            // any outgoing/spent TXOs which are not already "accounted for".
            //
            // * A received TXO has been spent if the SDK transaction history
            //   includes a "spent block."
            // * A spent TXO is unaccounted for if you don't yet have an
            //   outgoing TSPaymentModel without that TXO's keyImage in its
            //   mcSpentKeyImages.
            var unaccountedForSpentItems = [MCTransactionHistoryItem]()
            for spentItem in blockActivity.spentItems {
                let isAccountedFor = databaseState.spentImageKeyMap[spentItem.keyImage] != nil
                if !isAccountedFor {
                    unaccountedForSpentItems.append(spentItem)
                }
            }

            var unaccountedForReceivedItems = [MCTransactionHistoryItem]()
            for receivedItem in blockActivity.receivedItems {
                let existingReceivingPaymentModels = databaseState.incomingAnyMap.values(forKey: receivedItem.txoPublicKey)
                owsAssertDebug(existingReceivingPaymentModels.filter { $0.isFailed }.isEmpty)
                let isAccountedFor = !existingReceivingPaymentModels.isEmpty
                let isPossibleChange = databaseState.outputPublicKeyMap[receivedItem.txoPublicKey] != nil
                if !isAccountedFor, !isPossibleChange {
                    unaccountedForReceivedItems.append(receivedItem)
                }
            }

            guard !unaccountedForSpentItems.isEmpty || !unaccountedForReceivedItems.isEmpty else {
                continue
            }

            let spentPicoMob = unaccountedForSpentItems.map { $0.amountPicoMob }.reduce(0, +)
            let receivedPicoMob = unaccountedForReceivedItems.map { $0.amountPicoMob }.reduce(0, +)

            // If the net MOB received > spent, the "omnibus" payment is an
            // "unidentified incoming" payment; otherwise it is "unidentified
            // outgoing."
            //
            let isOutgoing = spentPicoMob > receivedPicoMob

            let netPicoMob: UInt64
            if isOutgoing {
                netPicoMob = spentPicoMob - receivedPicoMob
            } else {
                netPicoMob = receivedPicoMob - spentPicoMob
            }
            let paymentAmount = TSPaymentAmount(currency: .mobileCoin,
                                                picoMob: netPicoMob)
            let paymentType: TSPaymentType = (isOutgoing ? .outgoingUnidentified : .incomingUnidentified)
            let paymentState: TSPaymentState = (isOutgoing ? .outgoingComplete : .incomingComplete)

            let ledgerBlockIndex: UInt64 = blockActivity.blockIndex
            let ledgerBlockTimestamp: UInt64 = blockActivity.blockTimestamp ?? 0
            let createdTimestamp: UInt64 = Self.guesstimateBlockTimestamp(forBlockActivity: blockActivity,
                                                                          allBlockActivities: blockActivities)
            let createdDate = NSDate.ows_date(withMillisecondsSince1970: createdTimestamp)

            let unaccountedForSpentKeyImages: [Data] = unaccountedForSpentItems.map { $0.keyImage }
            let spentKeyImages: [Data]? = Array(Set(unaccountedForSpentKeyImages)).nilIfEmpty
            let incomingTransactionPublicKeys: [Data]? = unaccountedForReceivedItems.map { $0.txoPublicKey }.nilIfEmpty

            let mobileCoin = MobileCoinPayment(recipientPublicAddressData: nil,
                                               transactionData: nil,
                                               receiptData: nil,
                                               incomingTransactionPublicKeys: incomingTransactionPublicKeys,
                                               spentKeyImages: spentKeyImages,
                                               outputPublicKeys: nil,
                                               ledgerBlockTimestamp: ledgerBlockTimestamp,
                                               ledgerBlockIndex: ledgerBlockIndex,
                                               feeAmount: nil)
            let paymentModel = TSPaymentModel(paymentType: paymentType,
                                              paymentState: paymentState,
                                              paymentAmount: paymentAmount,
                                              createdDate: createdDate,
                                              addressUuidString: nil,
                                              memoMessage: nil,
                                              requestUuidString: nil,
                                              isUnread: true,
                                              mobileCoin: mobileCoin)

            if let transaction = transaction as? SDSAnyWriteTransaction {
                try Self.paymentsHelper.tryToInsertPaymentModel(paymentModel, transaction: transaction)
            } else {
                throw ReconciliationError.unsavedChanges
            }

            databaseState.add(paymentModel: paymentModel)
        }

        // 3. Fill in missing ledger timestamps.
        for blockActivity in blockActivities {
            // If we know the ledger block timestamp for a given block...
            guard let ledgerBlockTimestamp = blockActivity.blockTimestamp else {
                continue
            }
            let ledgerBlockIndex = blockActivity.blockIndex

            // Review all existing payment models in the block and fill in
            // any missing ledger block timestamps.
            let paymentModels = databaseState.ledgerBlockIndexMap[ledgerBlockIndex]
            for paymentModel in paymentModels {
                let hasLedgerBlockIndex = (paymentModel.mobileCoin?.ledgerBlockIndex ?? 0) > 0
                if !hasLedgerBlockIndex {
                    if let transaction = transaction as? SDSAnyWriteTransaction {
                        paymentModel.update(mcLedgerBlockTimestamp: ledgerBlockTimestamp,
                                            transaction: transaction)
                    } else {
                        throw ReconciliationError.unsavedChanges
                    }
                }
            }
        }
    }

    // When creating "unidentified" payments, the ledger block timestamp
    // might not always be available.  In these cases, its important to
    // make a "best guess" about when the transaction occurred in order to:
    //
    // * Ensure correct ordering of the transactions.
    // * Display the "best guess" of when transaction occurred in the UI.
    private static func guesstimateBlockTimestamp(forBlockActivity blockActivity: BlockActivity,
                                                  allBlockActivities: [BlockActivity]) -> UInt64 {
        // A given block has a single timestamp, so we can
        // consult all TXOs sent or received in the same block
        // to find a timestamp.
        if let timestamp = blockActivity.blockTimestamp {
            return timestamp
        }

        // This should be very rare, and we can fill in the correct
        // value later.
        Logger.warn("Unknown ledgerBlockTimestamp.")

        // If we don't have a value from FOG, we can make a best guess that
        // at least ensures the correct ordering by examining other known blocks
        // in the ledger.  Any blocks with a higher block index should have a
        // higher timestamp.
        let blockIndex = blockActivity.blockIndex
        var timestampUpperBound = Date().ows_millisecondsSince1970

        for otherBlockActivity in allBlockActivities {
            if otherBlockActivity.blockIndex > blockIndex,
               let timestamp = otherBlockActivity.blockTimestamp {
                timestampUpperBound = min(timestampUpperBound, timestamp)
            }
        }
        return timestampUpperBound - 1
    }

    private static func cleanUpDatabase(transaction: SDSAnyReadTransaction) throws {
        try cleanUpDatabaseMobileCoin(transaction: transaction)
    }

    private static func cleanUpDatabaseMobileCoin(transaction: SDSAnyReadTransaction) throws {

        var unidentifiedPaymentModelsToCull = [String: TSPaymentModel]()

        func cullPaymentModelsIfUnidentified(_ paymentModels: [TSPaymentModel]) -> UInt {
            var cullCount: UInt = 0
            for paymentModel in paymentModels {
                guard paymentModel.isUnidentified else {
                    continue
                }
                guard nil == unidentifiedPaymentModelsToCull[paymentModel.uniqueId] else {
                    continue
                }
                unidentifiedPaymentModelsToCull[paymentModel.uniqueId] = paymentModel
                cullCount += 1
            }
            return cullCount
        }

        func cullUnidentifiedDuplicates(_ map: MultiMap<Data, TSPaymentModel>,
                                        label: String) {
            for (_, paymentModels) in map {
                guard paymentModels.count > 1 else {
                    continue
                }
                for paymentModel in paymentModels {
                    Logger.verbose("Try to cull \(label): \(paymentModel.descriptionForLogs)")
                }
                let culled = cullPaymentModelsIfUnidentified(paymentModels)
                owsAssertDebug(culled > 0)
                Logger.warn("Culling \(label): \(culled)")
            }
        }

        let transactionMap = MultiMap<Data, TSPaymentModel>()
        let receiptMap = MultiMap<Data, TSPaymentModel>()
        let incomingTransactionPublicKeyMap = MultiMap<Data, TSPaymentModel>()
        let spentKeyImagesMap = MultiMap<Data, TSPaymentModel>()
        let outputPublicKeys = MultiMap<Data, TSPaymentModel>()

        let allPaymentModels = TSPaymentModel.anyFetchAll(transaction: transaction)
        for paymentModel in allPaymentModels {
            owsAssertDebug(paymentModel.isFailed == (paymentModel.mobileCoin == nil))
            guard !paymentModel.isFailed,
                  let mobileCoin = paymentModel.mobileCoin else {
                // Ignore failed models.
                continue
            }
            if let key = mobileCoin.transactionData {
                transactionMap.add(key: key, value: paymentModel)
            }
            if let key = mobileCoin.receiptData {
                receiptMap.add(key: key, value: paymentModel)
            }
            for key in mobileCoin.incomingTransactionPublicKeys ?? [] {
                incomingTransactionPublicKeyMap.add(key: key, value: paymentModel)
            }
            for key in mobileCoin.spentKeyImages ?? [] {
                spentKeyImagesMap.add(key: key, value: paymentModel)
            }
            for key in mobileCoin.outputPublicKeys ?? [] {
                outputPublicKeys.add(key: key, value: paymentModel)
            }
        }

        // Cull incoming unidentified payment models which are actually
        // change for an outgoing payment model.
        for (incomingTransactionPublicKey, paymentModels) in incomingTransactionPublicKeyMap {
            let isChange = !outputPublicKeys.values(forKey: incomingTransactionPublicKey).isEmpty
            if isChange {
                let culled = cullPaymentModelsIfUnidentified(paymentModels)
                owsAssertDebug(culled > 0)
                let label = "change"
                Logger.warn("Culling \(label): \(culled)")
            }
        }

        // Only one payment model should correspond to a given MC transaction.
        cullUnidentifiedDuplicates(transactionMap, label: "transactionMap")

        // Only one payment model should correspond to a given MC receipt.
        cullUnidentifiedDuplicates(receiptMap, label: "receiptMap")

        // Only one payment model should correspond to a given MC incoming TXO public key.
        cullUnidentifiedDuplicates(incomingTransactionPublicKeyMap, label: "incomingTransactionPublicKeyMap")

        // Only one payment model should correspond to a given MC spent key image.
        cullUnidentifiedDuplicates(spentKeyImagesMap, label: "spentKeyImagesMap")

        // Only one payment model should correspond to a given MC output public key.
        cullUnidentifiedDuplicates(outputPublicKeys, label: "outputPublicKeys")

        if !unidentifiedPaymentModelsToCull.isEmpty {
            owsFailDebug("Culling payment models: \(unidentifiedPaymentModelsToCull.count)")
            if let transaction = transaction as? SDSAnyWriteTransaction {
                for paymentModel in unidentifiedPaymentModelsToCull.values {
                    Logger.info("Culling payment model: \(paymentModel.descriptionForLogs)")
                    paymentModel.anyRemove(transaction: transaction)
                }
            } else {
                throw ReconciliationError.unsavedChanges
            }
        }
    }

    public func replaceAsUnidentified(paymentModel oldPaymentModel: TSPaymentModel,
                                      transaction: SDSAnyWriteTransaction) {
        guard !oldPaymentModel.isUnidentified else {
            owsFailDebug("Unexpected payment: \(oldPaymentModel.descriptionForLogs)")
            return
        }

        let paymentType: TSPaymentType
        let paymentState: TSPaymentState
        switch oldPaymentModel.paymentType {
        case .outgoingUnidentified,
             .incomingUnidentified:
            owsFailDebug("Unexpected payment: \(oldPaymentModel.descriptionForLogs)")
            return
        case .incomingPayment:
            paymentType = .incomingUnidentified
            paymentState = .incomingComplete
        case .outgoingPayment,
             .outgoingPaymentFromLinkedDevice,
             .outgoingTransfer,
             .outgoingDefragmentation,
             .outgoingDefragmentationFromLinkedDevice:
            paymentType = .outgoingUnidentified
            paymentState = .outgoingComplete
        @unknown default:
            owsFailDebug("Invalid value: \(oldPaymentModel.paymentType.formatted)")
            return
        }

        oldPaymentModel.anyRemove(transaction: transaction)

        let spentKeyImages: [Data]? = Array(Set(oldPaymentModel.mobileCoin?.spentKeyImages ?? [])).nilIfEmpty
        let outputPublicKeys: [Data]? = Array(Set(oldPaymentModel.mobileCoin?.outputPublicKeys ?? [])).nilIfEmpty

        let mobileCoin = MobileCoinPayment(recipientPublicAddressData: nil,
                                           transactionData: nil,
                                           receiptData: nil,
                                           incomingTransactionPublicKeys: oldPaymentModel.mobileCoin?.incomingTransactionPublicKeys,
                                           spentKeyImages: spentKeyImages,
                                           outputPublicKeys: outputPublicKeys,
                                           ledgerBlockTimestamp: oldPaymentModel.mobileCoin?.ledgerBlockTimestamp ?? 0,
                                           ledgerBlockIndex: oldPaymentModel.mobileCoin?.ledgerBlockIndex ?? 0,
                                           feeAmount: nil)
        let newPaymentModel = TSPaymentModel(paymentType: paymentType,
                                             paymentState: paymentState,
                                             paymentAmount: oldPaymentModel.paymentAmount,
                                             createdDate: oldPaymentModel.createdDate,
                                             addressUuidString: nil,
                                             memoMessage: nil,
                                             requestUuidString: nil,
                                             isUnread: false,
                                             mobileCoin: mobileCoin)
        do {
            try Self.paymentsHelper.tryToInsertPaymentModel(newPaymentModel, transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
        }

        scheduleReconciliationNow(transaction: transaction)
    }

    // MARK: -

    internal static func buildPaymentsDatabaseState(transaction: SDSAnyReadTransaction) -> PaymentsDatabaseState {
        let databaseState = PaymentsDatabaseState()

        TSPaymentModel.anyEnumerate(transaction: transaction,
                                    batchSize: 100) { (paymentModel, _) in
            databaseState.add(paymentModel: paymentModel)
        }

        return databaseState
    }

    // MARK: -

    public func willInsertPayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction) {
        // Cull unidentified payment models which might be replaced by this identified model,
        // then schedule reconciliation pass to create new unidentified payment models if necessary.
        if !paymentModel.isUnidentified,
           paymentModel.mcLedgerBlockIndex > 0 {
            cullUnidentifiedPaymentsInSameBlock(paymentModel, transaction: transaction)
        }
    }

    public func willUpdatePayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction) {
        // Cull unidentified payment models which might be replaced by this identified model,
        // then schedule reconciliation pass to create new unidentified payment models if necessary.
        if !paymentModel.isUnidentified,
           paymentModel.mcLedgerBlockIndex > 0 {
            cullUnidentifiedPaymentsInSameBlock(paymentModel, transaction: transaction)
        }
    }

    private func cullUnidentifiedPaymentsInSameBlock(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction) {
        guard !paymentModel.isUnidentified,
              paymentModel.mcLedgerBlockIndex > 0 else {
            owsFailDebug("Invalid paymentModel.")
            return
        }

        let otherPaymentModels = PaymentFinder.paymentModels(forMcLedgerBlockIndex: paymentModel.mcLedgerBlockIndex,
                                                             transaction: transaction)
        for otherPaymentModel in otherPaymentModels {
            guard otherPaymentModel.isUnidentified else {
                continue
            }
            guard paymentModel.uniqueId != otherPaymentModel.uniqueId else {
                owsFailDebug("Invalid paymentModel.")
                continue
            }
            otherPaymentModel.anyRemove(transaction: transaction)
            scheduleReconciliationNow(transaction: transaction)
        }
    }
}

// MARK: -

extension MCTransactionHistoryItem {
    var receivedBlockIndex: UInt64 {
        receivedBlock.index
    }
}

// MARK: -

extension Array where Element == MCTransactionHistoryItem {
    private func sortByBlockIndexBlock(descending: Bool) -> (MCTransactionHistoryItem, MCTransactionHistoryItem) -> Bool {
        return { (left, right) -> Bool in
            if descending {
                return left.receivedBlockIndex > right.receivedBlockIndex
            } else {
                return left.receivedBlockIndex < right.receivedBlockIndex
            }
        }
    }

    func sortedByBlockIndex(descending: Bool) -> [MCTransactionHistoryItem] {
        sorted(by: sortByBlockIndexBlock(descending: descending))
    }

    mutating func sortByBlockIndex(descending: Bool) {
        sort(by: sortByBlockIndexBlock(descending: descending))
    }
}

// MARK: -

private class BlockActivity {
    let blockIndex: UInt64
    var receivedItems = [MCTransactionHistoryItem]()
    var spentItems = [MCTransactionHistoryItem]()

    init(blockIndex: UInt64) {
        self.blockIndex = blockIndex
    }

    func addReceived(item: MCTransactionHistoryItem) {
        owsAssertDebug(receivedItems.filter { $0.txoPublicKey == item.txoPublicKey}.isEmpty)

        receivedItems.append(item)
    }

    func addSpent(item: MCTransactionHistoryItem) {
        owsAssertDebug(spentItems.filter { $0.txoPublicKey == item.txoPublicKey}.isEmpty)

        spentItems.append(item)
    }

    var blockTimestamp: UInt64? {
        for receivedItem in receivedItems {
            if let timestamp = receivedItem.receivedBlock.timestamp {
                return timestamp.ows_millisecondsSince1970
            }
        }
        for spentItem in spentItems {
            if let timestamp = spentItem.spentBlock?.timestamp {
                return timestamp.ows_millisecondsSince1970
            }
        }
        return nil
    }
}

// MARK: -

extension Array where Element == BlockActivity {
    private func sortByBlockIndexBlock(descending: Bool) -> (BlockActivity, BlockActivity) -> Bool {
        return { (left, right) -> Bool in
            if descending {
                return left.blockIndex > right.blockIndex
            } else {
                return left.blockIndex < right.blockIndex
            }
        }
    }

    func sortedByBlockIndex(descending: Bool) -> [BlockActivity] {
        sorted(by: sortByBlockIndexBlock(descending: descending))
    }

    mutating func sortByBlockIndex(descending: Bool) {
        sort(by: sortByBlockIndexBlock(descending: descending))
    }
}

// MARK: -

internal class PaymentsDatabaseState {

    var allPaymentModels = [TSPaymentModel]()

    // A map of "received TXO public key" to TSPaymentModel for
    // (incoming) transactions.
    var incomingAnyMap = MultiMap<Data, TSPaymentModel>()

    // A map of "spent TXO image key" to TSPaymentModel for
    // (known, outgoing) transactions.
    var spentImageKeyMap = [Data: TSPaymentModel]()

    // A map of "output TXO public key" to TSPaymentModel for
    // (known, outgoing) transactions.
    var outputPublicKeyMap = [Data: TSPaymentModel]()

    // A map of "ledger block index" to TSPaymentModel for
    // all payment models.
    //
    // TODO: Extend unit test to verify this state.
    var ledgerBlockIndexMap = MultiMap<UInt64, TSPaymentModel>()

    // MARK: -

    func add(paymentModel: TSPaymentModel) {

        owsAssertDebug(paymentModel.isValid)

        allPaymentModels.append(paymentModel)

        let formattedState = paymentModel.descriptionForLogs

        guard !paymentModel.isFailed else {
            // Ignore failed payments/transactions.
            Logger.verbose("Ignoring failed paymentModel: \(formattedState).")
            return
        }

        if let incomingTransactionPublicKeys = paymentModel.mobileCoin?.incomingTransactionPublicKeys {
            owsAssertDebug(paymentModel.canHaveMCIncomingTransaction)
            for key in incomingTransactionPublicKeys {
                incomingAnyMap.add(key: key, value: paymentModel)
            }
        } else if paymentModel.shouldHaveMCIncomingTransaction {
            owsFailDebug("Empty or missing mcIncomingTransaction: \(formattedState).")
        }

        if let mcSpentKeyImages = paymentModel.mcSpentKeyImages {
            owsAssertDebug(paymentModel.canHaveMCSpentKeyImages)
            for spentImageKey in mcSpentKeyImages {
                spentImageKeyMap[spentImageKey] = paymentModel
            }
        } else if paymentModel.shouldHaveMCSpentKeyImages {
            owsFailDebug("Empty or missing mcSpentKeyImages: \(formattedState).")
        }

        if let mcOutputPublicKeys = paymentModel.mcOutputPublicKeys {
            owsAssertDebug(paymentModel.canHaveMCOutputPublicKeys)
            for outputPublicKeys in mcOutputPublicKeys {
                outputPublicKeyMap[outputPublicKeys] = paymentModel
            }
        } else if paymentModel.shouldHaveMCOutputPublicKeys {
            owsFailDebug("Empty or missing mcOutputPublicKeys: \(formattedState).")
        }

        let ledgerBlockIndex = paymentModel.mobileCoin?.ledgerBlockIndex ?? 0
        if ledgerBlockIndex > 0 {
            ledgerBlockIndexMap.add(key: ledgerBlockIndex, value: paymentModel)
        }
    }

    // MARK: -

    func logVerbose() {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .long
        dateFormatter.dateStyle = .long

        // TODO: Log incomingAnyMap.

        func logMap(_ map: [Data: TSPaymentModel], name: String) {
            Logger.verbose("\(name): \(map.count)")
            for paymentModel in Array(map.values).sortedBySortDate(descending: false) {
                Logger.verbose("\t paymentModel: \(paymentModel.descriptionForLogs)")
            }
        }
        logMap(spentImageKeyMap, name: "spentImageKeyMap")
        logMap(outputPublicKeyMap, name: "outputPublicKeyMap")
    }
}

// MARK: -

public class MultiMap<KeyType: Hashable, ValueType>: Sequence {
    public typealias MapType = [KeyType: [ValueType]]
    private var map = MapType()

    public func add(key: KeyType, value: ValueType) {
        var values = map[key] ?? []
        values.append(value)
        map[key] = values
    }

    public func values(forKey key: KeyType) -> [ValueType] {
        map[key] ?? []
    }

    // MARK: - Sequence

    public typealias Iterator = MapType.Iterator

    public func makeIterator() -> Iterator {
        map.makeIterator()
    }

    public var count: Int { map.count }

    public subscript(_ key: KeyType) -> [ValueType] {
        values(forKey: key)
    }
}

// MARK: -

public protocol MCTransactionHistoryItem {
    var amountPicoMob: UInt64 { get }

    var txoPublicKey: Data { get }

    var keyImage: Data { get }

    var receivedBlock: MobileCoin.BlockMetadata { get }

    var spentBlock: MobileCoin.BlockMetadata? { get }
}

// MARK: -

public protocol MCTransactionHistory {
    var items: [MCTransactionHistoryItem] { get }

    var blockCount: UInt64 { get }
}

// MARK: -

extension MobileCoin.AccountActivity: MCTransactionHistory {
    public var items: [MCTransactionHistoryItem] { Array(txOuts) }
}

// MARK: -

extension MobileCoin.OwnedTxOut: MCTransactionHistoryItem {

    public var amountPicoMob: UInt64 { value }

    public var txoPublicKey: Data { publicKey }
}

// MARK: -

fileprivate extension MCTransactionHistory {
    // Well-behaved clients should never make TXOs of zero value,
    // but we can't count on that.  Therefore we filter records in
    // the SDK transaction history, discarding any zero value TXOs.
    // They have no consequence to the user and this simplifies our
    // logic.
    var safeItems: [MCTransactionHistoryItem] {
        items.filter { $0.amountPicoMob > 0 }
    }
    var receivedItems: [MCTransactionHistoryItem] {
        safeItems
    }
    var spentItems: [MCTransactionHistoryItem] {
        safeItems.filter { $0.spentBlock != nil }
    }
}

//

fileprivate extension Array {
    var nilIfEmpty: [Element]? {
        isEmpty ? nil : self
    }
}
