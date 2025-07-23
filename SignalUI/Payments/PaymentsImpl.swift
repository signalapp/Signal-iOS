//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient
public import MobileCoin
public import SignalServiceKit

public class PaymentsImpl: NSObject, PaymentsSwift {

    private let appReadiness: AppReadiness
    private var refreshBalanceEvent: RefreshEvent?

    fileprivate let paymentsReconciliation: PaymentsReconciliation

    private let paymentsProcessor: PaymentsProcessor

    public static let maxPaymentMemoMessageLength: Int = 32

    @MainActor
    public init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
        self.paymentsReconciliation = PaymentsReconciliation(appReadiness: appReadiness)
        self.paymentsProcessor = PaymentsProcessor(appReadiness: appReadiness)
        super.init()

        // Note: this isn't how often we refresh the balance, it's how often we
        // check whether we should refresh the balance.
        //
        // TODO: Tune.
        let refreshCheckInterval: TimeInterval = .minute * 5
        refreshBalanceEvent = RefreshEvent(appReadiness: appReadiness, refreshInterval: refreshCheckInterval) { [weak self] in
            self?.updateCurrentPaymentBalanceIfNecessary()
        }

        MobileCoinAPI.configureSDKLogging()

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            DispatchQueue.global().async {
                self.updateLastKnownLocalPaymentAddressProtoDataIfNecessary()
            }
        }
    }

    // NOTE: This k-v store is shared by PaymentsHelperImpl and PaymentsImpl.
    fileprivate static var keyValueStore: KeyValueStore { SSKEnvironment.shared.paymentsHelperRef.keyValueStore}
    fileprivate var keyValueStore: KeyValueStore { SSKEnvironment.shared.paymentsHelperRef.keyValueStore}

    private func updateLastKnownLocalPaymentAddressProtoDataIfNecessary() {
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return
        }
        guard appReadiness.isAppReady else {
            return
        }

        let appVersionKey = "appVersion"
        let currentAppVersion = AppVersionImpl.shared.currentAppVersion

        let shouldUpdate = SSKEnvironment.shared.databaseStorageRef.read { (transaction: DBReadTransaction) -> Bool in
            // Check if the app version has changed.
            let lastAppVersion = self.keyValueStore.getString(appVersionKey, transaction: transaction)
            guard lastAppVersion == currentAppVersion else {
                return true
            }
            return false
        }
        guard shouldUpdate else {
            return
        }
        Logger.info("Updating last known local payment address.")

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            self.updateLastKnownLocalPaymentAddressProtoData(transaction: transaction)

            self.keyValueStore.setString(currentAppVersion, key: appVersionKey, transaction: transaction)
        }
    }

    struct ApiHandle {
        let api: MobileCoinAPI
        let creationDate: Date

        var hasExpired: Bool {
            // Authentication expires after 24 hours, so we build new
            // API instances every 12 hours.
            return abs(creationDate.timeIntervalSinceNow) > 12 * .hour
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

    private func getOrBuildCurrentApi(paymentsEntropy: Data) async throws -> MobileCoinAPI {
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
            return api
        }

        let api = try await MobileCoinAPI.build(paymentsEntropy: paymentsEntropy)
        setCurrentApi(api)
        return api
    }

    // Instances of MobileCoinAPI are slightly expensive to
    // build since we need to obtain authentication from
    // the service, so we cache and reuse instances.
    func getMobileCoinAPI() async throws -> MobileCoinAPI {
        guard !CurrentAppContext().isNSE else {
            throw OWSAssertionError("Payments disabled in NSE.")
        }
        switch paymentsState {
        case .enabled(let paymentsEntropy):
            return try await getOrBuildCurrentApi(paymentsEntropy: paymentsEntropy)
        case .disabled, .disabledWithPaymentsEntropy:
            throw PaymentsError.notEnabled
        }
    }

    public var hasValidPhoneNumberForPayments: Bool { SSKEnvironment.shared.paymentsHelperRef.hasValidPhoneNumberForPayments }

    public var isKillSwitchActive: Bool { SSKEnvironment.shared.paymentsHelperRef.isKillSwitchActive }

    public var canEnablePayments: Bool { SSKEnvironment.shared.paymentsHelperRef.canEnablePayments }

    public var shouldShowPaymentsUI: Bool {
        arePaymentsEnabled || canEnablePayments
    }

    // MARK: - PaymentsState

    public var paymentsState: PaymentsState {
        SSKEnvironment.shared.paymentsHelperRef.paymentsState
    }

    public var arePaymentsEnabled: Bool {
        SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled
    }

    public var paymentsEntropy: Data? {
        SSKEnvironment.shared.paymentsHelperRef.paymentsEntropy
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

    public func clearState(transaction: DBWriteTransaction) {
        paymentBalanceCache.set(nil)

        discardApiHandle()
    }

    // MARK: - Public Keys

    public func isValidMobileCoinPublicAddress(_ publicAddressData: Data) -> Bool {
        MobileCoinAPI.isValidMobileCoinPublicAddress(publicAddressData)
    }

    // MARK: - Balance

    public static let currentPaymentBalanceDidChange = Notification.Name("currentPaymentBalanceDidChange")

    private let paymentBalanceCache = AtomicOptional<PaymentBalance>(nil, lock: .sharedGlobal)

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
            SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
                self.scheduleReconciliationNow(transaction: transaction)
            }
        }

        // TODO: We could only fire if the value actually changed.
        NotificationCenter.default.postOnMainThread(name: Self.currentPaymentBalanceDidChange, object: nil)
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
        guard
            appReadiness.isAppReady,
            CurrentAppContext().isMainAppAndActive,
            DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
        else {
            return
        }

        Task { @MainActor in
            do {
                _ = try await _updateCurrentPaymentBalance()
            } catch {
                let paymentsError = error as? PaymentsError
                let outdated = paymentsError == .outdatedClient || paymentsError == .attestationVerificationFailed
                SSKEnvironment.shared.paymentsHelperRef.setPaymentsVersionOutdated(outdated)
                owsFailDebugUnlessMCNetworkFailure(error)
            }
        }
    }

    @MainActor
    private func _updateCurrentPaymentBalance() async throws -> TSPaymentAmount {
        let balance = try await self.getCurrentBalance()
        self.setCurrentPaymentBalance(amount: balance)
        return balance
    }

    private func updateCurrentPaymentBalanceIfNecessary() {
        guard CurrentAppContext().isMainApp else {
            return
        }
        if let lastUpdateDate = paymentBalanceCache.get()?.date {
            // Don't bother updating if we've already updated in the last N hours.
            guard abs(lastUpdateDate.timeIntervalSinceNow) > 4 * .hour else {
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
                                  transaction: DBReadTransaction) -> [TSPaymentModel] {
        PaymentFinder.paymentModels(forMcLedgerBlockIndex: mcLedgerBlockIndex,
                                    transaction: transaction).filter {
                                        let publicKeys = $0.mobileCoin?.incomingTransactionPublicKeys ?? []
                                        return publicKeys.contains(mcIncomingTransactionPublicKey)
                                    }
    }
}

// MARK: - Operations

public extension PaymentsImpl {

    private func fetchPublicAddress(for recipientAci: Aci) async throws -> MobileCoin.PublicAddress {
        let profileFetcher = SSKEnvironment.shared.profileFetcherRef
        let fetchedProfile = try await profileFetcher.fetchProfile(for: recipientAci)

        guard let decryptedProfile = fetchedProfile.decryptedProfile else {
            throw PaymentsError.userHasNoPublicAddress
        }

        // We don't need to persist this value in the cache; the ProfileFetcher
        // will take care of that.
        guard
            let paymentAddress = decryptedProfile.paymentAddress(identityKey: fetchedProfile.identityKey),
            paymentAddress.isValid,
            paymentAddress.currency == .mobileCoin
        else {
            throw PaymentsError.userHasNoPublicAddress
        }
        do {
            return try paymentAddress.asPublicAddress()
        } catch {
            owsFailDebug("Can't parse public address: \(error)")
            throw PaymentsError.userHasNoPublicAddress
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
    ) async throws -> TSPaymentModel {
        guard !isKillSwitchActive else {
            throw PaymentsError.killSwitch
        }
        let recipientPublicAddressData = recipientPublicAddress.serializedData
        guard paymentAmount.currency == .mobileCoin, paymentAmount.isValidAmount(canBeEmpty: false) else {
            throw OWSAssertionError("Invalid amount.")
        }
        guard feeAmount.currency == .mobileCoin, feeAmount.isValidAmount(canBeEmpty: false) else {
            throw OWSAssertionError("Invalid fee.")
        }

        let mcTransactionData = transaction.serializedData
        let mcReceiptData = receipt.serializedData
        let paymentType: TSPaymentType = isOutgoingTransfer ? .outgoingTransfer : .outgoingPayment
        let inputKeyImages = Array(Set(transaction.inputKeyImages))
        owsAssertDebug(inputKeyImages.count == transaction.inputKeyImages.count)
        let outputPublicKeys = Array(Set(transaction.outputPublicKeys))
        owsAssertDebug(outputPublicKeys.count == transaction.outputPublicKeys.count)

        let mobileCoin = MobileCoinPayment(
            recipientPublicAddressData: recipientPublicAddressData,
            transactionData: mcTransactionData,
            receiptData: mcReceiptData,
            incomingTransactionPublicKeys: nil,
            spentKeyImages: inputKeyImages,
            outputPublicKeys: outputPublicKeys,
            ledgerBlockTimestamp: 0,
            ledgerBlockIndex: 0,
            feeAmount: feeAmount,
        )

        let paymentModel = TSPaymentModel(
            paymentType: paymentType,
            paymentState: .outgoingUnsubmitted,
            paymentAmount: paymentAmount,
            createdDate: Date(),
            senderOrRecipientAci: recipientAci.map { AciObjC($0) },
            memoMessage: memoMessage?.nilIfEmpty,
            isUnread: false,
            interactionUniqueId: nil,
            mobileCoin: mobileCoin,
        )

        guard paymentModel.isValid else {
            throw OWSAssertionError("Invalid paymentModel.")
        }

        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            try SSKEnvironment.shared.paymentsHelperRef.tryToInsertPaymentModel(paymentModel, transaction: transaction)
        }

        return paymentModel
    }
}

// MARK: - TSPaymentAddress

public extension PaymentsImpl {

    private func localMobileCoinAccount(paymentsState: PaymentsState) -> MobileCoinAPI.MobileCoinAccount? {
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

    // Only valid for the recipient
    func unmaskReceiptAmount(data: Data?) -> Amount? {
        guard let data = data else { return nil }
        let account = localMobileCoinAccount(paymentsState: self.paymentsState)
        guard let accountKey = account?.accountKey else { return nil }
        guard let receipt = Receipt(serializedData: data) else { return nil }
        guard let amount = receipt.validateAndUnmaskAmount(accountKey: accountKey) else { return nil }
        return amount
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
        let paymentsState = self.paymentsState
        owsAssertDebug(paymentsState.isEnabled)
        guard let localAccount = self.localMobileCoinAccount(paymentsState: paymentsState) else {
            return nil
        }
        return Self.formatAsBase58(publicAddress: localAccount.accountKey.publicAddress)
    }

    func localPaymentAddressProtoData(paymentsState: PaymentsState, tx: DBReadTransaction) -> Data? {
        owsAssertDebug(paymentsState.isEnabled)

        guard let localPaymentAddress = buildLocalPaymentAddress(paymentsState: paymentsState) else {
            owsFailDebug("Missing localPaymentAddress.")
            return nil
        }
        guard localPaymentAddress.isValid, localPaymentAddress.currency == .mobileCoin else {
            owsFailDebug("Invalid localPaymentAddress.")
            return nil
        }

        do {
            let proto = try localPaymentAddress.buildProto(tx: tx)
            return try proto.serializedData()
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    func updateLastKnownLocalPaymentAddressProtoData(transaction: DBWriteTransaction) {
        let data: Data?
        let paymentsState = self.paymentsState
        if paymentsState.isEnabled {
            data = localPaymentAddressProtoData(paymentsState: paymentsState, tx: transaction)
        } else {
            data = nil
        }
        SSKEnvironment.shared.paymentsHelperRef.setLastKnownLocalPaymentAddressProtoData(data, transaction: transaction)
    }
}

// MARK: - Current Balance

public extension PaymentsImpl {
    func getCurrentBalance() async throws -> TSPaymentAmount {
        let mobileCoinAPI = try await self.getMobileCoinAPI()
        return try await mobileCoinAPI.getLocalBalance().awaitable()
    }
}

// MARK: - PaymentTransaction

public extension PaymentsImpl {

    func maximumPaymentAmount() async throws -> TSPaymentAmount {
        let mobileCoinAPI = try await self.getMobileCoinAPI()
        return try await mobileCoinAPI.maxTransactionAmount()
    }

    func getEstimatedFee(forPaymentAmount paymentAmount: TSPaymentAmount) async throws -> TSPaymentAmount {
        guard paymentAmount.currency == .mobileCoin else {
            throw OWSAssertionError("Invalid currency.")
        }

        let mobileCoinAPI = try await self.getMobileCoinAPI()
        return try await mobileCoinAPI.getEstimatedFee(forPaymentAmount: paymentAmount)
    }

    func prepareOutgoingPayment(
        recipient: SendPaymentRecipient,
        paymentAmount: TSPaymentAmount,
        memoMessage: String?,
        isOutgoingTransfer: Bool,
        canDefragment: Bool
    ) async throws -> PreparedPayment {
        guard !isKillSwitchActive else {
            throw PaymentsError.killSwitch
        }
        guard let recipient = recipient as? SendPaymentRecipientImpl else {
            throw OWSAssertionError("Invalid recipient.")
        }

        switch recipient {
        case .address(let recipientAddress):
            // Cannot send "user-to-user" payment if kill switch is active.
            guard !SUIEnvironment.shared.paymentsRef.isKillSwitchActive else {
                throw PaymentsError.killSwitch
            }

            guard let recipientAci = recipientAddress.serviceId as? Aci else {
                throw PaymentsError.userHasNoPublicAddress
            }

            let recipientPublicAddress = try await self.fetchPublicAddress(for: recipientAci)
            return try await self.prepareOutgoingPayment(
                recipientAci: recipientAci,
                recipientPublicAddress: recipientPublicAddress,
                paymentAmount: paymentAmount,
                memoMessage: memoMessage,
                isOutgoingTransfer: isOutgoingTransfer,
                canDefragment: canDefragment
            )
        case .publicAddress(let recipientPublicAddress):
            return try await prepareOutgoingPayment(
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
    ) async throws -> PreparedPayment {
        guard !isKillSwitchActive else {
            throw PaymentsError.killSwitch
        }
        guard paymentAmount.currency == .mobileCoin else {
            throw OWSAssertionError("Invalid currency.")
        }
        guard recipientAci != DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
            throw OWSAssertionError("Can't make payment to yourself.")
        }

        let mobileCoinAPI = try await self.getMobileCoinAPI()
        // prepareTransaction() will fail if local balance is not yet known.
        _ = try await mobileCoinAPI.getLocalBalance().awaitable()
        _ = try await self.defragmentIfNecessary(
            forPaymentAmount: paymentAmount,
            mobileCoinAPI: mobileCoinAPI,
            canDefragment: canDefragment,
        )
        // prepareTransaction() will fail if local balance is not yet known.
        let shouldUpdateBalance = self.currentPaymentBalance == nil
        let preparedTransaction = try await mobileCoinAPI.prepareTransaction(
            paymentAmount: paymentAmount,
            recipientPublicAddress: recipientPublicAddress,
            shouldUpdateBalance: shouldUpdateBalance,
        ).awaitable()
        return PreparedPaymentImpl(
            recipientAci: recipientAci,
            recipientPublicAddress: recipientPublicAddress,
            paymentAmount: paymentAmount,
            memoMessage: memoMessage,
            isOutgoingTransfer: isOutgoingTransfer,
            preparedTransaction: preparedTransaction
        )
    }

    private func defragmentIfNecessary(
        forPaymentAmount paymentAmount: TSPaymentAmount,
        mobileCoinAPI: MobileCoinAPI,
        canDefragment: Bool,
    ) async throws {
        let shouldDefragment = try await mobileCoinAPI.requiresDefragmentation(forPaymentAmount: paymentAmount).awaitable()
        guard shouldDefragment else {
            return
        }
        guard canDefragment else {
            throw PaymentsError.defragmentationRequired
        }
        return try await self.defragment(forPaymentAmount: paymentAmount, mobileCoinAPI: mobileCoinAPI)
    }

    private func defragment(forPaymentAmount paymentAmount: TSPaymentAmount, mobileCoinAPI: MobileCoinAPI) async throws {
        Logger.info("")

        // 1. Prepare defragmentation transactions.
        // 2. Record defragmentation transactions in database.
        //   3. Submit defragmentation transactions (payment processor will do this).
        //   4. Verify defragmentation transactions (payment processor will do this).
        // 5. Block on verification of defragmentation transactions.
        let mcTransactions = try await mobileCoinAPI.prepareDefragmentationStepTransactions(forPaymentAmount: paymentAmount).awaitable()
        Logger.info("mcTransactions: \(mcTransactions.count)")

        // To initiate the defragmentation transactions, all we need to do
        // is save TSPaymentModels to the database. The PaymentsProcessor
        // will observe this and take responsibility for their submission,
        // verification.
        let paymentModels = try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { dbTransaction in
            return try mcTransactions.map { mcTransaction in
                let paymentAmount = TSPaymentAmount(currency: .mobileCoin, picoMob: 0)
                let feeAmount = TSPaymentAmount(currency: .mobileCoin, picoMob: mcTransaction.fee)
                let mcTransactionData = mcTransaction.serializedData
                let inputKeyImages = Array(Set(mcTransaction.inputKeyImages))
                owsAssertDebug(inputKeyImages.count == mcTransaction.inputKeyImages.count)
                let outputPublicKeys = Array(Set(mcTransaction.outputPublicKeys))
                owsAssertDebug(outputPublicKeys.count == mcTransaction.outputPublicKeys.count)
                let mobileCoin = MobileCoinPayment(
                    recipientPublicAddressData: nil,
                    transactionData: mcTransactionData,
                    receiptData: nil,
                    incomingTransactionPublicKeys: nil,
                    spentKeyImages: inputKeyImages,
                    outputPublicKeys: outputPublicKeys,
                    ledgerBlockTimestamp: 0,
                    ledgerBlockIndex: 0,
                    feeAmount: feeAmount,
                )

                let paymentModel = TSPaymentModel(
                    paymentType: .outgoingDefragmentation,
                    paymentState: .outgoingUnsubmitted,
                    paymentAmount: paymentAmount,
                    createdDate: Date(),
                    senderOrRecipientAci: nil,
                    memoMessage: nil,
                    isUnread: false,
                    interactionUniqueId: nil,
                    mobileCoin: mobileCoin,
                )

                guard paymentModel.isValid else {
                    throw OWSAssertionError("Invalid paymentModel.")
                }

                try SSKEnvironment.shared.paymentsHelperRef.tryToInsertPaymentModel(paymentModel, transaction: dbTransaction)

                return paymentModel
            }
        }

        return try await self.blockOnVerificationOfDefragmentation(paymentModels: paymentModels)
    }

    func initiateOutgoingPayment(preparedPayment: PreparedPayment) async throws -> TSPaymentModel {
        guard !isKillSwitchActive else {
            throw PaymentsError.killSwitch
        }
        guard let preparedPayment = preparedPayment as? PreparedPaymentImpl else {
            throw OWSAssertionError("Invalid preparedPayment.")
        }
        let preparedTransaction = preparedPayment.preparedTransaction

        // To initiate the outgoing payment, all we need to do is save
        // the TSPaymentModel to the database. The PaymentsProcessor
        // will observe this and take responsibility for the submission,
        // verification and notification of the payment.
        return try await self.upsertNewOutgoingPaymentModel(
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

    private func blockOnVerificationOfDefragmentation(paymentModels: [TSPaymentModel]) async throws {
        let maxBlockInterval: TimeInterval = .second * 30

        do {
            try await withCooperativeTimeout(seconds: maxBlockInterval) {
                try await withThrowingTaskGroup { taskGroup in
                    for paymentModel in paymentModels {
                        taskGroup.addTask {
                            guard try await self.blockOnOutgoingVerification(paymentModel: paymentModel) else {
                                throw PaymentsError.defragmentationFailed
                            }
                        }
                    }
                    try await taskGroup.waitForAll()
                }
            }
        } catch is CooperativeTimeoutError {
            throw PaymentsError.timeout
        }
    }

    func blockOnOutgoingVerification(paymentModel: TSPaymentModel) async throws -> Bool {
        while true {
            let paymentModelLatest = SSKEnvironment.shared.databaseStorageRef.read { transaction in
                TSPaymentModel.anyFetch(uniqueId: paymentModel.uniqueId, transaction: transaction)
            }
            guard let paymentModel = paymentModelLatest else {
                throw PaymentsError.missingModel
            }

            switch paymentModel.paymentState {
            case .outgoingUnsubmitted,
                    .outgoingUnverified:
                // Not yet verified, wait then try again.
                try await Task.sleep(nanoseconds: 50_000_000)
                // loop by not returning
            case .outgoingVerified,
                    .outgoingSending,
                    .outgoingSent,
                    .outgoingComplete:
                // Success: Verified.
                return true
            case .outgoingFailed:
                // Success: Failed.
                return false
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
                                              transaction: DBWriteTransaction) {
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
                                              transaction: DBWriteTransaction) throws -> OWSOutgoingPaymentMessage {
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
                                              transaction: DBWriteTransaction) {

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
        transaction: DBWriteTransaction
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
        let dmConfig = dmConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: transaction)

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
            expiresInSeconds: dmConfig.durationSeconds,
            expireTimerVersion: NSNumber(value: dmConfig.timerVersion),
            transaction: transaction
        )

        paymentModel.update(withInteractionUniqueId: message.uniqueId, transaction: transaction)
        // No attachments to add.
        let unpreparedMessage = UnpreparedOutgoingMessage.forMessage(message)

        ThreadUtil.enqueueMessage(
            unpreparedMessage,
            thread: thread
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
                                              transaction: DBWriteTransaction) -> TSOutgoingMessage? {

        guard let thread = TSContactThread.getOrCreateLocalThread(transaction: transaction) else {
            owsFailDebug("Missing local thread.")
            return nil
        }
        let mobileCoin = OutgoingPaymentMobileCoin(
            recipientAci: recipientAci.map { AciObjC($0) },
            recipientAddress: recipientAddress,
            amountPicoMob: paymentAmount.picoMob,
            feePicoMob: feeAmount.picoMob,
            blockIndex: mcLedgerBlockIndex ?? 0,
            blockTimestamp: mcLedgerBlockTimestamp ?? 0,
            memoMessage: memoMessage?.nilIfEmpty,
            spentKeyImages: mcSpentKeyImages,
            outputPublicKeys: mcOutputPublicKeys,
            receiptData: mcReceiptData,
            isDefragmentation: isDefragmentation
        )
        let message = OutgoingPaymentSyncMessage(
            localThread: thread,
            mobileCoin: mobileCoin,
            transaction: transaction
        )
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: message
        )
        SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: transaction)
        return message
    }
}

// MARK: -

public class PaymentsEventsMainApp: NSObject, PaymentsEvents {
    public func willInsertPayment(_ paymentModel: TSPaymentModel, transaction: DBWriteTransaction) {
        let payments = SUIEnvironment.shared.paymentsRef as! PaymentsImpl

        payments.paymentsReconciliation.willInsertPayment(paymentModel, transaction: transaction)

        // If we're inserting a new payment of any kind, our balance may have changed.
        payments.updateCurrentPaymentBalance()
    }

    public func willUpdatePayment(_ paymentModel: TSPaymentModel, transaction: DBWriteTransaction) {
        let payments = SUIEnvironment.shared.paymentsRef as! PaymentsImpl
        payments.paymentsReconciliation.willUpdatePayment(paymentModel, transaction: transaction)
    }

    public func updateLastKnownLocalPaymentAddressProtoData(transaction: DBWriteTransaction) {
        SUIEnvironment.shared.paymentsImplRef.updateLastKnownLocalPaymentAddressProtoData(transaction: transaction)
    }

    public func paymentsStateDidChange() {
        SUIEnvironment.shared.paymentsImplRef.updateCurrentPaymentBalance()
    }

    public func clearState(transaction: DBWriteTransaction) {
        SSKEnvironment.shared.paymentsHelperRef.clearState(transaction: transaction)
        SUIEnvironment.shared.paymentsRef.clearState(transaction: transaction)
    }
}

// MARK: -

public extension PaymentsImpl {

    func scheduleReconciliationNow(transaction: DBWriteTransaction) {
        paymentsReconciliation.scheduleReconciliationNow(transaction: transaction)
    }

    func replaceAsUnidentified(paymentModel oldPaymentModel: TSPaymentModel,
                               transaction: DBWriteTransaction) {
        paymentsReconciliation.replaceAsUnidentified(paymentModel: oldPaymentModel,
                                                     transaction: transaction)
    }

    // MARK: - URLs

    static func formatAsBase58(publicAddress: MobileCoin.PublicAddress) -> String {
        MobileCoinAPI.formatAsBase58(publicAddress: publicAddress)
    }

    static func parseAsPublicAddress(url: URL) -> MobileCoin.PublicAddress? {
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
