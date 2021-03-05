//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import MobileCoin

@objc
public class PaymentsImpl: NSObject, PaymentsSwift {

    // MARK: - Dependencies

    private static var identityManager: OWSIdentityManager {
        SSKEnvironment.shared.identityManager
    }

    private static var databaseStorage: SDSDatabaseStorage {
        SDSDatabaseStorage.shared
    }

    private static var profileManager: OWSProfileManager {
        .shared()
    }

    private static var tsAccountManager: TSAccountManager {
        TSAccountManager.shared()
    }

    private static var messageSenderJobQueue: MessageSenderJobQueue {
        SSKEnvironment.shared.messageSenderJobQueue
    }

    private static var storageCoordinator: StorageCoordinator {
        SSKEnvironment.shared.storageCoordinator
    }

    private static var storageServiceManager: StorageServiceManagerProtocol {
        SSKEnvironment.shared.storageServiceManager
    }

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

        // TODO: Remove
        if DebugFlags.paymentsInternalBeta,
           CurrentAppContext().isMainApp,
           !CurrentAppContext().isRunningTests {
            AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
                Self.storageServiceManager.recordPendingLocalAccountUpdates()
                Self.profileManager.reuploadLocalProfile()
            }
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
        Self.unfairLock.withLock {
            currentApiHandle = nil
        }
    }

    private func getOrBuildCurrentApi(mcRootEntropy: Data) -> Promise<MobileCoinAPI> {
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
            MobileCoinAPI.buildPromise(localRootEntropy: mcRootEntropy)
        }.map(on: .global()) { (api: MobileCoinAPI) -> MobileCoinAPI in
            setCurrentApi(api)
            return api
        }
    }

    // Instances of MobileCoinAPI are slightly expensive to
    // build since we need to obtain authentication from
    // the service, so we cache and reuse instances.
    func getMobileCoinAPI() -> Promise<MobileCoinAPI> {
        switch paymentsState {
        case .enabled(let mcRootEntropy):
            return getOrBuildCurrentApi(mcRootEntropy: mcRootEntropy)
        case .disabled, .disabledWithMCRootEntropy:
            return Promise(error: PaymentsError.notEnabled)
        }
    }

    public var canEnablePayments: Bool {
        guard FeatureFlags.payments else {
            return false
        }
        guard Self.tsAccountManager.isRegisteredAndReady else {
            return false
        }
        if DebugFlags.paymentsAllowAllCountries {
            return true
        }
        // TODO: Test.
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
        let callingCodePartsOfUK: Int = 44
        let validCallingCodes = [ callingCodePartsOfUK ]
        return validCallingCodes.contains(nsCountryCode.intValue)
    }

    public var shouldShowPaymentsUI: Bool {
        arePaymentsEnabled || canEnablePayments
    }

    // MARK: - PaymentsState

    private static let arePaymentsEnabledKey = "isPaymentEnabled"
    private static let mcRootEntropyKey = "rootEntropyBytes"

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

    public var mcRootEntropy: Data? {
        paymentsState.mcRootEntropy
    }

    public func setPaymentsState(_ paymentsState: PaymentsState, transaction: SDSAnyWriteTransaction) {
        guard paymentsState.isEnabled || canEnablePayments else {
            owsFailDebug("Payments cannot be enabled.")
            return
        }
        guard paymentsState != self.paymentsState else {
            Logger.verbose("Ignoring redundant change.")
            return
        }

        Self.keyValueStore.setBool(paymentsState.isEnabled,
                                   key: Self.arePaymentsEnabledKey,
                                   transaction: transaction)
        if let mcRootEntropy = paymentsState.mcRootEntropy {
            Self.keyValueStore.setData(mcRootEntropy,
                                       key: Self.mcRootEntropyKey,
                                       transaction: transaction)
        }

        self.paymentStateCache.set(paymentsState)

        transaction.addAsyncCompletion {
            NotificationCenter.default.postNotificationNameAsync(Self.arePaymentsEnabledDidChange, object: nil)

            self.updateCurrentPaymentBalance()

            Self.profileManager.reuploadLocalProfile()

            Self.storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    private static func loadPaymentsState(transaction: SDSAnyReadTransaction) -> PaymentsState {
        guard FeatureFlags.payments else {
            return .disabled
        }
        func loadMCRootEntropy() -> Data? {
            guard storageCoordinator.isStorageReady else {
                owsFailDebug("Storage is not ready.")
                return nil
            }
            guard tsAccountManager.isRegisteredAndReady else {
                return nil
            }
            if DevFlags.useFakeRootEntropy_self,
               let localAddress = tsAccountManager.localAddress,
               hasFakeRootEntropy(forAddress: localAddress) {
                return fakeRootEntropy(forAddress: localAddress)
            } else {
                return keyValueStore.getData(mcRootEntropyKey, transaction: transaction)
            }
        }

        guard let mcRootEntropy = loadMCRootEntropy() else {
            return .disabled
        }
        let isEnabled = keyValueStore.getBool(Self.arePaymentsEnabledKey,
                                              defaultValue: false,
                                              transaction: transaction)
        if isEnabled {
            return .enabled(mcRootEntropy: mcRootEntropy)
        } else {
            return .disabledWithMCRootEntropy(mcRootEntropy: mcRootEntropy)
        }
    }

    public func generateRandomMobileCoinRootEntropy() -> Data {
        // PAYMENTS TODO: Confirm this is correct.
        Cryptography.generateRandomBytes(MobileCoinAPI.rootEntropyLength)
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
        return paymentBalanceCache.get()
    }

    private func setCurrentPaymentBalance(amount: TSPaymentAmount) {
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

        NotificationCenter.default.postNotificationNameAsync(Self.currentPaymentBalanceDidChange, object: nil)
    }

    // We need to update our balance:
    //
    // * On launch.
    // * Periodically.
    // * After making or receiving payments.
    // * When user navigates into a view that displays the balance.
    public func updateCurrentPaymentBalance() {
        guard FeatureFlags.payments,
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

    // MARK: - Operations

    // PAYMENTS TODO:
    private enum DevFlags {
        static var useFakeRootEntropy_self: Bool {
            //            return false
            //            return true
            #if DEBUG
            return (MobileCoinAPI.Environment.current == .mobileCoinAlphaNet ||
                        MobileCoinAPI.Environment.current == .mobileCoinMobileDev)

            #else
            return false
            #endif
        }
    }

    // TODO: Remove.
    private struct DevDevice {
        fileprivate let address: SignalServiceAddress
        fileprivate let fakeRootEntropy: Data

        init(phoneNumber: String, fakeRootEntropy: Data) throws {
            self.address = SignalServiceAddress(phoneNumber: phoneNumber)
            self.fakeRootEntropy = fakeRootEntropy
        }
    }

    private class var fakeDevDevices: [DevDevice] {
        return [
            // iPhone 11 Pro Max Simulator
            try! DevDevice(phoneNumber: "+441752395464",
                           fakeRootEntropy: MobileCoinAPI.rootEntropy1),

            // iPhone Xs Simulator
            try! DevDevice(phoneNumber: "+14503002620",
                           fakeRootEntropy: MobileCoinAPI.rootEntropy2),

            // iPhone Xr Simulator
            try! DevDevice(phoneNumber: "+13602090656",
                           fakeRootEntropy: MobileCoinAPI.rootEntropy3),

            // iPhone XS Max Device
            try! DevDevice(phoneNumber: "+12262864592",
                           fakeRootEntropy: MobileCoinAPI.rootEntropy4),

            // iPhone 12 mini Device
            try! DevDevice(phoneNumber: "+12534877762",
                           fakeRootEntropy: MobileCoinAPI.rootEntropy5),

            // iPhone 11 Pro Simulator
            try! DevDevice(phoneNumber: "+15092608677",
                           fakeRootEntropy: MobileCoinAPI.rootEntropy6)
        ]
    }

    private class func fakeRootEntropy(forAddress address: SignalServiceAddress) -> Data {
        let device = fakeDevDevices.filter { $0.address == address }.first!
        return device.fakeRootEntropy
    }

    private class func hasFakeRootEntropy(forAddress address: SignalServiceAddress) -> Bool {
        !fakeDevDevices.filter { $0.address == address }.isEmpty
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
                                              memoMessage: paymentNotification.memoMessage,
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
        firstly(on: .global()) {
            guard recipientAddress != nil else {
                throw OWSAssertionError("Missing recipient.")
            }
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

            let mobileCoin = MobileCoinPayment(recipientPublicAddressData: recipientPublicAddressData,
                                               transactionData: mcTransactionData,
                                               receiptData: mcReceiptData,
                                               incomingTransactionPublicKeys: nil,
                                               spentKeyImages: Array(transaction.inputKeyImages),
                                               outputPublicKeys: Array(transaction.outputPublicKeys),
                                               ledgerBlockTimestamp: 0,
                                               ledgerBlockIndex: 0,
                                               feeAmount: feeAmount)

            let paymentModel = TSPaymentModel(paymentType: paymentType,
                                              paymentState: .outgoingUnsubmitted,
                                              paymentAmount: paymentAmount,
                                              createdDate: Date(),
                                              addressUuidString: addressUuidString,
                                              memoMessage: memoMessage,
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
        guard let mcRootEntropy = paymentsState.mcRootEntropy else {
            owsFailDebug("Missing mcRootEntropy.")
            return nil
        }

        do {
            return try MobileCoinAPI.buildLocalAccount(localRootEntropy: mcRootEntropy)
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
        guard FeatureFlags.payments,
              arePaymentsEnabled else {
            return Promise(error: PaymentsError.notEnabled)
        }

        return firstly { () -> Promise<MobileCoinAPI> in
            self.getMobileCoinAPI()
        }.then(on: .global()) { (mobileCoinAPI: MobileCoinAPI) in
            return mobileCoinAPI.getLocalBalance()
        }
    }
}

// MARK: - PaymentTransaction

public extension PaymentsImpl {

    func getEstimatedFee(forPaymentAmount paymentAmount: TSPaymentAmount) -> Promise<TSPaymentAmount> {

        guard FeatureFlags.payments,
              arePaymentsEnabled else {
            return Promise(error: PaymentsError.notEnabled)
        }
        guard paymentAmount.currency == .mobileCoin else {
            return Promise(error: OWSAssertionError("Invalid currency."))
        }

        return firstly(on: .global()) { () -> Promise<MobileCoinAPI> in
            self.getMobileCoinAPI()
        }.then(on: .global()) { (mobileCoinAPI: MobileCoinAPI) -> Promise<TSPaymentAmount> in
            mobileCoinAPI.getEstimatedFee(forPaymentAmount: paymentAmount)
        }
    }

    func submitPaymentTransaction(recipient: SendPaymentRecipient,
                                  paymentAmount: TSPaymentAmount,
                                  memoMessage: String?,
                                  paymentRequestModel: TSPaymentRequestModel?,
                                  isOutgoingTransfer: Bool) -> Promise<TSPaymentModel> {

        guard let recipient = recipient as? SendPaymentRecipientImpl else {
            return Promise(error: OWSAssertionError("Invalid recipient."))
        }

        switch recipient {
        case .address(let recipientAddress):
            return firstly(on: .global()) { () -> Promise<MobileCoin.PublicAddress> in
                self.fetchPublicAddress(forAddress: recipientAddress)
            }.then(on: .global()) { (recipientPublicAddress: MobileCoin.PublicAddress) -> Promise<TSPaymentModel> in
                self.submitPaymentTransaction(recipientAddress: recipientAddress,
                                              recipientPublicAddress: recipientPublicAddress,
                                              paymentAmount: paymentAmount,
                                              memoMessage: memoMessage,
                                              paymentRequestModel: paymentRequestModel,
                                              isOutgoingTransfer: isOutgoingTransfer)
            }
        case .publicAddress(let recipientPublicAddress):
            return submitPaymentTransaction(recipientAddress: nil,
                                            recipientPublicAddress: recipientPublicAddress,
                                            paymentAmount: paymentAmount,
                                            memoMessage: memoMessage,
                                            paymentRequestModel: paymentRequestModel,
                                            isOutgoingTransfer: isOutgoingTransfer)
        }
    }

    private func submitPaymentTransaction(recipientAddress: SignalServiceAddress?,
                                          recipientPublicAddress: MobileCoin.PublicAddress,
                                          paymentAmount: TSPaymentAmount,
                                          memoMessage: String?,
                                          paymentRequestModel: TSPaymentRequestModel?,
                                          isOutgoingTransfer: Bool) -> Promise<TSPaymentModel> {

        guard FeatureFlags.payments,
              arePaymentsEnabled else {
            return Promise(error: PaymentsError.notEnabled)
        }
        guard paymentAmount.currency == .mobileCoin else {
            return Promise(error: OWSAssertionError("Invalid currency."))
        }
        guard recipientAddress != Self.tsAccountManager.localAddress else {
            return Promise(error: OWSAssertionError("Can't make payment to yourself."))
        }

        return firstly(on: .global()) { () -> Promise<MobileCoinAPI> in
            self.getMobileCoinAPI()
        }.then(on: .global()) { (mobileCoinAPI: MobileCoinAPI) -> Promise<MobileCoinAPI.PreparedTransaction> in
            mobileCoinAPI.prepareTransaction(paymentAmount: paymentAmount,
                                             recipientPublicAddress: recipientPublicAddress)
        }.then(on: .global()) { (preparedTransaction: MobileCoinAPI.PreparedTransaction) -> Promise<TSPaymentModel> in
            // To initiate the outgoing payment, all we need to do is save
            // the TSPaymentModel to the database. The PaymentsProcessor
            // will observe this and take responsibility for the submission,
            // verification and notification of the payment.
            //
            // TODO: Handle requests.
            self.upsertNewOutgoingPaymentModel(recipientAddress: recipientAddress,
                                               recipientPublicAddress: recipientPublicAddress,
                                               paymentAmount: paymentAmount,
                                               feeAmount: preparedTransaction.feeAmount,
                                               memoMessage: memoMessage,
                                               transaction: preparedTransaction.transaction,
                                               receipt: preparedTransaction.receipt,
                                               paymentRequestModel: paymentRequestModel,
                                               isOutgoingTransfer: isOutgoingTransfer)
        }
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
              !mcReceiptData.isEmpty else {
            if DebugFlags.paymentsIgnoreBadData.get() {
                Logger.warn("Missing mcReceiptData.")
            } else {
                owsFailDebug("Missing mcReceiptData.")
            }
            return
        }
        guard let mcTransactionData = paymentModel.mcTransactionData,
              !mcTransactionData.isEmpty else {
            if DebugFlags.paymentsIgnoreBadData.get() {
                Logger.warn("Missing mcTransactionData.")
            } else {
                owsFailDebug("Missing mcTransactionData.")
            }
            return
        }
        _ = sendOutgoingPaymentSyncMessage(recipientUuid: recipientUuid,
                                           recipientAddress: recipientAddress,
                                           paymentAmount: paymentAmount,
                                           feeAmount: feeAmount,
                                           mcReceiptData: mcReceiptData,
                                           mcTransactionData: mcTransactionData,
                                           mcLedgerBlockTimestamp: paymentModel.mcLedgerBlockTimestamp,
                                           mcLedgerBlockIndex: paymentModel.mcLedgerBlockIndex,
                                           memoMessage: paymentModel.memoMessage,
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

    class func sendOutgoingPaymentSyncMessage(recipientUuid: UUID,
                                              recipientAddress: Data,
                                              paymentAmount: TSPaymentAmount,
                                              feeAmount: TSPaymentAmount,
                                              mcReceiptData: Data,
                                              mcTransactionData: Data,
                                              mcLedgerBlockTimestamp: UInt64?,
                                              mcLedgerBlockIndex: UInt64?,
                                              memoMessage: String?,
                                              transaction: SDSAnyWriteTransaction) -> TSOutgoingMessage? {

        guard let thread = TSAccountManager.getOrCreateLocalThread(transaction: transaction) else {
            owsFailDebug("Missing local thread.")
            return nil
        }
        let mobileCoin = OutgoingPaymentMobileCoin(recipientUuidString: recipientUuid.uuidString,
                                                   recipientAddress: recipientAddress,
                                                   amountPicoMob: paymentAmount.picoMob,
                                                   feePicoMob: feeAmount.picoMob,
                                                   receiptData: mcReceiptData,
                                                   transactionData: mcTransactionData,
                                                   blockIndex: mcLedgerBlockIndex ?? 0,
                                                   blockTimestamp: mcLedgerBlockTimestamp ?? 0,
                                                   memoMessage: memoMessage)

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
        do {
            // TODO: Handle defrag.
            guard let mobileCoinProto = paymentProto.mobileCoin else {
                Logger.warn("Missing mobileCoinProto.")
                return
            }
            let recipientUuidString = paymentProto.recipientUuid
            guard let recipientUuid = UUID(uuidString: recipientUuidString) else {
                throw OWSAssertionError("Missing recipientUuid.")
            }
            let paymentAmount = TSPaymentAmount(currency: .mobileCoin, picoMob: mobileCoinProto.amountPicoMob)
            guard paymentAmount.isValidAmount(canBeEmpty: false) else {
                throw OWSAssertionError("Invalid paymentAmount.")
            }
            let feeAmount = TSPaymentAmount(currency: .mobileCoin, picoMob: mobileCoinProto.feePicoMob)
            guard feeAmount.isValidAmount(canBeEmpty: false) else {
                throw OWSAssertionError("Invalid feeAmount.")
            }
            // TODO: Require this?
            let recipientPublicAddressData = mobileCoinProto.recipientAddress
            let memoMessage = paymentProto.note
            let receiptData = mobileCoinProto.receipt
            // Verify that the reciept can be parsed.
            guard nil != MobileCoin.Receipt(serializedData: receiptData) else {
                throw OWSAssertionError("Invalid receipt.")
            }
            let transactionData = mobileCoinProto.transaction
            guard let mcTransaction = MobileCoin.Transaction(serializedData: transactionData) else {
                throw OWSAssertionError("Invalid transaction.")
            }
            let spentKeyImages = Array(mcTransaction.inputKeyImages)
            guard !spentKeyImages.isEmpty else {
                throw OWSAssertionError("Missing spentKeyImages.")
            }
            let outputPublicKeys = Array(mcTransaction.outputPublicKeys)
            guard !outputPublicKeys.isEmpty else {
                throw OWSAssertionError("Missing outputPublicKeys.")
            }
            let ledgerBlockIndex = mobileCoinProto.ledgerBlockIndex
            guard ledgerBlockIndex > 0 else {
                throw OWSAssertionError("Missing ledgerBlockIndex.")
            }
            let ledgerBlockTimestamp = mobileCoinProto.ledgerBlockTimestamp
            // TODO: Support requests.
            let requestUuidString: String? = nil
            let mobileCoin = MobileCoinPayment(recipientPublicAddressData: recipientPublicAddressData,
                                               transactionData: transactionData,
                                               receiptData: receiptData,
                                               incomingTransactionPublicKeys: nil,
                                               spentKeyImages: spentKeyImages,
                                               outputPublicKeys: outputPublicKeys,
                                               ledgerBlockTimestamp: ledgerBlockTimestamp,
                                               ledgerBlockIndex: ledgerBlockIndex,
                                               feeAmount: feeAmount)
            let hasLedgerBlockTimestamp = ledgerBlockTimestamp > 0
            let paymentState: TSPaymentState = (hasLedgerBlockTimestamp
                                                    ? .outgoingMissingLedgerTimestamp
                                                    : .outgoingComplete)

            // We use .outgoingSent, we're assuming that the linked device which
            // sent the payment has verified and notified.
            let paymentModel = TSPaymentModel(paymentType: .outgoingPayment,
                                              paymentState: paymentState,
                                              paymentAmount: paymentAmount,
                                              createdDate: NSDate.ows_date(withMillisecondsSince1970: messageTimestamp),
                                              addressUuidString: recipientUuid.uuidString,
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

        guard paymentModel.isValid else {
            throw OWSAssertionError("Invalid paymentModel.")
        }

        if paymentModel.isOutgoing,
           paymentModel.isIdentifiedPayment {
            if let transactionData = paymentModel.mobileCoin?.transactionData {
                let existingPaymentModels = PaymentFinder.paymentModels(forMcTransactionData: transactionData,
                                                                        transaction: transaction)
                if existingPaymentModels.count > 1 {
                    owsFailDebug("More than one conflict.")
                }
                if !existingPaymentModels.isEmpty {
                    throw OWSAssertionError("Duplicate paymentModel.")
                }
            } else {
                throw OWSAssertionError("Missing transactionData.")
            }
        }

        if paymentModel.isIncoming,
           paymentModel.isIdentifiedPayment {
            if let receiptData = paymentModel.mobileCoin?.receiptData {
                let existingPaymentModels = PaymentFinder.paymentModels(forMcReceiptData: receiptData,
                                                                        transaction: transaction)
                if existingPaymentModels.count > 1 {
                    owsFailDebug("More than one conflict.")
                }
                if !existingPaymentModels.isEmpty {
                    throw OWSAssertionError("Duplicate paymentModel.")
                }
            } else {
                throw OWSAssertionError("Missing receiptData.")
            }
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
        // TODO: Replace with SDK method when available.
        return Base58Coder.encode(publicAddress)
    }

    static func formatAsUrl(publicAddress: MobileCoin.PublicAddress) -> String {
        // http://mobilecoin.com/mob58/b58PayloadString
        //
        // TODO: Replace with SDK method when available.
        let base58 = formatAsBase58(publicAddress: publicAddress)
        return "http://mobilecoin.com/mob58/" + base58
    }

    static func parse(publicAddressUrl url: URL) -> MobileCoin.PublicAddress? {
        // http://mobilecoin.com/mob58/b58PayloadString
        //
        // TODO: Replace with SDK method when available.
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            Logger.verbose("Invalid url scheme: \(url)")
            Logger.warn("Invalid url scheme.")
            return nil
        }
        guard let host = url.host?.lowercased(),
              host == "mobilecoin.com" else {
            Logger.verbose("Invalid url host: \(url)")
            Logger.warn("Invalid url host.")
            return nil
        }
        let pathPrefix = "/mob58/"
        guard url.path.starts(with: pathPrefix) else {
            Logger.verbose("Invalid url path: \(url)")
            Logger.warn("Invalid url path.")
            return nil
        }
        let base58 = String(url.path.suffix(pathPrefix.count))
        return parse(publicAddressBase58: base58)
    }

    static func parse(publicAddressBase58 base58: String) -> MobileCoin.PublicAddress? {
        // TODO: Replace with SDK method when available.
        guard let result = Base58Coder.decode(base58) else {
            Logger.verbose("Invalid base58: \(base58)")
            Logger.warn("Invalid base58.")
            return nil
        }
        switch result {
        case .publicAddress(let publicAddress):
            return publicAddress
        default:
            Logger.verbose("Invalid base58: \(base58)")
            Logger.warn("Invalid base58.")
            return nil
        }
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
}

// MARK: -

public extension PaymentsImpl {
    static var currencyAbbreviationMobileCoin: String {
        PaymentsConstants.mobileCoinCurrencyIdentifier
    }

    // Used for formatting MOB (not picoMob) values for display.
    private static var mobFormat: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = Locale(identifier: "en_US")
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumIntegerDigits = 1
        numberFormatter.minimumFractionDigits = 1
        numberFormatter.maximumFractionDigits = 4
        numberFormatter.usesSignificantDigits = false
        return numberFormatter
    }()

    // Used for formatting decimal numbers in the
    // send payment flow.  _NOT_ used for display.
    // The format is convenient to parse into an "input string"
    // the correponds to our custom keyboard.
    private static var doubleFormat: NumberFormatter = {
        // For formatting numbers as arabic numerals without
        // any commas, etc. 1234567.890123
        let numberFormatter = NumberFormatter()
        numberFormatter.locale = Locale(identifier: "en_US")
        // Hide commas.
        numberFormatter.groupingSeparator = ""
        numberFormatter.numberStyle = .decimal
        return numberFormatter
    }()

    static func format(paymentAmount: TSPaymentAmount,
                       withCurrencyCode: Bool = false,
                       withSpace: Bool = false,
                       withPaymentType paymentType: TSPaymentType? = nil) -> String {
        guard paymentAmount.currency == .mobileCoin else {
            owsFailDebug("Unknown currency.")
            return NSLocalizedString("PAYMENTS_CURRENCY_UNKNOWN",
                                     comment: "Indicator for unknown currency.")
        }
        guard let amountString = format(picoMob: paymentAmount.picoMob) else {
            owsFailDebug("Couldn't format currency.")
            return NSLocalizedString("PAYMENTS_CURRENCY_UNKNOWN",
                                     comment: "Indicator for unknown currency.")
        }

        var result = ""

        if let paymentType = paymentType {
            result += paymentType.isIncoming ? "+" : "-"
        }

        result += amountString

        if withCurrencyCode {
            if withSpace {
                result += " "
            }
            result += PaymentsConstants.mobileCoinCurrencyIdentifier
        }
        return result
    }

    static func formatOrError(picoMob: UInt64) -> String {
        guard let string = format(picoMob: picoMob) else {
            owsFailDebug("Couldn't format currency.")
            return NSLocalizedString("PAYMENTS_CURRENCY_UNKNOWN",
                                     comment: "Indicator for unknown currency.")
        }
        return string
    }

    static func format(mob: Double) -> String? {
        format(picoMob: PaymentsConstants.convertMobToPicoMob(mob))
    }

    static func format(picoMob: UInt64) -> String? {
        let mob = PaymentsConstants.convertPicoMobToMob(picoMob)
        guard let result = mobFormat.string(from: NSNumber(value: mob)) else {
            owsFailDebug("Couldn't format currency.")
            return nil
        }
        return result
    }

    static func formatAsDoubleString(picoMob: UInt64) -> String? {
        formatAsDoubleString(PaymentsConstants.convertPicoMobToMob(picoMob))
    }

    static func formatAsDoubleString(_ value: Double) -> String? {
        guard let result = doubleFormat.string(from: NSNumber(value: value)) else {
            owsFailDebug("Couldn't format double.")
            return nil
        }
        return result
    }

    static func attributedFormat(paymentAmount: TSPaymentAmount,
                                 paymentType: TSPaymentType? = nil,
                                 withSpace: Bool = false) -> NSAttributedString {
        guard paymentAmount.currency == .mobileCoin else {
            owsFailDebug("Unknown currency.")
            return NSAttributedString(string: NSLocalizedString("PAYMENTS_CURRENCY_UNKNOWN",
                                                                comment: "Indicator for unknown currency."))
        }

        return attributedFormat(mobileCoinString: format(paymentAmount: paymentAmount,
                                                         withPaymentType: paymentType),
                                withSpace: withSpace)
    }

    static func attributedFormat(mobileCoinString: String,
                                 withSpace: Bool = false) -> NSAttributedString {
        attributedFormat(currencyString: mobileCoinString,
                         currencyCode: currencyAbbreviationMobileCoin,
                         withSpace: withSpace)
    }

    static func attributedFormat(fiatCurrencyAmount: Double,
                                 currencyCode: String,
                                 withSpace: Bool = false) -> NSAttributedString? {
        guard let currencyString = format(fiatCurrencyAmount: fiatCurrencyAmount) else {
            owsFailDebug("Invalid fiatCurrencyAmount.")
            return nil
        }
        return attributedFormat(currencyString: currencyString,
                                currencyCode: currencyCode,
                                withSpace: withSpace)
    }

    static func attributedFormat(currencyString: String,
                                 currencyCode: String,
                                 withSpace: Bool = false) -> NSAttributedString {
        let text = NSMutableAttributedString()

        text.append(currencyString.ows_stripped(),
                    attributes: [
                        .foregroundColor: Theme.primaryTextColor
                    ])

        if withSpace {
            text.append(" ", attributes: [:])
        }

        text.append(currencyCode.ows_stripped(),
                    attributes: [
                        .foregroundColor: Theme.secondaryTextAndIconColor
                    ])

        return text
    }

    static func formatAsFiatCurrency(paymentAmount: TSPaymentAmount,
                                     currencyConversionInfo: CurrencyConversionInfo) -> String? {
        guard let fiatCurrencyAmount = currencyConversionInfo.convertToFiatCurrency(paymentAmount: paymentAmount) else {
            return nil
        }
        return format(fiatCurrencyAmount: fiatCurrencyAmount)
    }

    // Used to format fiat currency values for display.
    static func format(fiatCurrencyAmount: Double,
                       minimumFractionDigits: Int = 2,
                       maximumFractionDigits: Int = 2) -> String? {
        let currencyFormatter = NumberFormatter()
        currencyFormatter.locale = Locale(identifier: "en_US")
        currencyFormatter.numberStyle = .decimal
        // TODO: Check with design.
        currencyFormatter.minimumFractionDigits = minimumFractionDigits
        currencyFormatter.maximumFractionDigits = maximumFractionDigits
        return currencyFormatter.string(from: NSNumber(value: fiatCurrencyAmount))
    }
}
