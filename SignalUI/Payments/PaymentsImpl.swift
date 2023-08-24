//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import MobileCoin
import SignalCoreKit
import SignalMessaging
import SignalServiceKit

public class PaymentsImpl: NSObject, PaymentsSwift {

    private var refreshBalanceEvent: RefreshEvent?

    fileprivate let paymentsReconciliation = PaymentsReconciliation()

    private let paymentsProcessor = PaymentsProcessor()

    public static let maxPaymentMemoMessageLength: Int = 32

    public required override init() {
        super.init()

        // Note: this isn't how often we refresh the balance, it's how often we
        // check whether we should refresh the balance.
        //
        // TODO: Tune.
        let refreshCheckInterval = kMinuteInterval * 5
        refreshBalanceEvent = RefreshEvent(refreshInterval: refreshCheckInterval) { [weak self] in
            self?.updateCurrentPaymentBalanceIfNecessary()
        }

        MobileCoinAPI.configureSDKLogging()

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            DispatchQueue.global().async {
                self.updateLastKnownLocalPaymentAddressProtoDataIfNecessary()
            }
        }
    }

    // NOTE: This k-v store is shared by PaymentsHelperImpl and PaymentsImpl.
    fileprivate static var keyValueStore: SDSKeyValueStore { paymentsHelper.keyValueStore}
    fileprivate var keyValueStore: SDSKeyValueStore { paymentsHelper.keyValueStore}

    private func updateLastKnownLocalPaymentAddressProtoDataIfNecessary() {
        guard tsAccountManager.isRegisteredAndReady else {
            return
        }
        guard AppReadiness.isAppReady else {
            return
        }

        let appVersionKey = "appVersion"
        let currentAppVersion4 = AppVersionImpl.shared.currentAppVersion4

        let shouldUpdate = Self.databaseStorage.read { (transaction: SDSAnyReadTransaction) -> Bool in
            // Check if the app version has changed.
            let lastAppVersion = self.keyValueStore.getString(appVersionKey, transaction: transaction)
            guard lastAppVersion == currentAppVersion4 else {
                return true
            }
            Logger.info("Skipping; lastAppVersion: \(String(describing: lastAppVersion)), currentAppVersion4: \(currentAppVersion4).")
            return false
        }
        guard shouldUpdate else {
            return
        }
        Logger.info("Updating last known local payment address.")

        databaseStorage.write { transaction in
            self.updateLastKnownLocalPaymentAddressProtoData(transaction: transaction)

            self.keyValueStore.setString(currentAppVersion4, key: appVersionKey, transaction: transaction)
        }
    }

    struct ApiHandle {
        let api: MobileCoinAPI
        let creationDate: Date

        var hasExpired: Bool {
            // Authentication expires after 24 hours, so we build new
            // API instances every 12 hours.
            let expiration = kHourInterval * 12
            return abs(creationDate.timeIntervalSinceNow) > expiration
        }
    }

    private static let unfairLock = UnfairLock()
    private var currentApiHandle: ApiHandle?

    public func didReceiveMCAuthError() {
        discardApiHandle()
    }

    private func discardApiHandle() {
        Self.unfairLock.withLock {
            currentApiHandle = nil
        }
    }

    private func getOrBuildCurrentApi(paymentsEntropy: Data) -> Promise<MobileCoinAPI> {
        func getCurrentApi() -> MobileCoinAPI? {
            return Self.unfairLock.withLock { () -> MobileCoinAPI? in
                if let handle = self.currentApiHandle,
                   !handle.hasExpired {
                    return handle.api
                }
                return nil
            }
        }

        func setCurrentApi(_ api: MobileCoinAPI) {
            Self.unfairLock.withLock {
                self.currentApiHandle = ApiHandle(api: api, creationDate: Date())
            }
        }

        if let api = getCurrentApi() {
            return Promise.value(api)
        }

        return firstly(on: DispatchQueue.global()) {
            MobileCoinAPI.buildPromise(paymentsEntropy: paymentsEntropy)
        }.map(on: DispatchQueue.global()) { (api: MobileCoinAPI) -> MobileCoinAPI in
            setCurrentApi(api)
            return api
        }
    }

    // Instances of MobileCoinAPI are slightly expensive to
    // build since we need to obtain authentication from
    // the service, so we cache and reuse instances.
    func getMobileCoinAPI() -> Promise<MobileCoinAPI> {
        guard !CurrentAppContext().isNSE else {
            return Promise(error: OWSAssertionError("Payments disabled in NSE."))
        }
        switch paymentsState {
        case .enabled(let paymentsEntropy):
            return getOrBuildCurrentApi(paymentsEntropy: paymentsEntropy)
        case .disabled, .disabledWithPaymentsEntropy:
            return Promise(error: PaymentsError.notEnabled)
        }
    }

    public var hasValidPhoneNumberForPayments: Bool { paymentsHelper.hasValidPhoneNumberForPayments }

    public var isKillSwitchActive: Bool { paymentsHelper.isKillSwitchActive }

    public var canEnablePayments: Bool { paymentsHelper.canEnablePayments }

    public var shouldShowPaymentsUI: Bool {
        arePaymentsEnabled || canEnablePayments
    }

    // MARK: - PaymentsState

    public var paymentsState: PaymentsState {
        paymentsHelperSwift.paymentsState
    }

    public var arePaymentsEnabled: Bool {
        paymentsHelper.arePaymentsEnabled
    }

    public var paymentsEntropy: Data? {
        paymentsHelper.paymentsEntropy
    }

    public var passphrase: PaymentsPassphrase? {
        guard let paymentsEntropy = paymentsEntropy else {
            owsFailDebug("Missing paymentsEntropy.")
            return nil
        }
        return passphrase(forPaymentsEntropy: paymentsEntropy)
    }

    public func passphrase(forPaymentsEntropy paymentsEntropy: Data) -> PaymentsPassphrase? {
        do {
            return try MobileCoinAPI.passphrase(forPaymentsEntropy: paymentsEntropy)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    public func paymentsEntropy(forPassphrase passphrase: PaymentsPassphrase) -> Data? {
        do {
            return try MobileCoinAPI.paymentsEntropy(forPassphrase: passphrase)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    public func isValidPassphraseWord(_ word: String?) -> Bool {
        MobileCoinAPI.isValidPassphraseWord(word)
    }

    public func clearState(transaction: SDSAnyWriteTransaction) {
        paymentBalanceCache.set(nil)

        discardApiHandle()
    }

    // MARK: - Public Keys

    public func isValidMobileCoinPublicAddress(_ publicAddressData: Data) -> Bool {
        MobileCoinAPI.isValidMobileCoinPublicAddress(publicAddressData)
    }

    // MARK: - Balance

    public static let currentPaymentBalanceDidChange = Notification.Name("currentPaymentBalanceDidChange")

    private let paymentBalanceCache = AtomicOptional<PaymentBalance>(nil)

    public var currentPaymentBalance: PaymentBalance? {
        paymentBalanceCache.get()
    }

    private func setCurrentPaymentBalance(amount: TSPaymentAmount) {
        owsAssertDebug(amount.isValidAmount(canBeEmpty: true))

        let balance = PaymentBalance(amount: amount, date: Date())

        let oldBalance = paymentBalanceCache.get()

        paymentBalanceCache.set(balance)

        if let oldAmount = oldBalance?.amount,
           oldAmount != amount {
            // When the balance changes, there might be new transactions
            // that aren't accounted for in the database yet. Perform
            // reconciliation to ensure we're up-to-date.
            Self.databaseStorage.asyncWrite { transaction in
                self.scheduleReconciliationNow(transaction: transaction)
            }
        }

        // TODO: We could only fire if the value actually changed.
        NotificationCenter.default.postNotificationNameAsync(Self.currentPaymentBalanceDidChange, object: nil)
    }

    private var canUsePayments: Bool {
        arePaymentsEnabled && !CurrentAppContext().isNSE
    }

    // We need to update our balance:
    //
    // * On launch.
    // * Periodically.
    // * After making or receiving payments.
    // * When user navigates into a view that displays the balance.
    public func updateCurrentPaymentBalance() {
        guard canUsePayments else {
            return
        }
        guard AppReadiness.isAppReady,
              CurrentAppContext().isMainAppAndActive,
              Self.tsAccountManager.isRegisteredAndReady else {
            return
        }

        firstly {
            self.updateCurrentPaymentBalancePromise()
        }.catch { error in
            let paymentsError = error as? PaymentsError
            let outdated = paymentsError == .outdatedClient || paymentsError == .attestationVerificationFailed
            Self.paymentsHelper.setPaymentsVersionOutdated(outdated)
            owsFailDebugUnlessMCNetworkFailure(error)
        }
    }

    public func updateCurrentPaymentBalancePromise() -> Promise<TSPaymentAmount> {
        return firstly { () -> Promise<TSPaymentAmount> in
            self.getCurrentBalance()
        }.map { (balance: TSPaymentAmount) -> TSPaymentAmount in
            self.setCurrentPaymentBalance(amount: balance)
            return balance
        }
    }

    private func updateCurrentPaymentBalanceIfNecessary() {
        guard CurrentAppContext().isMainApp else {
            return
        }
        if let lastUpdateDate = paymentBalanceCache.get()?.date {
            // Don't bother updating if we've already updated in the last N hours.
            let updateFrequency: TimeInterval = kHourInterval * 4
            guard abs(lastUpdateDate.timeIntervalSinceNow) > updateFrequency else {
                return
            }
        }

        updateCurrentPaymentBalance()
    }

    public func clearCurrentPaymentBalance() {
        paymentBalanceCache.set(nil)
    }

    // MARK: -

    public func findPaymentModels(withMCLedgerBlockIndex mcLedgerBlockIndex: UInt64,
                                  mcIncomingTransactionPublicKey: Data,
                                  transaction: SDSAnyReadTransaction) -> [TSPaymentModel] {
        PaymentFinder.paymentModels(forMcLedgerBlockIndex: mcLedgerBlockIndex,
                                    transaction: transaction).filter {
                                        let publicKeys = $0.mobileCoin?.incomingTransactionPublicKeys ?? []
                                        return publicKeys.contains(mcIncomingTransactionPublicKey)
                                    }
    }
}

// MARK: - Operations

public extension PaymentsImpl {

    private func fetchPublicAddress(for recipientAci: Aci) -> Promise<MobileCoin.PublicAddress> {
        return firstly {
            ProfileFetcherJob.fetchProfilePromise(
                serviceId: recipientAci,
                mainAppOnly: false,
                ignoreThrottling: true
            )
        }.map(on: DispatchQueue.global()) { (fetchedProfile: FetchedProfile) -> MobileCoin.PublicAddress in
            guard let decryptedProfile = fetchedProfile.decryptedProfile else {
                throw PaymentsError.userHasNoPublicAddress
            }

            // We don't need to persist this value in the cache; the ProfileFetcherJob
            // will take care of that.
            guard let paymentAddress = decryptedProfile.paymentAddress,
                  paymentAddress.isValid,
                  paymentAddress.currency == .mobileCoin else {
                throw PaymentsError.userHasNoPublicAddress
            }
            do {
                return try paymentAddress.asPublicAddress()
            } catch {
                owsFailDebug("Can't parse public address: \(error)")
                throw PaymentsError.userHasNoPublicAddress
            }
        }
    }

    private func upsertNewOutgoingPaymentModel(
        recipientAci: Aci?,
        recipientPublicAddress: MobileCoin.PublicAddress,
        paymentAmount: TSPaymentAmount,
        feeAmount: TSPaymentAmount,
        memoMessage: String?,
        transaction: MobileCoin.Transaction,
        receipt: MobileCoin.Receipt,
        isOutgoingTransfer: Bool
    ) -> Promise<TSPaymentModel> {
        guard !isKillSwitchActive else {
            return Promise(error: PaymentsError.killSwitch)
        }
        return firstly(on: DispatchQueue.global()) {
            let recipientPublicAddressData = recipientPublicAddress.serializedData
            guard paymentAmount.currency == .mobileCoin,
                  paymentAmount.isValidAmount(canBeEmpty: false) else {
                throw OWSAssertionError("Invalid amount.")
            }
            guard feeAmount.currency == .mobileCoin,
                  feeAmount.isValidAmount(canBeEmpty: false) else {
                throw OWSAssertionError("Invalid fee.")
            }

            let mcTransactionData = transaction.serializedData
            let mcReceiptData = receipt.serializedData
            let paymentType: TSPaymentType = isOutgoingTransfer ? .outgoingTransfer : .outgoingPayment
            let inputKeyImages = Array(Set(transaction.inputKeyImages))
            owsAssertDebug(inputKeyImages.count == transaction.inputKeyImages.count)
            let outputPublicKeys = Array(Set(transaction.outputPublicKeys))
            owsAssertDebug(outputPublicKeys.count == transaction.outputPublicKeys.count)

            let mobileCoin = MobileCoinPayment(recipientPublicAddressData: recipientPublicAddressData,
                                               transactionData: mcTransactionData,
                                               receiptData: mcReceiptData,
                                               incomingTransactionPublicKeys: nil,
                                               spentKeyImages: inputKeyImages,
                                               outputPublicKeys: outputPublicKeys,
                                               ledgerBlockTimestamp: 0,
                                               ledgerBlockIndex: 0,
                                               feeAmount: feeAmount)

            let paymentModel = TSPaymentModel(
                paymentType: paymentType,
                paymentState: .outgoingUnsubmitted,
                paymentAmount: paymentAmount,
                createdDate: Date(),
                senderOrRecipientAci: recipientAci.map { AciObjC($0) },
                memoMessage: memoMessage?.nilIfEmpty,
                isUnread: false,
                interactionUniqueId: nil,
                mobileCoin: mobileCoin
            )

            guard paymentModel.isValid else {
                throw OWSAssertionError("Invalid paymentModel.")
            }

            try Self.databaseStorage.write { transaction in
                try self.paymentsHelper.tryToInsertPaymentModel(paymentModel, transaction: transaction)
            }

            return paymentModel
        }
    }
}

// MARK: - TSPaymentAddress

public extension PaymentsImpl {

    private func localMobileCoinAccount(paymentsState: PaymentsState) -> MobileCoinAPI.MobileCoinAccount? {
        owsAssertDebug(paymentsState.isEnabled)

        guard let paymentsEntropy = paymentsState.paymentsEntropy else {
            owsFailDebug("Missing paymentsEntropy.")
            return nil
        }

        do {
            return try MobileCoinAPI.buildLocalAccount(paymentsEntropy: paymentsEntropy)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    private func localMobileCoinAccount() -> MobileCoinAPI.MobileCoinAccount? {
        localMobileCoinAccount(paymentsState: self.paymentsState)
    }

    // Only valid for the recipient
    func unmaskReceiptAmount(data: Data?) -> Amount? {
        guard let data = data else { return nil }
        let account = localMobileCoinAccount()
        guard let accountKey = account?.accountKey else { return nil }
        guard let receipt = Receipt(serializedData: data) else { return nil }
        guard let amount = receipt.validateAndUnmaskAmount(accountKey: accountKey) else { return nil }
        return amount
    }

    // Only valid for the recipient
    func decryptReceipt(data: Data) -> (Amount?, Receipt?) {
        let account = localMobileCoinAccount()
        guard let accountKey = account?.accountKey else { return (nil, nil) }
        guard let receipt = Receipt(serializedData: data) else { return (nil, nil) }
        guard let amount = receipt.validateAndUnmaskAmount(accountKey: accountKey) else { return (nil, nil) }
        return (amount, receipt)
    }

    func buildLocalPaymentAddress(paymentsState: PaymentsState) -> TSPaymentAddress? {
        owsAssertDebug(paymentsState.isEnabled)

        guard let localAccount = self.localMobileCoinAccount(paymentsState: paymentsState) else {
            owsFailDebug("Missing local account.")
            return nil
        }
        return localAccount.accountKey.publicAddress.asPaymentAddress
    }

    func walletAddressBase58() -> String? {
        guard let localAccount = self.localMobileCoinAccount() else {
            return nil
        }
        return Self.formatAsBase58(publicAddress: localAccount.accountKey.publicAddress)
    }

    func walletAddressQRUrl() -> URL? {
        guard let localAccount = self.localMobileCoinAccount() else {
            return nil
        }
        guard let url = URL(string: Self.formatAsUrl(publicAddress: localAccount.accountKey.publicAddress)) else {
            owsFailDebug("Invalid url.")
            return nil
        }
        return url
    }

    func localPaymentAddressProtoData() -> Data? {
        localPaymentAddressProtoData(paymentsState: self.paymentsState)
    }

    func localPaymentAddressProtoData(paymentsState: PaymentsState) -> Data? {
        owsAssertDebug(paymentsState.isEnabled)

        guard let localPaymentAddress = buildLocalPaymentAddress(paymentsState: paymentsState) else {
            owsFailDebug("Missing localPaymentAddress.")
            return nil
        }
        guard localPaymentAddress.isValid,
              localPaymentAddress.currency == .mobileCoin else {
            owsFailDebug("Invalid localPaymentAddress.")
            return nil
        }

        do {
            let proto = try localPaymentAddress.buildProto()
            return try proto.serializedData()
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    func updateLastKnownLocalPaymentAddressProtoData(transaction: SDSAnyWriteTransaction) {
        let data: Data?
        let paymentsState = self.paymentsState
        if paymentsState.isEnabled {
            data = localPaymentAddressProtoData(paymentsState: paymentsState)
        } else {
            data = nil
        }
        paymentsHelper.setLastKnownLocalPaymentAddressProtoData(data, transaction: transaction)
    }
}

// MARK: - Current Balance

public extension PaymentsImpl {
    func getCurrentBalance() -> Promise<TSPaymentAmount> {
        firstly { () -> Promise<MobileCoinAPI> in
            self.getMobileCoinAPI()
        }.then(on: DispatchQueue.global()) { (mobileCoinAPI: MobileCoinAPI) in
            return mobileCoinAPI.getLocalBalance()
        }
    }
}

// MARK: - PaymentTransaction

public extension PaymentsImpl {

    func maximumPaymentAmount() -> Promise<TSPaymentAmount> {
        return firstly(on: DispatchQueue.global()) { () -> Promise<MobileCoinAPI> in
            self.getMobileCoinAPI()
        }.then(on: DispatchQueue.global()) { (mobileCoinAPI: MobileCoinAPI) -> Promise<TSPaymentAmount> in
            try mobileCoinAPI.maxTransactionAmount()
        }
    }

    func getEstimatedFee(forPaymentAmount paymentAmount: TSPaymentAmount) -> Promise<TSPaymentAmount> {
        guard paymentAmount.currency == .mobileCoin else {
            return Promise(error: OWSAssertionError("Invalid currency."))
        }

        return firstly(on: DispatchQueue.global()) { () -> Promise<MobileCoinAPI> in
            self.getMobileCoinAPI()
        }.then(on: DispatchQueue.global()) { (mobileCoinAPI: MobileCoinAPI) -> Promise<TSPaymentAmount> in
            try mobileCoinAPI.getEstimatedFee(forPaymentAmount: paymentAmount)
        }
    }

    func prepareOutgoingPayment(
        recipient: SendPaymentRecipient,
        paymentAmount: TSPaymentAmount,
        memoMessage: String?,
        isOutgoingTransfer: Bool,
        canDefragment: Bool
    ) -> Promise<PreparedPayment> {

        guard !isKillSwitchActive else {
            return Promise(error: PaymentsError.killSwitch)
        }
        guard let recipient = recipient as? SendPaymentRecipientImpl else {
            return Promise(error: OWSAssertionError("Invalid recipient."))
        }

        switch recipient {
        case .address(let recipientAddress):
            // Cannot send "user-to-user" payment if kill switch is active.
            guard !payments.isKillSwitchActive else {
                return Promise(error: PaymentsError.killSwitch)
            }

            guard let recipientAci = recipientAddress.serviceId as? Aci else {
                return Promise(error: PaymentsError.userHasNoPublicAddress)
            }

            return firstly(on: DispatchQueue.global()) { () -> Promise<MobileCoin.PublicAddress> in
                self.fetchPublicAddress(for: recipientAci)
            }.then(on: DispatchQueue.global()) { (recipientPublicAddress: MobileCoin.PublicAddress) -> Promise<PreparedPayment> in
                self.prepareOutgoingPayment(
                    recipientAci: recipientAci,
                    recipientPublicAddress: recipientPublicAddress,
                    paymentAmount: paymentAmount,
                    memoMessage: memoMessage,
                    isOutgoingTransfer: isOutgoingTransfer,
                    canDefragment: canDefragment
                )
            }
        case .publicAddress(let recipientPublicAddress):
            return prepareOutgoingPayment(
                recipientAci: nil,
                recipientPublicAddress: recipientPublicAddress,
                paymentAmount: paymentAmount,
                memoMessage: memoMessage,
                isOutgoingTransfer: isOutgoingTransfer,
                canDefragment: canDefragment
            )
        }
    }

    private func prepareOutgoingPayment(
        recipientAci: Aci?,
        recipientPublicAddress: MobileCoin.PublicAddress,
        paymentAmount: TSPaymentAmount,
        memoMessage: String?,
        isOutgoingTransfer: Bool,
        canDefragment: Bool
    ) -> Promise<PreparedPayment> {

        guard !isKillSwitchActive else {
            return Promise(error: PaymentsError.killSwitch)
        }
        guard paymentAmount.currency == .mobileCoin else {
            return Promise(error: OWSAssertionError("Invalid currency."))
        }
        guard recipientAci != Self.tsAccountManager.localIdentifiers?.aci else {
            return Promise(error: OWSAssertionError("Can't make payment to yourself."))
        }

        return firstly(on: DispatchQueue.global()) { () -> Promise<MobileCoinAPI> in
            self.getMobileCoinAPI()
        }.then(on: DispatchQueue.global()) { (mobileCoinAPI: MobileCoinAPI) -> Promise<PreparedPayment> in
            return firstly(on: DispatchQueue.global()) { () throws -> Promise<TSPaymentAmount> in
                // prepareTransaction() will fail if local balance is not yet known.
                mobileCoinAPI.getLocalBalance()
            }.then(on: DispatchQueue.global()) { (balance: TSPaymentAmount) -> Promise<Void> in
                Logger.verbose("balance: \(balance.picoMob)")
                return self.defragmentIfNecessary(forPaymentAmount: paymentAmount,
                                                  mobileCoinAPI: mobileCoinAPI,
                                                  canDefragment: canDefragment)
            }.then(on: DispatchQueue.global()) { () -> Promise<MobileCoinAPI.PreparedTransaction> in
                // prepareTransaction() will fail if local balance is not yet known.
                let shouldUpdateBalance = self.currentPaymentBalance == nil
                return mobileCoinAPI.prepareTransaction(paymentAmount: paymentAmount,
                                                        recipientPublicAddress: recipientPublicAddress,
                                                        shouldUpdateBalance: shouldUpdateBalance)
            }.map(on: DispatchQueue.global()) { (preparedTransaction: MobileCoinAPI.PreparedTransaction) -> PreparedPayment in
                PreparedPaymentImpl(
                    recipientAci: recipientAci,
                    recipientPublicAddress: recipientPublicAddress,
                    paymentAmount: paymentAmount,
                    memoMessage: memoMessage,
                    isOutgoingTransfer: isOutgoingTransfer,
                    preparedTransaction: preparedTransaction
                )
            }
        }
    }

    private func defragmentIfNecessary(forPaymentAmount paymentAmount: TSPaymentAmount,
                                       mobileCoinAPI: MobileCoinAPI,
                                       canDefragment: Bool) -> Promise<Void> {
        Logger.verbose("")

        return firstly(on: DispatchQueue.global()) { () throws -> Promise<Bool> in
            mobileCoinAPI.requiresDefragmentation(forPaymentAmount: paymentAmount)
        }.then(on: DispatchQueue.global()) { (shouldDefragment: Bool) -> Promise<Void> in
            guard shouldDefragment else {
                return Promise.value(())
            }
            guard canDefragment else {
                throw PaymentsError.defragmentationRequired
            }
            return self.defragment(forPaymentAmount: paymentAmount,
                                   mobileCoinAPI: mobileCoinAPI)
        }
    }

    private func defragment(forPaymentAmount paymentAmount: TSPaymentAmount,
                            mobileCoinAPI: MobileCoinAPI) -> Promise<Void> {
        Logger.info("")

        // 1. Prepare defragmentation transactions.
        // 2. Record defragmentation transactions in database.
        //   3. Submit defragmentation transactions (payment processor will do this).
        //   4. Verify defragmentation transactions (payment processor will do this).
        // 5. Block on verification of defragmentation transactions.
        return firstly(on: DispatchQueue.global()) { () throws -> Promise<[MobileCoin.Transaction]> in
            mobileCoinAPI.prepareDefragmentationStepTransactions(forPaymentAmount: paymentAmount)
        }.map(on: DispatchQueue.global()) { (mcTransactions: [MobileCoin.Transaction]) -> [TSPaymentModel] in
            Logger.info("mcTransactions: \(mcTransactions.count)")

            // To initiate the defragmentation transactions, all we need to do
            // is save TSPaymentModels to the database. The PaymentsProcessor
            // will observe this and take responsibility for their submission,
            // verification.
            return try Self.databaseStorage.write { dbTransaction in
                try mcTransactions.map { mcTransaction in
                    let paymentAmount = TSPaymentAmount(currency: .mobileCoin, picoMob: 0)
                    let feeAmount = TSPaymentAmount(currency: .mobileCoin, picoMob: mcTransaction.fee)
                    let mcTransactionData = mcTransaction.serializedData
                    let inputKeyImages = Array(Set(mcTransaction.inputKeyImages))
                    owsAssertDebug(inputKeyImages.count == mcTransaction.inputKeyImages.count)
                    let outputPublicKeys = Array(Set(mcTransaction.outputPublicKeys))
                    owsAssertDebug(outputPublicKeys.count == mcTransaction.outputPublicKeys.count)
                    let mobileCoin = MobileCoinPayment(recipientPublicAddressData: nil,
                                                       transactionData: mcTransactionData,
                                                       receiptData: nil,
                                                       incomingTransactionPublicKeys: nil,
                                                       spentKeyImages: inputKeyImages,
                                                       outputPublicKeys: outputPublicKeys,
                                                       ledgerBlockTimestamp: 0,
                                                       ledgerBlockIndex: 0,
                                                       feeAmount: feeAmount)

                    let paymentModel = TSPaymentModel(paymentType: .outgoingDefragmentation,
                                                      paymentState: .outgoingUnsubmitted,
                                                      paymentAmount: paymentAmount,
                                                      createdDate: Date(),
                                                      senderOrRecipientAci: nil,
                                                      memoMessage: nil,
                                                      isUnread: false,
                                                      interactionUniqueId: nil,
                                                      mobileCoin: mobileCoin)

                    guard paymentModel.isValid else {
                        throw OWSAssertionError("Invalid paymentModel.")
                    }

                    try self.paymentsHelper.tryToInsertPaymentModel(paymentModel, transaction: dbTransaction)

                    return paymentModel
                }
            }
        }.then(on: DispatchQueue.global()) { (paymentModels: [TSPaymentModel]) -> Promise<Void> in
            self.blockOnVerificationOfDefragmentation(paymentModels: paymentModels)
        }
    }

    func initiateOutgoingPayment(preparedPayment: PreparedPayment) -> Promise<TSPaymentModel> {
        guard !isKillSwitchActive else {
            return Promise(error: PaymentsError.killSwitch)
        }
        return firstly(on: DispatchQueue.global()) { () -> Promise<TSPaymentModel> in
            guard let preparedPayment = preparedPayment as? PreparedPaymentImpl else {
                throw OWSAssertionError("Invalid preparedPayment.")
            }
            let preparedTransaction = preparedPayment.preparedTransaction

            // To initiate the outgoing payment, all we need to do is save
            // the TSPaymentModel to the database. The PaymentsProcessor
            // will observe this and take responsibility for the submission,
            // verification and notification of the payment.
            return self.upsertNewOutgoingPaymentModel(
                recipientAci: preparedPayment.recipientAci,
                recipientPublicAddress: preparedPayment.recipientPublicAddress,
                paymentAmount: preparedPayment.paymentAmount,
                feeAmount: preparedTransaction.feeAmount,
                memoMessage: preparedPayment.memoMessage,
                transaction: preparedTransaction.transaction,
                receipt: preparedTransaction.receipt,
                isOutgoingTransfer: preparedPayment.isOutgoingTransfer
            )
        }
    }

    private func blockOnVerificationOfDefragmentation(paymentModels: [TSPaymentModel]) -> Promise<Void> {
        let maxBlockInterval = kSecondInterval * 30

        return firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
            let promises = paymentModels.map { paymentModel in
                firstly(on: DispatchQueue.global()) { () -> Promise<Bool> in
                    self.blockOnOutgoingVerification(paymentModel: paymentModel)
                }.map(on: DispatchQueue.global()) { (didSucceed: Bool) -> Void in
                    guard didSucceed else {
                        throw PaymentsError.defragmentationFailed
                    }
                }
            }
            return Promise.when(fulfilled: promises)
        }.timeout(seconds: maxBlockInterval, description: "blockOnVerificationOfDefragmentation") { () -> Error in
            PaymentsError.timeout
        }
    }

    func blockOnOutgoingVerification(paymentModel: TSPaymentModel) -> Promise<Bool> {
        firstly(on: DispatchQueue.global()) { () -> Promise<Bool> in
            let paymentModelLatest = Self.databaseStorage.read { transaction in
                TSPaymentModel.anyFetch(uniqueId: paymentModel.uniqueId,
                                        transaction: transaction)
            }
            guard let paymentModel = paymentModelLatest else {
                throw PaymentsError.missingModel
            }

            switch paymentModel.paymentState {
            case .outgoingUnsubmitted,
                 .outgoingUnverified:
                // Not yet verified, wait then try again.
                return firstly(on: DispatchQueue.global()) {
                    Guarantee.after(seconds: 0.05)
                }.then(on: DispatchQueue.global()) { () -> Promise<Bool> in
                    // Recurse.
                    self.blockOnOutgoingVerification(paymentModel: paymentModel)
                }
            case .outgoingVerified,
                 .outgoingSending,
                 .outgoingSent,
                 .outgoingComplete:
                // Success: Verified.
                return Promise.value(true)
            case .outgoingFailed:
                // Success: Failed.
                return Promise.value(false)
            case .incomingUnverified,
                 .incomingVerified,
                 .incomingComplete,
                 .incomingFailed:
                owsFailDebug("Unexpected paymentState: \(paymentModel.descriptionForLogs)")
                throw PaymentsError.invalidModel
            @unknown default:
                owsFailDebug("Invalid paymentState: \(paymentModel.descriptionForLogs)")
                throw PaymentsError.invalidModel
            }
        }
    }

    class func sendDefragmentationSyncMessage(paymentModel: TSPaymentModel,
                                              transaction: SDSAnyWriteTransaction) {
        Logger.verbose("")
        guard paymentModel.isDefragmentation else {
            owsFailDebug("Invalid paymentType.")
            return
        }
        guard let paymentAmount = paymentModel.paymentAmount,
              paymentAmount.currency == .mobileCoin,
              paymentAmount.isValidAmount(canBeEmpty: true),
              paymentAmount.picoMob == 0 else {
            owsFailDebug("Missing or invalid paymentAmount.")
            return
        }
        guard let feeAmount = paymentModel.mobileCoin?.feeAmount,
              feeAmount.currency == .mobileCoin,
              feeAmount.isValidAmount(canBeEmpty: false) else {
            owsFailDebug("Missing or invalid feeAmount.")
            return
        }
        guard let mcTransactionData = paymentModel.mcTransactionData,
              !mcTransactionData.isEmpty,
              let mcTransaction = MobileCoin.Transaction(serializedData: mcTransactionData) else {
            if DebugFlags.paymentsIgnoreBadData.get() {
                Logger.warn("Missing or invalid mcTransactionData.")
            } else {
                owsFailDebug("Missing or invalid mcTransactionData.")
            }
            return
        }
        guard let mcReceiptData = paymentModel.mcReceiptData,
              !mcReceiptData.isEmpty,
              nil != MobileCoin.Receipt(serializedData: mcReceiptData) else {
            if DebugFlags.paymentsIgnoreBadData.get() {
                Logger.warn("Missing or invalid mcReceiptData.")
            } else {
                owsFailDebug("Missing or invalid mcReceiptData.")
            }
            return
        }
        let mcSpentKeyImages = Array(mcTransaction.inputKeyImages)
        guard !mcSpentKeyImages.isEmpty else {
            if DebugFlags.paymentsIgnoreBadData.get() {
                Logger.warn("Missing or invalid mcSpentKeyImages.")
            } else {
                owsFailDebug("Missing or invalid mcSpentKeyImages.")
            }
            return
        }
        let mcOutputPublicKeys = Array(mcTransaction.outputPublicKeys)
        guard !mcOutputPublicKeys.isEmpty else {
            if DebugFlags.paymentsIgnoreBadData.get() {
                Logger.warn("Missing or invalid mcOutputPublicKeys.")
            } else {
                owsFailDebug("Missing or invalid mcOutputPublicKeys.")
            }
            return
        }

        _ = sendOutgoingPaymentSyncMessage(recipientAci: nil,
                                           recipientAddress: nil,
                                           paymentAmount: paymentAmount,
                                           feeAmount: feeAmount,
                                           mcLedgerBlockTimestamp: paymentModel.mcLedgerBlockTimestamp,
                                           mcLedgerBlockIndex: paymentModel.mcLedgerBlockIndex,
                                           memoMessage: nil,
                                           mcSpentKeyImages: mcSpentKeyImages,
                                           mcOutputPublicKeys: mcOutputPublicKeys,
                                           mcReceiptData: mcReceiptData,
                                           isDefragmentation: true,
                                           transaction: transaction)
    }

    class func sendPaymentNotificationMessage(paymentModel: TSPaymentModel,
                                              transaction: SDSAnyWriteTransaction) throws -> OWSOutgoingPaymentMessage {
        guard paymentModel.paymentType == .outgoingPayment else {
            owsFailDebug("Invalid paymentType.")
            throw PaymentsError.invalidModel
        }
        guard paymentModel.paymentState == .outgoingVerified ||
                DebugFlags.paymentsDoubleNotify.get() else {
            owsFailDebug("Invalid paymentState: \(paymentModel.paymentState.formatted).")
            throw PaymentsError.invalidModel
        }
        guard let paymentAmount = paymentModel.paymentAmount else {
            owsFailDebug("Missing paymentAmount.")
            throw PaymentsError.invalidModel
        }
        guard paymentAmount.currency == .mobileCoin else {
            owsFailDebug("Invalid currency.")
            throw PaymentsError.invalidModel
        }
        guard paymentAmount.picoMob > 0 else {
            owsFailDebug("Invalid amount.")
            throw PaymentsError.invalidModel
        }
        guard let recipientAci = paymentModel.senderOrRecipientAci?.wrappedAciValue else {
            owsFailDebug("Invalid recipientAci.")
            throw PaymentsError.invalidModel
        }
        guard let mcTransactionData = paymentModel.mcTransactionData,
              mcTransactionData.count > 0 else {
            owsFailDebug("Missing mcTransactionData.")
            throw PaymentsError.invalidModel
        }
        guard let mcReceiptData = paymentModel.mcReceiptData,
              mcReceiptData.count > 0 else {
            if DebugFlags.paymentsIgnoreBadData.get() {
                Logger.warn("Missing mcReceiptData.")
            } else {
                owsFailDebug("Missing mcReceiptData.")
            }
            throw PaymentsError.invalidModel
        }

        let message = self.sendPaymentNotificationMessage(
            paymentModel: paymentModel,
            recipientAci: recipientAci,
            memoMessage: paymentModel.memoMessage,
            mcReceiptData: mcReceiptData,
            transaction: transaction
        )
        return message
    }

    class func sendOutgoingPaymentSyncMessage(paymentModel: TSPaymentModel,
                                              transaction: SDSAnyWriteTransaction) {

        Logger.verbose("")
        guard let recipientAci = paymentModel.senderOrRecipientAci else {
            owsFailDebug("Missing recipientAci.")
            return
        }
        guard let recipientAddress = paymentModel.mobileCoin?.recipientPublicAddressData else {
            owsFailDebug("Missing recipientAddress.")
            return
        }
        guard paymentModel.paymentType == .outgoingPayment else {
            owsFailDebug("Invalid paymentType.")
            return
        }
        guard let paymentAmount = paymentModel.paymentAmount,
              paymentAmount.currency == .mobileCoin,
              paymentAmount.isValidAmount(canBeEmpty: false) else {
            owsFailDebug("Missing or invalid paymentAmount.")
            return
        }
        guard let feeAmount = paymentModel.mobileCoin?.feeAmount,
              feeAmount.currency == .mobileCoin,
              feeAmount.isValidAmount(canBeEmpty: false) else {
            owsFailDebug("Missing or invalid feeAmount.")
            return
        }
        guard let mcReceiptData = paymentModel.mcReceiptData,
              !mcReceiptData.isEmpty,
              nil != MobileCoin.Receipt(serializedData: mcReceiptData) else {
            if DebugFlags.paymentsIgnoreBadData.get() {
                Logger.warn("Missing mcReceiptData.")
            } else {
                owsFailDebug("Missing mcReceiptData.")
            }
            return
        }
        guard let mcTransactionData = paymentModel.mcTransactionData,
              !mcTransactionData.isEmpty,
              let mcTransaction = MobileCoin.Transaction(serializedData: mcTransactionData) else {
            if DebugFlags.paymentsIgnoreBadData.get() {
                Logger.warn("Missing or invalid mcTransactionData.")
            } else {
                owsFailDebug("Missing or invalid mcTransactionData.")
            }
            return
        }
        let mcSpentKeyImages = Array(mcTransaction.inputKeyImages)
        guard !mcSpentKeyImages.isEmpty else {
            if DebugFlags.paymentsIgnoreBadData.get() {
                Logger.warn("Missing or invalid mcSpentKeyImages.")
            } else {
                owsFailDebug("Missing or invalid mcSpentKeyImages.")
            }
            return
        }
        let mcOutputPublicKeys = Array(mcTransaction.outputPublicKeys)
        guard !mcOutputPublicKeys.isEmpty else {
            if DebugFlags.paymentsIgnoreBadData.get() {
                Logger.warn("Missing or invalid mcOutputPublicKeys.")
            } else {
                owsFailDebug("Missing or invalid mcOutputPublicKeys.")
            }
            return
        }
        _ = sendOutgoingPaymentSyncMessage(recipientAci: recipientAci.wrappedAciValue,
                                           recipientAddress: recipientAddress,
                                           paymentAmount: paymentAmount,
                                           feeAmount: feeAmount,
                                           mcLedgerBlockTimestamp: paymentModel.mcLedgerBlockTimestamp,
                                           mcLedgerBlockIndex: paymentModel.mcLedgerBlockIndex,
                                           memoMessage: paymentModel.memoMessage,
                                           mcSpentKeyImages: mcSpentKeyImages,
                                           mcOutputPublicKeys: mcOutputPublicKeys,
                                           mcReceiptData: mcReceiptData,
                                           isDefragmentation: false,
                                           transaction: transaction)

    }
}

// MARK: - Messages

public extension PaymentsImpl {
    private class func sendPaymentNotificationMessage(
        paymentModel: TSPaymentModel,
        recipientAci: Aci,
        memoMessage: String?,
        mcReceiptData: Data,
        transaction: SDSAnyWriteTransaction
    ) -> OWSOutgoingPaymentMessage {

        if
            let paymentModel = TSPaymentModel.anyFetch(uniqueId: paymentModel.uniqueId, transaction: transaction),
            let interactionUniqueId = paymentModel.interactionUniqueId
        {
            if
                let existingInteraction = TSInteraction.anyFetch(uniqueId: interactionUniqueId, transaction: transaction),
                let message = existingInteraction as? OWSOutgoingPaymentMessage
            {
                // We already have a message, no need to send anything.
                return message
            } else {
                owsFailBeta("Missing or incorrect interaction type")
            }
        }

        let thread = TSContactThread.getOrCreateThread(
            withContactAddress: SignalServiceAddress(recipientAci),
            transaction: transaction
        )
        let paymentNotification = TSPaymentNotification(
            memoMessage: memoMessage,
            mcReceiptData: mcReceiptData
        )
        let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
        let expiresInSeconds = dmConfigurationStore.durationSeconds(for: thread, tx: transaction.asV2Read)

        let messageBody: String? = {
            guard let picoMob = paymentModel.paymentAmount?.picoMob else {
                return nil
            }
            // Reverse type direction, so it reads correctly incoming to the recipient.
            return PaymentsFormat.paymentPreviewText(
                amount: picoMob,
                transaction: transaction,
                type: .incomingMessage
            )
        }()

        let message = OWSOutgoingPaymentMessage(
            thread: thread,
            messageBody: messageBody,
            paymentNotification: paymentNotification,
            expiresInSeconds: expiresInSeconds,
            transaction: transaction
        )

        paymentModel.update(withInteractionUniqueId: message.uniqueId, transaction: transaction)

        ThreadUtil.enqueueMessage(
            message,
            thread: thread,
            insertMessage: { innerTx in
                message.anyInsert(transaction: innerTx)
                return message.asPreparer
            },
            transaction: transaction
        )

        return message
    }

    class func sendOutgoingPaymentSyncMessage(recipientAci: Aci?,
                                              recipientAddress: Data?,
                                              paymentAmount: TSPaymentAmount,
                                              feeAmount: TSPaymentAmount,
                                              mcLedgerBlockTimestamp: UInt64?,
                                              mcLedgerBlockIndex: UInt64?,
                                              memoMessage: String?,
                                              mcSpentKeyImages: [Data],
                                              mcOutputPublicKeys: [Data],
                                              mcReceiptData: Data,
                                              isDefragmentation: Bool,
                                              transaction: SDSAnyWriteTransaction) -> TSOutgoingMessage? {

        guard let thread = TSAccountManager.getOrCreateLocalThread(transaction: transaction) else {
            owsFailDebug("Missing local thread.")
            return nil
        }
        let mobileCoin = OutgoingPaymentMobileCoin(recipientAci: recipientAci.map { AciObjC($0) },
                                                   recipientAddress: recipientAddress,
                                                   amountPicoMob: paymentAmount.picoMob,
                                                   feePicoMob: feeAmount.picoMob,
                                                   blockIndex: mcLedgerBlockIndex ?? 0,
                                                   blockTimestamp: mcLedgerBlockTimestamp ?? 0,
                                                   memoMessage: memoMessage?.nilIfEmpty,
                                                   spentKeyImages: mcSpentKeyImages,
                                                   outputPublicKeys: mcOutputPublicKeys,
                                                   receiptData: mcReceiptData,
                                                   isDefragmentation: isDefragmentation)
        let message = OutgoingPaymentSyncMessage(thread: thread, mobileCoin: mobileCoin, transaction: transaction)
        Self.sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
        return message
    }
}

// MARK: -

public class PaymentsEventsMainApp: NSObject, PaymentsEvents {
    public func willInsertPayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction) {
        let payments = self.payments as! PaymentsImpl

        payments.paymentsReconciliation.willInsertPayment(paymentModel, transaction: transaction)

        // If we're inserting a new payment of any kind, our balance may have changed.
        payments.updateCurrentPaymentBalance()
    }

    public func willUpdatePayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction) {
        let payments = self.payments as! PaymentsImpl
        payments.paymentsReconciliation.willUpdatePayment(paymentModel, transaction: transaction)
    }

    public func updateLastKnownLocalPaymentAddressProtoData(transaction: SDSAnyWriteTransaction) {
        paymentsImpl.updateLastKnownLocalPaymentAddressProtoData(transaction: transaction)
    }

    public func paymentsStateDidChange() {
        paymentsImpl.updateCurrentPaymentBalance()
    }

    public func clearState(transaction: SDSAnyWriteTransaction) {
        paymentsHelperSwift.clearState(transaction: transaction)
        payments.clearState(transaction: transaction)
    }
}

// MARK: -

public extension PaymentsImpl {

    func scheduleReconciliationNow(transaction: SDSAnyWriteTransaction) {
        paymentsReconciliation.scheduleReconciliationNow(transaction: transaction)
    }

    func replaceAsUnidentified(paymentModel oldPaymentModel: TSPaymentModel,
                               transaction: SDSAnyWriteTransaction) {
        paymentsReconciliation.replaceAsUnidentified(paymentModel: oldPaymentModel,
                                                     transaction: transaction)
    }

    // MARK: - URLs

    static func formatAsBase58(publicAddress: MobileCoin.PublicAddress) -> String {
        MobileCoinAPI.formatAsBase58(publicAddress: publicAddress)
    }

    static func formatAsUrl(publicAddress: MobileCoin.PublicAddress) -> String {
        let url = MobileCoinAPI.formatAsUrl(publicAddress: publicAddress)
        Logger.verbose("publicAddressUrl: \(url)")
        return url
    }

    static func parseAsPublicAddress(url: URL) -> MobileCoin.PublicAddress? {
        Logger.verbose("publicAddressUrl: \(url)")
        return MobileCoinAPI.parseAsPublicAddress(url: url)
    }

    static func parse(publicAddressBase58 base58: String) -> MobileCoin.PublicAddress? {
        MobileCoinAPI.parse(publicAddressBase58: base58)
    }
}

// MARK: -

public enum SendPaymentRecipientImpl: SendPaymentRecipient {
    case address(address: SignalServiceAddress)
    case publicAddress(publicAddress: MobileCoin.PublicAddress)

    public var address: SignalServiceAddress? {
        switch self {
        case .address(let address):
            return address
        case .publicAddress:
            return nil
        }
    }

    public var isIdentifiedPayment: Bool {
        address != nil
    }
}

// MARK: -

public struct PreparedPaymentImpl: PreparedPayment {
    fileprivate let recipientAci: Aci?
    fileprivate let recipientPublicAddress: MobileCoin.PublicAddress
    fileprivate let paymentAmount: TSPaymentAmount
    fileprivate let memoMessage: String?
    fileprivate let isOutgoingTransfer: Bool
    fileprivate let preparedTransaction: MobileCoinAPI.PreparedTransaction

    public var transaction: Transaction { preparedTransaction.transaction }
    public var receipt: Receipt { preparedTransaction.receipt }
    public var feeAmount: TSPaymentAmount { preparedTransaction.feeAmount }
}

extension Amount {
    public var tsPaymentAmount: TSPaymentAmount? {
        TSPaymentAmount(
            currency: self.tokenId == .MOB ? .mobileCoin : .unknown,
            picoMob: self.value
        )
    }
}
