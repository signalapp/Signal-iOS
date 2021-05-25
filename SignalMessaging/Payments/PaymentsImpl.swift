//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import MobileCoin

@objc
public class PaymentsImpl: NSObject, PaymentsSwift {

    // MARK: - KV Store

    fileprivate static let keyValueStore = SDSKeyValueStore(collection: "Payments")

    private var refreshBalanceEvent: RefreshEvent?

    private let paymentsReconciliation = PaymentsReconciliation()

    private let paymentsProcessor = PaymentsProcessor()

    @objc
    public static let maxPaymentMemoMessageLength: Int = 32

    @objc
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

        return firstly(on: .global()) {
            MobileCoinAPI.buildPromise(paymentsEntropy: paymentsEntropy)
        }.map(on: .global()) { (api: MobileCoinAPI) -> MobileCoinAPI in
            setCurrentApi(api)
            return api
        }
    }

    // Instances of MobileCoinAPI are slightly expensive to
    // build since we need to obtain authentication from
    // the service, so we cache and reuse instances.
    func getMobileCoinAPI() -> Promise<MobileCoinAPI> {
        guard FeatureFlags.paymentsEnabled else {
            return Promise(error: PaymentsError.notEnabled)
        }
        switch paymentsState {
        case .enabled(let paymentsEntropy):
            return getOrBuildCurrentApi(paymentsEntropy: paymentsEntropy)
        case .disabled, .disabledWithPaymentsEntropy:
            return Promise(error: PaymentsError.notEnabled)
        }
    }

    public var canEnablePayments: Bool {
        guard FeatureFlags.paymentsEnabled else {
            return false
        }
        guard !isKillSwitchActive else {
            return false
        }
        return hasValidPhoneNumberForPayments
    }

    private var hasValidPhoneNumberForPayments: Bool {
        guard Self.tsAccountManager.isRegisteredAndReady else {
            return false
        }
        if DebugFlags.paymentsAllowAllCountries {
            return true
        }
        guard let localNumber = Self.tsAccountManager.localNumber else {
            return false
        }
        guard let phoneNumber = PhoneNumber(fromE164: localNumber) else {
            owsFailDebug("Could not parse phone number: \(localNumber).")
            return false
        }
        guard let nsCountryCode = phoneNumber.getCountryCode() else {
            owsFailDebug("Missing countryCode: \(localNumber).")
            return false
        }
        let countryCodePartsOfUK: Int = 44
        let validCountryCodes = [ countryCodePartsOfUK ]
        return validCountryCodes.contains(nsCountryCode.intValue)
    }

    public var isKillSwitchActive: Bool {
        RemoteConfig.paymentsResetKillSwitch || !hasValidPhoneNumberForPayments
    }

    public var shouldShowPaymentsUI: Bool {
        arePaymentsEnabled || canEnablePayments
    }

    // MARK: - PaymentsState

    private static let arePaymentsEnabledKey = "isPaymentEnabled"
    private static let paymentsEntropyKey = "paymentsEntropy"

    private let paymentStateCache = AtomicOptional<PaymentsState>(nil)

    @objc
    public static let arePaymentsEnabledDidChange = Notification.Name("arePaymentsEnabledDidChange")

    public func warmCaches() {
        Self.databaseStorage.read { transaction in
            self.paymentStateCache.set(Self.loadPaymentsState(transaction: transaction))
        }
    }

    public var paymentsState: PaymentsState {
        paymentStateCache.get() ?? .disabled
    }

    public var arePaymentsEnabled: Bool {
        paymentsState.isEnabled
    }

    public var paymentsEntropy: Data? {
        paymentsState.paymentsEntropy
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

    public func enablePayments(transaction: SDSAnyWriteTransaction) {
        // We must preserve any existing paymentsEntropy.
        let paymentsEntropy = self.paymentsEntropy ?? Self.generateRandomPaymentsEntropy()
        _ = enablePayments(withPaymentsEntropy: paymentsEntropy, transaction: transaction)
    }

    public func enablePayments(withPaymentsEntropy newPaymentsEntropy: Data, transaction: SDSAnyWriteTransaction) -> Bool {
        let oldPaymentsEntropy = Self.loadPaymentsState(transaction: transaction).paymentsEntropy
        guard oldPaymentsEntropy == nil || oldPaymentsEntropy == newPaymentsEntropy else {
            owsFailDebug("paymentsEntropy is already set.")
            return false
        }
        let paymentsState = PaymentsState.build(arePaymentsEnabled: true,
                                                paymentsEntropy: newPaymentsEntropy)
        owsAssertDebug(paymentsState.isEnabled)
        setPaymentsState(paymentsState,
                         updateStorageService: true,
                         transaction: transaction)
        owsAssertDebug(arePaymentsEnabled)
        return true
    }

    public func disablePayments(transaction: SDSAnyWriteTransaction) {
        switch paymentsState {
        case .enabled(let paymentsEntropy):
            setPaymentsState(.disabledWithPaymentsEntropy(paymentsEntropy: paymentsEntropy),
                             updateStorageService: true,
                             transaction: transaction)
        case .disabled, .disabledWithPaymentsEntropy:
            owsFailDebug("Payments already disabled.")
        }
        owsAssertDebug(!arePaymentsEnabled)
    }

    public func setPaymentsState(_ newPaymentsState: PaymentsState,
                                 updateStorageService: Bool,
                                 transaction: SDSAnyWriteTransaction) {
        let oldPaymentsState = self.paymentsState

        guard !newPaymentsState.isEnabled || canEnablePayments else {
            owsFailDebug("Payments cannot be enabled.")
            return
        }
        guard newPaymentsState != oldPaymentsState else {
            Logger.verbose("Ignoring redundant change.")
            return
        }
        if let oldPaymentsEntropy = oldPaymentsState.paymentsEntropy,
           let newPaymentsEntropy = newPaymentsState.paymentsEntropy,
           oldPaymentsEntropy != newPaymentsEntropy {
            Logger.verbose("oldPaymentsEntropy: \(oldPaymentsEntropy.hexadecimalString) != newPaymentsEntropy: \(newPaymentsEntropy.hexadecimalString).")
            owsFailDebug("paymentsEntropy does not match.")
        }

        Self.keyValueStore.setBool(newPaymentsState.isEnabled,
                                   key: Self.arePaymentsEnabledKey,
                                   transaction: transaction)
        if let paymentsEntropy = newPaymentsState.paymentsEntropy {
            Self.keyValueStore.setData(paymentsEntropy,
                                       key: Self.paymentsEntropyKey,
                                       transaction: transaction)
        }

        self.paymentStateCache.set(newPaymentsState)

        transaction.addAsyncCompletion {
            NotificationCenter.default.postNotificationNameAsync(Self.arePaymentsEnabledDidChange, object: nil)

            self.updateCurrentPaymentBalance()

            Self.profileManager.reuploadLocalProfile()

            if updateStorageService {
                Self.storageServiceManager.recordPendingLocalAccountUpdates()
            }
        }
    }

    private static func loadPaymentsState(transaction: SDSAnyReadTransaction) -> PaymentsState {
        guard FeatureFlags.paymentsEnabled else {
            return .disabled
        }
        func loadPaymentsEntropy() -> Data? {
            guard storageCoordinator.isStorageReady else {
                owsFailDebug("Storage is not ready.")
                return nil
            }
            guard tsAccountManager.isRegisteredAndReady else {
                return nil
            }
            return keyValueStore.getData(paymentsEntropyKey, transaction: transaction)
        }
        guard let paymentsEntropy = loadPaymentsEntropy() else {
            return .disabled
        }
        let arePaymentsEnabled = keyValueStore.getBool(Self.arePaymentsEnabledKey,
                                                       defaultValue: false,
                                                       transaction: transaction)
        return PaymentsState.build(arePaymentsEnabled: arePaymentsEnabled,
                                   paymentsEntropy: paymentsEntropy)
    }

    public static func generateRandomPaymentsEntropy() -> Data {
        Cryptography.generateRandomBytes(PaymentsConstants.paymentsEntropyLength)
    }

    public func clearState(transaction: SDSAnyWriteTransaction) {
        Self.keyValueStore.removeAll(transaction: transaction)

        paymentStateCache.set(nil)
        paymentBalanceCache.set(nil)

        discardApiHandle()
    }

    // MARK: - Public Keys

    private static let arePaymentsEnabledForUserStore = SDSKeyValueStore(collection: "arePaymentsEnabledForUserStore")

    public func setArePaymentsEnabled(for address: SignalServiceAddress, hasPaymentsEnabled: Bool, transaction: SDSAnyWriteTransaction) {
        guard let uuid = address.uuid else {
            Logger.warn("User is missing uuid.")
            return
        }
        Self.arePaymentsEnabledForUserStore.setBool(hasPaymentsEnabled, key: uuid.uuidString, transaction: transaction)
    }

    public func arePaymentsEnabled(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        guard let uuid = address.uuid else {
            Logger.warn("User is missing uuid.")
            return false
        }
        return Self.arePaymentsEnabledForUserStore.getBool(uuid.uuidString,
                                                           defaultValue: false,
                                                           transaction: transaction)
    }

    // MARK: - Public Keys

    public func isValidMobileCoinPublicAddress(_ publicAddressData: Data) -> Bool {
        MobileCoinAPI.isValidMobileCoinPublicAddress(publicAddressData)
    }

    // MARK: - Balance

    @objc
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

    // We need to update our balance:
    //
    // * On launch.
    // * Periodically.
    // * After making or receiving payments.
    // * When user navigates into a view that displays the balance.
    public func updateCurrentPaymentBalance() {
        guard FeatureFlags.paymentsEnabled,
              arePaymentsEnabled else {
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
        if let lastUpdateDate = paymentBalanceCache.get()?.date {
            // Don't bother updating if we've already updated in the last N hours.
            let updateFrequency: TimeInterval = kHourInterval * 4
            guard abs(lastUpdateDate.timeIntervalSinceNow) > updateFrequency else {
                return
            }
        }

        updateCurrentPaymentBalance()
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

    // MARK: - Upsert Payment Records

    private func upsertPaymentModelForIncomingPaymentNotification(_ paymentNotification: TSPaymentNotification,
                                                                  thread: TSThread,
                                                                  senderAddress: SignalServiceAddress,
                                                                  transaction: SDSAnyWriteTransaction) {
        do {
            let mcReceiptData = paymentNotification.mcReceiptData
            guard let receipt = MobileCoin.Receipt(serializedData: mcReceiptData) else {
                throw OWSAssertionError("Invalid receipt.")
            }

            let mobileCoin = MobileCoinPayment(recipientPublicAddressData: nil,
                                               transactionData: nil,
                                               receiptData: paymentNotification.mcReceiptData,
                                               incomingTransactionPublicKeys: [ receipt.txOutPublicKey ],
                                               spentKeyImages: nil,
                                               outputPublicKeys: nil,
                                               ledgerBlockTimestamp: 0,
                                               ledgerBlockIndex: 0,
                                               feeAmount: nil)
            let paymentModel = TSPaymentModel(paymentType: .incomingPayment,
                                              paymentState: .incomingUnverified,
                                              paymentAmount: nil,
                                              createdDate: Date(),
                                              addressUuidString: senderAddress.uuidString,
                                              memoMessage: paymentNotification.memoMessage?.nilIfEmpty,
                                              requestUuidString: nil,
                                              isUnread: true,
                                              mobileCoin: mobileCoin)
            guard paymentModel.isValid else {
                throw OWSAssertionError("Invalid paymentModel.")
            }
            try tryToInsertPaymentModel(paymentModel, transaction: transaction)

            // TODO: Remove any corresponding payment request.
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }

    // Incoming requests are for outgoing payments and vice versa.
    private class func findPaymentRequestModel(forRequestUuidString requestUuidString: String,
                                               expectedIsIncomingRequest: Bool?,
                                               transaction: SDSAnyReadTransaction) -> TSPaymentRequestModel? {

        guard let paymentRequestModel = PaymentFinder.paymentRequestModel(forRequestUuidString: requestUuidString,
                                                                          transaction: transaction) else {
            return nil
        }
        // Incoming requests are for outgoing payments and vice versa.
        if let expectedIsIncomingRequest = expectedIsIncomingRequest {
            guard expectedIsIncomingRequest == paymentRequestModel.isIncomingRequest else {
                owsFailDebug("Unexpected isIncomingRequest: \(paymentRequestModel.isIncomingRequest).")
                return nil
            }
        }
        guard paymentRequestModel.isValid else {
            owsFailDebug("Invalid paymentRequestModel.")
            return nil
        }
        return paymentRequestModel
    }
}

// MARK: - Operations

public extension PaymentsImpl {

    private func fetchPublicAddress(forAddress address: SignalServiceAddress) -> Promise<MobileCoin.PublicAddress> {
        return firstly {
            ProfileFetcherJob.fetchProfilePromise(address: address,
                                                  mainAppOnly: false,
                                                  ignoreThrottling: true,
                                                  fetchType: .`default`)
        }.map(on: .global()) { (fetchedProfile: FetchedProfile) -> MobileCoin.PublicAddress in
            guard let decryptedProfile = fetchedProfile.decryptedProfile else {
                Logger.verbose("address: \(address)")
                throw PaymentsError.userHasNoPublicAddress
            }

            // We don't need to persist this value in the cache; the ProfileFetcherJob
            // will take care of that.
            guard let paymentAddress = decryptedProfile.paymentAddress,
                  paymentAddress.isValid,
                  paymentAddress.currency == .mobileCoin else {
                Logger.verbose("address: \(address)")
                Logger.verbose("profile.paymentAddress: \(String(describing: decryptedProfile.paymentAddress))")
                throw PaymentsError.userHasNoPublicAddress
            }
            do {
                return try paymentAddress.asPublicAddress()
            } catch {
                Logger.verbose("address: \(address)")
                owsFailDebug("Can't parse public address: \(error)")
                throw PaymentsError.userHasNoPublicAddress
            }
        }
    }

    private func upsertNewOutgoingPaymentModel(recipientAddress: SignalServiceAddress?,
                                               recipientPublicAddress: MobileCoin.PublicAddress,
                                               paymentAmount: TSPaymentAmount,
                                               feeAmount: TSPaymentAmount,
                                               memoMessage: String?,
                                               transaction: MobileCoin.Transaction,
                                               receipt: MobileCoin.Receipt,
                                               paymentRequestModel: TSPaymentRequestModel?,
                                               isOutgoingTransfer: Bool) -> Promise<TSPaymentModel> {
        guard !isKillSwitchActive else {
            return Promise(error: PaymentsError.killSwitch)
        }
        return firstly(on: .global()) {
            var addressUuidString: String?
            if let recipientAddress = recipientAddress {
                guard recipientAddress.isValid else {
                    throw OWSAssertionError("Invalid address.")
                }
                guard let recipientUuid = recipientAddress.uuid else {
                    throw OWSAssertionError("Missing recipientUuid.")
                }
                addressUuidString = recipientUuid.uuidString
            }
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

            let paymentModel = TSPaymentModel(paymentType: paymentType,
                                              paymentState: .outgoingUnsubmitted,
                                              paymentAmount: paymentAmount,
                                              createdDate: Date(),
                                              addressUuidString: addressUuidString,
                                              memoMessage: memoMessage?.nilIfEmpty,
                                              requestUuidString: paymentRequestModel?.requestUuidString,
                                              isUnread: false,
                                              mobileCoin: mobileCoin)

            guard paymentModel.isValid else {
                throw OWSAssertionError("Invalid paymentModel.")
            }

            try Self.databaseStorage.write { transaction in
                try self.tryToInsertPaymentModel(paymentModel, transaction: transaction)
            }

            return paymentModel
        }
    }
}

// MARK: - TSPaymentAddress

public extension PaymentsImpl {

    private func localMobileCoinAccount() -> MobileCoinAPI.MobileCoinAccount? {
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

    func buildLocalPaymentAddress() -> TSPaymentAddress? {
        guard let localAccount = self.localMobileCoinAccount() else {
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
        guard let localPaymentAddress = buildLocalPaymentAddress() else {
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
}

// MARK: - Current Balance

public extension PaymentsImpl {
    func getCurrentBalance() -> Promise<TSPaymentAmount> {
        firstly { () -> Promise<MobileCoinAPI> in
            self.getMobileCoinAPI()
        }.then(on: .global()) { (mobileCoinAPI: MobileCoinAPI) in
            return mobileCoinAPI.getLocalBalance()
        }
    }
}

// MARK: - PaymentTransaction

public extension PaymentsImpl {

    func maximumPaymentAmount() -> Promise<TSPaymentAmount> {
        return firstly(on: .global()) { () -> Promise<MobileCoinAPI> in
            self.getMobileCoinAPI()
        }.then(on: .global()) { (mobileCoinAPI: MobileCoinAPI) -> Promise<TSPaymentAmount> in
            try mobileCoinAPI.maxTransactionAmount()
        }
    }

    func getEstimatedFee(forPaymentAmount paymentAmount: TSPaymentAmount) -> Promise<TSPaymentAmount> {
        guard paymentAmount.currency == .mobileCoin else {
            return Promise(error: OWSAssertionError("Invalid currency."))
        }

        return firstly(on: .global()) { () -> Promise<MobileCoinAPI> in
            self.getMobileCoinAPI()
        }.then(on: .global()) { (mobileCoinAPI: MobileCoinAPI) -> Promise<TSPaymentAmount> in
            try mobileCoinAPI.getEstimatedFee(forPaymentAmount: paymentAmount)
        }
    }

    func prepareOutgoingPayment(recipient: SendPaymentRecipient,
                                paymentAmount: TSPaymentAmount,
                                memoMessage: String?,
                                paymentRequestModel: TSPaymentRequestModel?,
                                isOutgoingTransfer: Bool,
                                canDefragment: Bool) -> Promise<PreparedPayment> {

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

            return firstly(on: .global()) { () -> Promise<MobileCoin.PublicAddress> in
                self.fetchPublicAddress(forAddress: recipientAddress)
            }.then(on: .global()) { (recipientPublicAddress: MobileCoin.PublicAddress) -> Promise<PreparedPayment> in
                self.prepareOutgoingPayment(recipientAddress: recipientAddress,
                                              recipientPublicAddress: recipientPublicAddress,
                                              paymentAmount: paymentAmount,
                                              memoMessage: memoMessage,
                                              paymentRequestModel: paymentRequestModel,
                                              isOutgoingTransfer: isOutgoingTransfer,
                                              canDefragment: canDefragment)
            }
        case .publicAddress(let recipientPublicAddress):
            return prepareOutgoingPayment(recipientAddress: nil,
                                            recipientPublicAddress: recipientPublicAddress,
                                            paymentAmount: paymentAmount,
                                            memoMessage: memoMessage,
                                            paymentRequestModel: paymentRequestModel,
                                            isOutgoingTransfer: isOutgoingTransfer,
                                            canDefragment: canDefragment)
        }
    }

    private func prepareOutgoingPayment(recipientAddress: SignalServiceAddress?,
                                          recipientPublicAddress: MobileCoin.PublicAddress,
                                          paymentAmount: TSPaymentAmount,
                                          memoMessage: String?,
                                          paymentRequestModel: TSPaymentRequestModel?,
                                          isOutgoingTransfer: Bool,
                                          canDefragment: Bool) -> Promise<PreparedPayment> {

        guard !isKillSwitchActive else {
            return Promise(error: PaymentsError.killSwitch)
        }
        guard paymentAmount.currency == .mobileCoin else {
            return Promise(error: OWSAssertionError("Invalid currency."))
        }
        guard recipientAddress != Self.tsAccountManager.localAddress else {
            return Promise(error: OWSAssertionError("Can't make payment to yourself."))
        }

        return firstly(on: .global()) { () -> Promise<MobileCoinAPI> in
            self.getMobileCoinAPI()
        }.then(on: .global()) { (mobileCoinAPI: MobileCoinAPI) -> Promise<PreparedPayment> in
            return firstly(on: .global()) { () throws -> Promise<TSPaymentAmount> in
                // prepareTransaction() will fail if local balance is not yet known.
                mobileCoinAPI.getLocalBalance()
            }.then(on: .global()) { (balance: TSPaymentAmount) -> Promise<Void> in
                Logger.verbose("balance: \(balance.picoMob)")
                return self.defragmentIfNecessary(forPaymentAmount: paymentAmount,
                                                  mobileCoinAPI: mobileCoinAPI,
                                                  canDefragment: canDefragment)
            }.then(on: .global()) { () -> Promise<MobileCoinAPI.PreparedTransaction> in
                // prepareTransaction() will fail if local balance is not yet known.
                let shouldUpdateBalance = self.currentPaymentBalance == nil
                return mobileCoinAPI.prepareTransaction(paymentAmount: paymentAmount,
                                                        recipientPublicAddress: recipientPublicAddress,
                                                        shouldUpdateBalance: shouldUpdateBalance)
            }.map(on: .global()) { (preparedTransaction: MobileCoinAPI.PreparedTransaction) -> PreparedPayment in
                PreparedPaymentImpl(
                    recipientAddress: recipientAddress,
                    recipientPublicAddress: recipientPublicAddress,
                    paymentAmount: paymentAmount,
                    memoMessage: memoMessage,
                    paymentRequestModel: paymentRequestModel,
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

        return firstly(on: .global()) { () throws -> Promise<Bool> in
            mobileCoinAPI.requiresDefragmentation(forPaymentAmount: paymentAmount)
        }.then(on: .global()) { (shouldDefragment: Bool) -> Promise<Void> in
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
        return firstly(on: .global()) { () throws -> Promise<[MobileCoin.Transaction]> in
            mobileCoinAPI.prepareDefragmentationStepTransactions(forPaymentAmount: paymentAmount)
        }.map(on: .global()) { (mcTransactions: [MobileCoin.Transaction]) -> [TSPaymentModel] in
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
                                                      addressUuidString: nil,
                                                      memoMessage: nil,
                                                      requestUuidString: nil,
                                                      isUnread: false,
                                                      mobileCoin: mobileCoin)

                    guard paymentModel.isValid else {
                        throw OWSAssertionError("Invalid paymentModel.")
                    }

                    try self.tryToInsertPaymentModel(paymentModel, transaction: dbTransaction)

                    return paymentModel
                }
            }
        }.then(on: .global()) { (paymentModels: [TSPaymentModel]) -> Promise<Void> in
            self.blockOnVerificationOfDefragmentation(paymentModels: paymentModels)
        }
    }

    func initiateOutgoingPayment(preparedPayment: PreparedPayment) -> Promise<TSPaymentModel> {
        guard !isKillSwitchActive else {
            return Promise(error: PaymentsError.killSwitch)
        }
        return firstly(on: .global()) { () -> Promise<TSPaymentModel> in
            guard let preparedPayment = preparedPayment as? PreparedPaymentImpl else {
                throw OWSAssertionError("Invalid preparedPayment.")
            }
            let preparedTransaction = preparedPayment.preparedTransaction

            // To initiate the outgoing payment, all we need to do is save
            // the TSPaymentModel to the database. The PaymentsProcessor
            // will observe this and take responsibility for the submission,
            // verification and notification of the payment.
            //
            // TODO: Handle requests.
            return self.upsertNewOutgoingPaymentModel(recipientAddress: preparedPayment.recipientAddress,
                                                      recipientPublicAddress: preparedPayment.recipientPublicAddress,
                                                      paymentAmount: preparedPayment.paymentAmount,
                                                      feeAmount: preparedTransaction.feeAmount,
                                                      memoMessage: preparedPayment.memoMessage,
                                                      transaction: preparedTransaction.transaction,
                                                      receipt: preparedTransaction.receipt,
                                                      paymentRequestModel: preparedPayment.paymentRequestModel,
                                                      isOutgoingTransfer: preparedPayment.isOutgoingTransfer)
        }
    }

    private func blockOnVerificationOfDefragmentation(paymentModels: [TSPaymentModel]) -> Promise<Void> {
        let maxBlockInterval = kSecondInterval * 30

        return firstly(on: .global()) { () -> Promise<Void> in
            let promises = paymentModels.map { paymentModel in
                firstly(on: .global()) { () -> Promise<Bool> in
                    self.blockOnOutgoingVerification(paymentModel: paymentModel)
                }.map(on: .global()) { (didSucceed: Bool) -> Void in
                    guard didSucceed else {
                        throw PaymentsError.defragmentationFailed
                    }
                }
            }
            return when(fulfilled: promises)
        }.timeout(seconds: maxBlockInterval, description: "blockOnVerificationOfDefragmentation") { () -> Error in
            PaymentsError.timeout
        }
    }

    func blockOnOutgoingVerification(paymentModel: TSPaymentModel) -> Promise<Bool> {
        firstly(on: .global()) { () -> Promise<Bool> in
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
                return firstly(on: .global()) {
                    after(seconds: 0.05)
                }.then(on: .global()) { () -> Promise<Bool> in
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

        _ = sendOutgoingPaymentSyncMessage(recipientUuid: nil,
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

        Logger.verbose("")
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
        guard let address = paymentModel.address,
              address.isValid else {
            owsFailDebug("Invalid address.")
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
        let requestUuidString = paymentModel.requestUuidString

        Logger.verbose("paymentState: \(paymentModel.paymentState.formatted).")

        let message = self.sendPaymentNotificationMessage(address: address,
                                                          memoMessage: paymentModel.memoMessage,
                                                          mcReceiptData: mcReceiptData,
                                                          requestUuidString: requestUuidString,
                                                          transaction: transaction)
        return message
    }

    class func sendOutgoingPaymentSyncMessage(paymentModel: TSPaymentModel,
                                              transaction: SDSAnyWriteTransaction) {

        Logger.verbose("")
        guard let recipientUuidString = paymentModel.addressUuidString,
              let recipientUuid = UUID(uuidString: recipientUuidString) else {
            owsFailDebug("Missing recipientUuid.")
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
        _ = sendOutgoingPaymentSyncMessage(recipientUuid: recipientUuid,
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
    class func sendPaymentRequestMessagePromise(address: SignalServiceAddress,
                                                paymentAmount: TSPaymentAmount,
                                                memoMessage: String?) -> Promise<OWSOutgoingPaymentMessage> {
        databaseStorage.write(.promise) { transaction in
            guard let addressUuid = address.uuid else {
                throw OWSAssertionError("Misisng address.uuid.")
            }
            let requestUuidString = UUID().uuidString
            let paymentRequestModel = TSPaymentRequestModel(requestUuidString: requestUuidString,
                                                            addressUuidString: addressUuid.uuidString,
                                                            isIncomingRequest: false,
                                                            paymentAmount: paymentAmount,
                                                            memoMessage: memoMessage,
                                                            createdDate: Date())
            paymentRequestModel.anyInsert(transaction: transaction)

            let thread = TSContactThread.getOrCreateThread(withContactAddress: address,
                                                           transaction: transaction)
            let paymentRequest = TSPaymentRequest(requestUuidString: requestUuidString,
                                                  paymentAmount: paymentAmount,
                                                  memoMessage: memoMessage)
            let message = OWSOutgoingPaymentMessage(thread: thread,
                                                    paymentCancellation: nil,
                                                    paymentNotification: nil,
                                                    paymentRequest: paymentRequest)
            Self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
            return message
        }
    }

    class func sendPaymentNotificationMessagePromise(address: SignalServiceAddress,
                                                     memoMessage: String?,
                                                     mcReceiptData: Data,
                                                     requestUuidString: String?) -> Promise<OWSOutgoingPaymentMessage> {
        databaseStorage.write(.promise) { transaction in
            self.sendPaymentNotificationMessage(address: address,
                                                memoMessage: memoMessage,
                                                mcReceiptData: mcReceiptData,
                                                requestUuidString: requestUuidString,
                                                transaction: transaction)
        }
    }

    class func sendPaymentNotificationMessage(address: SignalServiceAddress,
                                              memoMessage: String?,
                                              mcReceiptData: Data,
                                              requestUuidString: String?,
                                              transaction: SDSAnyWriteTransaction) -> OWSOutgoingPaymentMessage {
        let thread = TSContactThread.getOrCreateThread(withContactAddress: address,
                                                       transaction: transaction)
        let paymentNotification = TSPaymentNotification(memoMessage: memoMessage,
                                                        requestUuidString: requestUuidString,
                                                        mcReceiptData: mcReceiptData)
        let message = OWSOutgoingPaymentMessage(thread: thread,
                                                paymentCancellation: nil,
                                                paymentNotification: paymentNotification,
                                                paymentRequest: nil)
        Self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
        return message

    }

    class func sendPaymentCancellationMessagePromise(address: SignalServiceAddress,
                                                     requestUuidString: String) -> Promise<OWSOutgoingPaymentMessage> {
        return databaseStorage.write(.promise) { transaction in
            Self.sendPaymentCancellationMessage(address: address,
                                                requestUuidString: requestUuidString,
                                                transaction: transaction)
        }
    }

    class func sendPaymentCancellationMessage(address: SignalServiceAddress,
                                              requestUuidString: String,
                                              transaction: SDSAnyWriteTransaction) -> OWSOutgoingPaymentMessage {
        let thread = TSContactThread.getOrCreateThread(withContactAddress: address,
                                                       transaction: transaction)
        let paymentCancellation = TSPaymentCancellation(requestUuidString: requestUuidString)
        let message = OWSOutgoingPaymentMessage(thread: thread,
                                                paymentCancellation: paymentCancellation,
                                                paymentNotification: nil,
                                                paymentRequest: nil)
        Self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
        return message

    }

    class func sendOutgoingPaymentSyncMessage(recipientUuid: UUID?,
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
        let mobileCoin = OutgoingPaymentMobileCoin(recipientUuidString: recipientUuid?.uuidString,
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
        let message = OutgoingPaymentSyncMessage(thread: thread, mobileCoin: mobileCoin)
        Self.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
        return message
    }

    // MARK: - Incoming Messages

    func processIncomingPaymentRequest(thread: TSThread,
                                       paymentRequest: TSPaymentRequest,
                                       transaction: SDSAnyWriteTransaction) {
        // TODO: Handle requests.
        owsFailDebug("Not yet implemented.")
    }

    func processIncomingPaymentNotification(thread: TSThread,
                                            paymentNotification: TSPaymentNotification,
                                            senderAddress: SignalServiceAddress,
                                            transaction: SDSAnyWriteTransaction) {
        guard paymentNotification.isValid else {
            owsFailDebug("Invalid paymentNotification.")
            return
        }
        guard senderAddress.isValid else {
            owsFailDebug("Invalid senderAddress.")
            return
        }
        upsertPaymentModelForIncomingPaymentNotification(paymentNotification,
                                                         thread: thread,
                                                         senderAddress: senderAddress,
                                                         transaction: transaction)
    }

    func processIncomingPaymentCancellation(thread: TSThread,
                                            paymentCancellation: TSPaymentCancellation,
                                            transaction: SDSAnyWriteTransaction) {
        guard paymentCancellation.isValid else {
            owsFailDebug("Invalid paymentNotification.")
            return
        }
        let requestUuidString = paymentCancellation.requestUuidString
        guard let paymentRequestModel = Self.findPaymentRequestModel(forRequestUuidString: requestUuidString,
                                                                     expectedIsIncomingRequest: nil,
                                                                     transaction: transaction) else {
            // This isn't necessarily an error; we might receive multiple
            // cancellation messages for a given request.
            owsFailDebug("Missing paymentRequestModel.")
            return
        }
        paymentRequestModel.anyRemove(transaction: transaction)
    }

    func processReceivedTranscriptPaymentRequest(thread: TSThread,
                                                 paymentRequest: TSPaymentRequest,
                                                 messageTimestamp: UInt64,
                                                 transaction: SDSAnyWriteTransaction) {
        do {
            guard let contactThread = thread as? TSContactThread else {
                throw OWSAssertionError("Invalid thread.")
            }
            guard let contactUuid = contactThread.contactAddress.uuid else {
                throw OWSAssertionError("Missing contactUuid.")
            }
            let paymentRequestModel = TSPaymentRequestModel(requestUuidString: paymentRequest.requestUuidString,
                                                            addressUuidString: contactUuid.uuidString,
                                                            isIncomingRequest: false,
                                                            paymentAmount: paymentRequest.paymentAmount,
                                                            memoMessage: paymentRequest.memoMessage,
                                                            createdDate: NSDate.ows_date(withMillisecondsSince1970: messageTimestamp))
            guard paymentRequestModel.isValid else {
                throw OWSAssertionError("Invalid paymentRequestModel.")
            }
            paymentRequestModel.anyInsert(transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
            return
        }
    }

    func processReceivedTranscriptPaymentNotification(thread: TSThread,
                                                      paymentNotification: TSPaymentNotification,
                                                      messageTimestamp: UInt64,
                                                      transaction: SDSAnyWriteTransaction) {
        Logger.info("Ignoring payment notification from sync transcript.")
    }

    func processIncomingPaymentSyncMessage(_ paymentProto: SSKProtoSyncMessageOutgoingPayment,
                                           messageTimestamp: UInt64,
                                           transaction: SDSAnyWriteTransaction) {
        Logger.verbose("")
        do {
            guard let mobileCoinProto = paymentProto.mobileCoin else {
                throw OWSAssertionError("Invalid payment sync message: Missing mobileCoinProto.")
            }
            var recipientUuid: UUID?
            if let recipientUuidString = paymentProto.recipientUuid {
                guard let uuid = UUID(uuidString: recipientUuidString) else {
                    throw OWSAssertionError("Invalid payment sync message: Missing recipientUuid.")
                }
                recipientUuid = uuid
            }
            let paymentAmount = TSPaymentAmount(currency: .mobileCoin, picoMob: mobileCoinProto.amountPicoMob)
            guard paymentAmount.isValidAmount(canBeEmpty: true) else {
                throw OWSAssertionError("Invalid payment sync message: invalid paymentAmount.")
            }
            let feeAmount = TSPaymentAmount(currency: .mobileCoin, picoMob: mobileCoinProto.feePicoMob)
            guard feeAmount.isValidAmount(canBeEmpty: false) else {
                throw OWSAssertionError("Invalid payment sync message: invalid feeAmount.")
            }
            let recipientPublicAddressData = mobileCoinProto.recipientAddress
            let memoMessage = paymentProto.note?.nilIfEmpty
            let spentKeyImages = Array(Set(mobileCoinProto.spentKeyImages))
            owsAssertDebug(spentKeyImages.count == mobileCoinProto.spentKeyImages.count)
            guard !spentKeyImages.isEmpty else {
                throw OWSAssertionError("Invalid payment sync message: Missing spentKeyImages.")
            }
            let outputPublicKeys = Array(Set(mobileCoinProto.outputPublicKeys))
            owsAssertDebug(outputPublicKeys.count == mobileCoinProto.outputPublicKeys.count)
            guard !outputPublicKeys.isEmpty else {
                throw OWSAssertionError("Invalid payment sync message: Missing outputPublicKeys.")
            }
            guard let mcReceiptData = mobileCoinProto.receipt,
                  !mcReceiptData.isEmpty,
                  nil != MobileCoin.Receipt(serializedData: mcReceiptData) else {
                throw OWSAssertionError("Invalid payment sync message: Missing or invalid receipt.")
            }
            let ledgerBlockIndex = mobileCoinProto.ledgerBlockIndex
            guard ledgerBlockIndex > 0 else {
                throw OWSAssertionError("Invalid payment sync message: Invalid ledgerBlockIndex.")
            }
            let ledgerBlockTimestamp = mobileCoinProto.ledgerBlockTimestamp
            // TODO: Support requests.
            let requestUuidString: String? = nil
            // We use .outgoingComplete. We can safely assume that the device which
            // sent the payment has verified and notified.
            let paymentState: TSPaymentState = .outgoingComplete

            let paymentType: TSPaymentType
            if recipientPublicAddressData == nil {
                // Possible defragmentation.
                guard recipientUuid == nil else {
                    throw OWSAssertionError("Invalid payment sync message: unexpected recipientUuid.")
                }
                guard recipientPublicAddressData == nil else {
                    throw OWSAssertionError("Invalid payment sync message: unexpected recipientPublicAddressData.")
                }
                guard paymentAmount.isValidAmount(canBeEmpty: true),
                      paymentAmount.picoMob == 0 else {
                    throw OWSAssertionError("Invalid payment sync message: invalid paymentAmount.")
                }
                guard memoMessage == nil else {
                    throw OWSAssertionError("Invalid payment sync message: unexpected memoMessage.")
                }
                paymentType = .outgoingDefragmentationFromLinkedDevice
            } else {
                // Possible outgoing payment.
                guard recipientUuid != nil else {
                    throw OWSAssertionError("Invalid payment sync message: missing recipientUuid.")
                }
                guard paymentAmount.isValidAmount(canBeEmpty: false) else {
                    throw OWSAssertionError("Invalid payment sync message: invalid paymentAmount.")
                }
                paymentType = .outgoingPaymentFromLinkedDevice
            }

            let mobileCoin = MobileCoinPayment(recipientPublicAddressData: recipientPublicAddressData,
                                               transactionData: nil,
                                               receiptData: mcReceiptData,
                                               incomingTransactionPublicKeys: nil,
                                               spentKeyImages: spentKeyImages,
                                               outputPublicKeys: outputPublicKeys,
                                               ledgerBlockTimestamp: ledgerBlockTimestamp,
                                               ledgerBlockIndex: ledgerBlockIndex,
                                               feeAmount: feeAmount)
            let paymentModel = TSPaymentModel(paymentType: paymentType,
                                              paymentState: paymentState,
                                              paymentAmount: paymentAmount,
                                              createdDate: NSDate.ows_date(withMillisecondsSince1970: messageTimestamp),
                                              addressUuidString: recipientUuid?.uuidString,
                                              memoMessage: memoMessage,
                                              requestUuidString: requestUuidString,
                                              isUnread: false,
                                              mobileCoin: mobileCoin)

            try tryToInsertPaymentModel(paymentModel, transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
            return
        }
    }

    // This method enforces invariants around TSPaymentModel.
    func tryToInsertPaymentModel(_ paymentModel: TSPaymentModel,
                                 transaction: SDSAnyWriteTransaction) throws {

        Logger.info("Trying to insert: \(paymentModel.descriptionForLogs)")

        guard paymentModel.isValid else {
            throw OWSAssertionError("Invalid paymentModel.")
        }

        let isRedundant = try isProposedPaymentModelRedundant(paymentModel,
                                                              transaction: transaction)
        guard !isRedundant else {
            throw OWSAssertionError("Duplicate paymentModel.")
        }

        paymentModel.anyInsert(transaction: transaction)

        if paymentModel.isOutgoing,
           paymentModel.isIdentifiedPayment,
           let requestUuidString = paymentModel.requestUuidString,
           let paymentRequestModel = Self.findPaymentRequestModel(forRequestUuidString: requestUuidString,
                                                                  expectedIsIncomingRequest: true,
                                                                  transaction: transaction) {
            paymentRequestModel.anyRemove(transaction: transaction)
        }
    }

    // This method enforces invariants around TSPaymentModel.
    private func isProposedPaymentModelRedundant(_ paymentModel: TSPaymentModel,
                                                 transaction: SDSAnyWriteTransaction) throws -> Bool {
        guard paymentModel.isValid else {
            throw OWSAssertionError("Invalid paymentModel.")
        }

        // Only one model in the database should have a given transaction.
        if paymentModel.canHaveMCTransaction {
            if let transactionData = paymentModel.mobileCoin?.transactionData {
                let existingPaymentModels = PaymentFinder.paymentModels(forMcTransactionData: transactionData,
                                                                        transaction: transaction)
                if existingPaymentModels.count > 1 {
                    owsFailDebug("More than one conflict.")
                }
                if !existingPaymentModels.isEmpty {
                    owsFailDebug("Transaction conflict.")
                    return true
                }
            } else if paymentModel.shouldHaveMCTransaction {
                throw OWSAssertionError("Missing transactionData.")
            }
        }

        // Only one model in the database should have a given receipt.
        if paymentModel.shouldHaveMCReceipt {
            if let receiptData = paymentModel.mobileCoin?.receiptData {
                let existingPaymentModels = PaymentFinder.paymentModels(forMcReceiptData: receiptData,
                                                                        transaction: transaction)
                if existingPaymentModels.count > 1 {
                    owsFailDebug("More than one conflict.")
                }
                if !existingPaymentModels.isEmpty {
                    owsFailDebug("Receipt conflict.")
                    return true
                }
            } else {
                throw OWSAssertionError("Missing receiptData.")
            }
        }

        // Only one _identified_ payment model in the database should correspond to any given
        // spentKeyImage or outputPublicKey.
        //
        // We don't need to worry about conflicts with unidentified payment models;
        // PaymentsReconciliation will avoid / clean those up.
        let mcLedgerBlockIndex = paymentModel.mobileCoin?.ledgerBlockIndex ?? 0
        let spentKeyImages = Set(paymentModel.mobileCoin?.spentKeyImages ?? [])
        let outputPublicKeys = Set(paymentModel.mobileCoin?.outputPublicKeys ?? [])
        if !paymentModel.isUnidentified,
           mcLedgerBlockIndex > 0 {

            let otherPaymentModels = PaymentFinder.paymentModels(forMcLedgerBlockIndex: mcLedgerBlockIndex,
                                                                 transaction: transaction)
            for otherPaymentModel in otherPaymentModels {
                guard !otherPaymentModel.isUnidentified else {
                    continue
                }
                guard paymentModel.uniqueId != otherPaymentModel.uniqueId else {
                    owsFailDebug("Duplicate paymentModel.")
                    return true
                }
                let otherSpentKeyImages = Set(otherPaymentModel.mobileCoin?.spentKeyImages ?? [])
                let otherOutputPublicKeys = Set(otherPaymentModel.mobileCoin?.outputPublicKeys ?? [])
                if !spentKeyImages.intersection(otherSpentKeyImages).isEmpty {
                    for value in spentKeyImages {
                        Logger.verbose("spentKeyImage: \(value.hexadecimalString)")
                    }
                    for value in otherSpentKeyImages {
                        Logger.verbose("otherSpentKeyImage: \(value.hexadecimalString)")
                    }
                    owsFailDebug("spentKeyImage conflict.")
                    return true
                }
                if !outputPublicKeys.intersection(otherOutputPublicKeys).isEmpty {
                    for value in outputPublicKeys {
                        Logger.verbose("outputPublicKey: \(value.hexadecimalString)")
                    }
                    for value in otherOutputPublicKeys {
                        Logger.verbose("otherOutputPublicKey: \(value.hexadecimalString)")
                    }
                    owsFailDebug("outputPublicKey conflict.")
                    return true
                }
            }
        }

        return false
    }

    func processReceivedTranscriptPaymentCancellation(thread: TSThread,
                                                      paymentCancellation: TSPaymentCancellation,
                                                      messageTimestamp: UInt64,
                                                      transaction: SDSAnyWriteTransaction) {
        let requestUuidString = paymentCancellation.requestUuidString
        if let paymentRequestModel = Self.findPaymentRequestModel(forRequestUuidString: requestUuidString,
                                                                  expectedIsIncomingRequest: nil,
                                                                  transaction: transaction) {
            paymentRequestModel.anyRemove(transaction: transaction)
        }
    }
}

// MARK: - Formatting

public extension PaymentsImpl {
    func willInsertPayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction) {
        paymentsReconciliation.willInsertPayment(paymentModel, transaction: transaction)

        // If we're inserting a new payment of any kind, our balance may have changed.
        updateCurrentPaymentBalance()
    }

    func willUpdatePayment(_ paymentModel: TSPaymentModel, transaction: SDSAnyWriteTransaction) {
        paymentsReconciliation.willUpdatePayment(paymentModel, transaction: transaction)
    }

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
    fileprivate let recipientAddress: SignalServiceAddress?
    fileprivate let recipientPublicAddress: MobileCoin.PublicAddress
    fileprivate let paymentAmount: TSPaymentAmount
    fileprivate let memoMessage: String?
    fileprivate let paymentRequestModel: TSPaymentRequestModel?
    fileprivate let isOutgoingTransfer: Bool
    fileprivate let preparedTransaction: MobileCoinAPI.PreparedTransaction
}
