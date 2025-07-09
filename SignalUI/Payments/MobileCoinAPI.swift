//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MobileCoin
public import SignalServiceKit

public class MobileCoinAPI {

    // MARK: - Passphrases & Entropy

    public static func passphrase(forPaymentsEntropy paymentsEntropy: Data) throws -> PaymentsPassphrase {
        guard paymentsEntropy.count == PaymentsConstants.paymentsEntropyLength else {
            throw PaymentsError.invalidEntropy
        }
        let result = MobileCoin.Mnemonic.mnemonic(fromEntropy: paymentsEntropy)
        switch result {
        case .success(let mnemonic):
            return try PaymentsPassphrase.parse(passphrase: mnemonic,
                                                validateWords: false)
        case .failure(let error):
            owsFailDebug("Error: \(error)")
            let error = Self.convertMCError(error: error)
            throw error
        }
    }

    public static func paymentsEntropy(forPassphrase passphrase: PaymentsPassphrase) throws -> Data {
        let mnemonic = passphrase.asPassphrase
        let result = MobileCoin.Mnemonic.entropy(fromMnemonic: mnemonic)
        switch result {
        case .success(let paymentsEntropy):
            guard paymentsEntropy.count == PaymentsConstants.paymentsEntropyLength else {
                throw PaymentsError.invalidEntropy
            }
            return paymentsEntropy
        case .failure(let error):
            owsFailDebug("Error: \(error)")
            let error = Self.convertMCError(error: error)
            throw error
        }
    }

    public static func isValidPassphraseWord(_ word: String?) -> Bool {
        guard let word = word?.strippedOrNil else {
            return false
        }
        return !MobileCoin.Mnemonic.words(matchingPrefix: word).isEmpty
    }

    // MARK: -

    private let paymentsEntropy: Data

    // PAYMENTS TODO: Finalize this value with the designers.
    private static let timeoutDuration: TimeInterval = 60

    let localAccount: MobileCoinAccount

    private let client: MobileCoinClient

    private init(paymentsEntropy: Data,
                 localAccount: MobileCoinAccount,
                 client: MobileCoinClient) throws {

        guard paymentsEntropy.count == PaymentsConstants.paymentsEntropyLength else {
            throw PaymentsError.invalidEntropy
        }

        owsAssertDebug(SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled)

        self.paymentsEntropy = paymentsEntropy
        self.localAccount = localAccount
        self.client = client
    }

    // MARK: -

    public static func configureSDKLogging() {
        if DebugFlags.internalLogging,
           !CurrentAppContext().isRunningTests {
            MobileCoinLogging.logSensitiveData = true
        }
    }

    // MARK: -

    private func withTimeoutAndErrorConversion<T>(makeRequest: @escaping () async throws -> T) async throws -> T {
        if DebugFlags.paymentsNoRequestsComplete.get() {
            // Never resolve.
            try! await Task.sleep(nanoseconds: TimeInterval.infinity.clampedNanoseconds)
        }
        do {
            return try await withUncooperativeTimeout(seconds: Self.timeoutDuration) {
                do {
                    return try await makeRequest()
                } catch {
                    let convertedError = Self.convertMCError(error: error)
                    owsFailDebugUnlessMCNetworkFailure(convertedError)
                    throw convertedError
                }
            }
        } catch is UncooperativeTimeoutError {
            throw PaymentsError.timeout
        }
    }

    // MARK: -

    static func buildLocalAccount(paymentsEntropy: Data) throws -> MobileCoinAccount {
        try Self.buildAccount(forPaymentsEntropy: paymentsEntropy)
    }

    private static func parseAuthorizationResponse(responseObject: Any?) throws -> OWSAuthorization {
        guard let params = ParamParser(responseObject: responseObject) else {
            throw OWSAssertionError("Invalid responseObject.")
        }
        let username: String = try params.required(key: "username")
        let password: String = try params.required(key: "password")
        return OWSAuthorization(username: username, password: password)
    }

    public static func build(paymentsEntropy: Data) async throws -> MobileCoinAPI {
        guard !CurrentAppContext().isNSE else {
            throw OWSAssertionError("Payments disabled in NSE.")
        }
        let request = OWSRequestFactory.paymentsAuthenticationCredentialRequest()
        let response = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request)
        guard let json = response.responseBodyJson else {
            throw OWSAssertionError("Missing or invalid JSON")
        }
        let signalAuthorization = try Self.parseAuthorizationResponse(responseObject: json)
        let localAccount = try Self.buildAccount(forPaymentsEntropy: paymentsEntropy)
        let client = try localAccount.buildClient(signalAuthorization: signalAuthorization)
        return try MobileCoinAPI(paymentsEntropy: paymentsEntropy, localAccount: localAccount, client: client)
    }

    // MARK: -

    class func isValidMobileCoinPublicAddress(_ publicAddressData: Data) -> Bool {
        MobileCoin.PublicAddress(serializedData: publicAddressData) != nil
    }

    // MARK: -

    func getLocalBalance() -> Promise<TSPaymentAmount> {
        Logger.verbose("")

        let client = self.client

        return firstly(on: DispatchQueue.global()) { () throws -> Promise<MobileCoin.Balance> in
            let (promise, future) = Promise<MobileCoin.Balance>.pending()
            if DebugFlags.paymentsNoRequestsComplete.get() {
                // Never resolve.
                return promise
            }
            client.updateBalances { (result: Swift.Result<Balances, BalanceUpdateError>) in
                switch result {
                case .success(let balances):
                    future.resolve(balances.mobBalance)
                case .failure(let error):
                    let error = Self.convertMCError(error: error)
                    future.reject(error)
                }
            }
            return promise
        }.map(on: DispatchQueue.global()) { (balance: MobileCoin.Balance) -> TSPaymentAmount in
            Logger.verbose("Success: \(balance)")
            // We do not need to support amountPicoMobHigh.
            guard let amountPicoMob = balance.amount() else {
                throw OWSAssertionError("Invalid balance.")
            }
            return TSPaymentAmount(currency: .mobileCoin, picoMob: amountPicoMob)
        }.recover(on: DispatchQueue.global()) { (error: Error) -> Promise<TSPaymentAmount> in
            owsFailDebugUnlessMCNetworkFailure(error)
            throw error
        }.timeout(seconds: Self.timeoutDuration, description: "getLocalBalance") { () -> Error in
            PaymentsError.timeout
        }
    }

    func getEstimatedFee(forPaymentAmount paymentAmount: TSPaymentAmount) async throws -> TSPaymentAmount {
        guard paymentAmount.isValidAmount(canBeEmpty: false) else {
            throw OWSAssertionError("Invalid amount.")
        }

        return try await _getPaymentAmount(canBeEmpty: false, getPicoMob: { [client] in
            return try await withCheckedThrowingContinuation { continuation in
                // We don't need to support amountPicoMobHigh.
                let amount = Amount(paymentAmount.picoMob, in: .MOB)
                client.estimateTotalFee(toSendAmount: amount, feeLevel: Self.feeLevel) {
                    continuation.resume(with: $0)
                }
            }
        })
    }

    func maxTransactionAmount() async throws -> TSPaymentAmount {
        return try await _getPaymentAmount(canBeEmpty: true, getPicoMob: { [client] in
            return try await withCheckedThrowingContinuation { continuation in
                client.amountTransferable(tokenId: .MOB, feeLevel: Self.feeLevel) {
                    continuation.resume(with: $0)
                }
            }
        })
    }

    private func _getPaymentAmount(canBeEmpty: Bool, getPicoMob: @escaping () async throws -> UInt64) async throws -> TSPaymentAmount {
        if DebugFlags.paymentsNoRequestsComplete.get() {
            // Never resolve.
            try! await Task.sleep(nanoseconds: TimeInterval.infinity.clampedNanoseconds)
        }

        let picoMob = try await withTimeoutAndErrorConversion(makeRequest: getPicoMob)
        let result = TSPaymentAmount(currency: .mobileCoin, picoMob: picoMob)
        guard result.isValidAmount(canBeEmpty: canBeEmpty) else {
            throw OWSAssertionError("Invalid amount.")
        }
        return result
    }

    struct PreparedTransaction: PreparedPayment {
        let transaction: MobileCoin.Transaction
        let receipt: MobileCoin.Receipt
        let feeAmount: TSPaymentAmount
    }

    func prepareTransaction(paymentAmount: TSPaymentAmount,
                            recipientPublicAddress: MobileCoin.PublicAddress,
                            shouldUpdateBalance: Bool) -> Promise<PreparedTransaction> {
        Logger.verbose("")

        Logger.verbose("paymentAmount: \(paymentAmount.picoMob)")

        let client = self.client

        return firstly(on: DispatchQueue.global()) { () throws -> Promise<Void> in
            guard shouldUpdateBalance else {
                return Promise.value(())
            }
            return firstly(on: DispatchQueue.global()) { () throws -> Promise<TSPaymentAmount> in
                // prepareTransaction() will fail if local balance is not yet known.
                self.getLocalBalance()
            }.done(on: DispatchQueue.global()) { (balance: TSPaymentAmount) in
                Logger.verbose("balance: \(balance.picoMob)")
            }
        }.then(on: DispatchQueue.global()) { () -> Promise<TSPaymentAmount> in
            return Promise.wrapAsync {
                try await self.getEstimatedFee(forPaymentAmount: paymentAmount)
            }
        }.then(on: DispatchQueue.global()) { (estimatedFeeAmount: TSPaymentAmount) -> Promise<PreparedTransaction> in
            Logger.verbose("estimatedFeeAmount: \(estimatedFeeAmount.picoMob)")
            guard paymentAmount.isValidAmount(canBeEmpty: false) else {
                throw OWSAssertionError("Invalid amount.")
            }
            guard estimatedFeeAmount.isValidAmount(canBeEmpty: false) else {
                throw OWSAssertionError("Invalid fee.")
            }

            let (promise, future) = Promise<PreparedTransaction>.pending()
            if DebugFlags.paymentsNoRequestsComplete.get() {
                // Never resolve.
                return promise
            }
            // We don't need to support amountPicoMobHigh.
            client.prepareTransaction(to: recipientPublicAddress,
                                      amount: Amount(paymentAmount.picoMob, in: .MOB),
                                      fee: estimatedFeeAmount.picoMob) { (result: Swift.Result<PendingSinglePayloadTransaction,
                                                                                                TransactionPreparationError>) in
                switch result {
                case .success(let payload):
                    let transaction = payload.transaction
                    let receipt = payload.receipt
                    let finalFeeAmount = TSPaymentAmount(currency: .mobileCoin,
                                                         picoMob: transaction.fee)
                    owsAssertDebug(estimatedFeeAmount == finalFeeAmount)
                    let preparedTransaction = PreparedTransaction(transaction: transaction,
                                                                  receipt: receipt,
                                                                  feeAmount: finalFeeAmount)
                    future.resolve(preparedTransaction)
                case .failure(let error):
                    let error = Self.convertMCError(error: error)
                    future.reject(error)
                }
            }
            return promise
        }.recover(on: DispatchQueue.global()) { (error: Error) -> Promise<PreparedTransaction> in
            owsFailDebugUnlessMCNetworkFailure(error)
            throw error
        }.timeout(seconds: Self.timeoutDuration, description: "prepareTransaction") { () -> Error in
            PaymentsError.timeout
        }
    }

    // TODO: Are we always going to use _minimum_ fee?
    private static let feeLevel: MobileCoin.FeeLevel = .minimum

    func requiresDefragmentation(forPaymentAmount paymentAmount: TSPaymentAmount) -> Promise<Bool> {
        Logger.verbose("")

        let client = self.client

        return firstly(on: DispatchQueue.global()) { () -> Promise<Bool> in
            let (promise, future) = Promise<Bool>.pending()
            if DebugFlags.paymentsNoRequestsComplete.get() {
                // Never resolve.
                return promise
            }
            client.requiresDefragmentation(toSendAmount: Amount(paymentAmount.picoMob, in: .MOB),
                                           feeLevel: Self.feeLevel) { (result: Swift.Result<Bool,
                                                                                            TransactionEstimationFetcherError>) in
                switch result {
                case .success(let shouldDefragment):
                    future.resolve(shouldDefragment)
                case .failure(let error):
                    let error = Self.convertMCError(error: error)
                    future.reject(error)
                }
            }
            return promise
        }.recover(on: DispatchQueue.global()) { (error: Error) -> Promise<Bool> in
            owsFailDebugUnlessMCNetworkFailure(error)
            throw error
        }.timeout(seconds: Self.timeoutDuration, description: "requiresDefragmentation") { () -> Error in
            PaymentsError.timeout
        }
    }

    func prepareDefragmentationStepTransactions(forPaymentAmount paymentAmount: TSPaymentAmount) -> Promise<[MobileCoin.Transaction]> {
        Logger.verbose("")

        let client = self.client

        return firstly(on: DispatchQueue.global()) { () throws -> Promise<[MobileCoin.Transaction]> in
            let (promise, future) = Promise<[MobileCoin.Transaction]>.pending()
            if DebugFlags.paymentsNoRequestsComplete.get() {
                // Never resolve.
                return promise
            }
            client.prepareDefragmentationStepTransactions(toSendAmount: Amount(paymentAmount.picoMob, in: .MOB),
                                                          feeLevel: Self.feeLevel) { (result: Swift.Result<[MobileCoin.Transaction],
                                                                                                           MobileCoin.DefragTransactionPreparationError>) in
                switch result {
                case .success(let transactions):
                    future.resolve(transactions)
                case .failure(let error):
                    let error = Self.convertMCError(error: error)
                    future.reject(error)
                }
            }
            return promise
        }.timeout(seconds: Self.timeoutDuration, description: "prepareDefragmentationStepTransactions") { () -> Error in
            PaymentsError.timeout
        }
    }

    func submitTransaction(transaction: MobileCoin.Transaction) async throws -> Void {
        Logger.verbose("")

        guard !DebugFlags.paymentsFailOutgoingSubmission.get() else {
            throw OWSGenericError("Failed.")
        }

        return try await withTimeoutAndErrorConversion { [client] in
            return try await withCheckedThrowingContinuation { continuation in
                client.submitTransaction(transaction: transaction) { (result: Result<UInt64, SubmitTransactionError>) in
                    switch result {
                    case .success:
                        Logger.verbose("Success.")
                        continuation.resume(returning: ())
                    case .failure(let error):
                        continuation.resume(throwing: error.submissionError)
                    }
                }
            }
        }
    }

    func getOutgoingTransactionStatus(transaction: MobileCoin.Transaction) async throws -> MCOutgoingTransactionStatus {
        Logger.verbose("")

        guard !DebugFlags.paymentsFailOutgoingVerification.get() else {
            throw OWSGenericError("Failed.")
        }

        let transactionStatus = try await withTimeoutAndErrorConversion { [client] in
            return try await withCheckedThrowingContinuation { continuation in
                client.txOutStatus(of: transaction) { (result: Swift.Result<MobileCoin.TransactionStatus, ConnectionError>) in
                    continuation.resume(with: result)
                }
            }
        }
        let outgoingTransactionStatus = MCOutgoingTransactionStatus(transactionStatus: transactionStatus)
        Logger.verbose("Success: \(outgoingTransactionStatus)")
        SUIEnvironment.shared.paymentsSwiftRef.clearCurrentPaymentBalance()
        return outgoingTransactionStatus
    }

    func paymentAmount(forReceipt receipt: MobileCoin.Receipt) throws -> TSPaymentAmount {
        try Self.paymentAmount(forReceipt: receipt, localAccount: localAccount)
    }

    static func paymentAmount(forReceipt receipt: MobileCoin.Receipt,
                              localAccount: MobileCoinAccount) throws -> TSPaymentAmount {
        guard let picoMob = receipt.validateAndUnmaskValue(accountKey: localAccount.accountKey) else {
            // This can happen if the receipt was address to a different account.
            owsFailDebug("Receipt missing amount.")
            throw PaymentsError.invalidAmount
        }
        guard picoMob > 0 else {
            owsFailDebug("Receipt has invalid amount.")
            throw PaymentsError.invalidAmount
        }
        return TSPaymentAmount(currency: .mobileCoin, picoMob: picoMob)
    }

    func getIncomingReceiptStatus(receipt: MobileCoin.Receipt) -> Promise<MCIncomingReceiptStatus> {
        Logger.verbose("")

        guard !DebugFlags.paymentsFailIncomingVerification.get() else {
            return Promise(error: OWSGenericError("Failed."))
        }

        let client = self.client
        let localAccount = self.localAccount

        return firstly(on: DispatchQueue.global()) { () throws -> Promise<TSPaymentAmount> in
            // .status(of: receipt) requires an updated balance.
            //
            // TODO: We could improve perf when verifying multiple receipts by getting balance just once.
            self.getLocalBalance()
        }.map(on: DispatchQueue.global()) { (_: TSPaymentAmount) -> MCIncomingReceiptStatus in
            let paymentAmount: TSPaymentAmount
            do {
                paymentAmount = try Self.paymentAmount(forReceipt: receipt,
                                                       localAccount: localAccount)
            } catch {
                owsFailDebug("Error: \(error)")
                return MCIncomingReceiptStatus(receiptStatus: .failed,
                                               paymentAmount: .zeroMob,
                                               txOutPublicKey: Data())
            }
            let txOutPublicKey: Data = receipt.txOutPublicKey

            let result = client.status(of: receipt)
            switch result {
            case .success(let receiptStatus):
                return MCIncomingReceiptStatus(receiptStatus: receiptStatus,
                                               paymentAmount: paymentAmount,
                                               txOutPublicKey: txOutPublicKey)
            case .failure(let error):
                let error = Self.convertMCError(error: error)
                throw error
            }
        }.map(on: DispatchQueue.global()) { (value: MCIncomingReceiptStatus) -> MCIncomingReceiptStatus in
            Logger.verbose("Success: \(value)")
            return value
        }.recover(on: DispatchQueue.global()) { (error: Error) -> Promise<MCIncomingReceiptStatus> in
            owsFailDebugUnlessMCNetworkFailure(error)
            throw error
        }.timeout(seconds: Self.timeoutDuration, description: "getIncomingReceiptStatus") { () -> Error in
            PaymentsError.timeout
        }
    }

    func getAccountActivity() async throws -> MobileCoin.AccountActivity {
        Logger.verbose("")

        let client = self.client

        _ = try await withTimeoutAndErrorConversion {
            return try await withCheckedThrowingContinuation { continuation in
                client.updateBalances { (result: Swift.Result<Balances, BalanceUpdateError>) in
                    continuation.resume(with: result)
                }
            }
        }
        let accountActivity = client.accountActivity(for: .MOB)
        Logger.verbose("Success: \(accountActivity.blockCount)")
        return accountActivity
    }
}

// MARK: -

extension MobileCoin.PublicAddress {
    var asPaymentAddress: TSPaymentAddress {
        return TSPaymentAddress(currency: .mobileCoin,
                                mobileCoinPublicAddressData: serializedData)
    }
}

// MARK: -

extension TSPaymentAddress {
    func asPublicAddress() throws -> MobileCoin.PublicAddress {
        guard currency == .mobileCoin else {
            throw PaymentsError.invalidCurrency
        }
        guard let address = MobileCoin.PublicAddress(serializedData: mobileCoinPublicAddressData) else {
            throw OWSAssertionError("Invalid mobileCoinPublicAddressData.")
        }
        return address
    }
}

// MARK: -

struct MCIncomingReceiptStatus {
    let receiptStatus: MobileCoin.ReceiptStatus
    let paymentAmount: TSPaymentAmount
    let txOutPublicKey: Data
}

// MARK: -

struct MCOutgoingTransactionStatus {
    let transactionStatus: MobileCoin.TransactionStatus
}

// MARK: - Error Handling

extension MobileCoinAPI {
    public static func convertMCError(error: Error) -> PaymentsError {
        func switchOnConnectionError(_ error: MobileCoin.ConnectionError) -> PaymentsError {
            switch error {
            case .connectionFailure(let reason):
                Logger.warn("Error: \(error), reason: \(reason)")
                return PaymentsError.connectionFailure
            case .authorizationFailure(let reason):
                owsFailDebug("Error: \(error), reason: \(reason)")

                // Immediately discard the SDK client instance; the auth token may be stale.
                SUIEnvironment.shared.paymentsRef.didReceiveMCAuthError()

                return PaymentsError.authorizationFailure
            case .invalidServerResponse(let reason):
                // TODO: It would be preferable to owsFailDebug()
                //       here. Ledger errors can now occur during
                //       fee transitions, but should be very rare.
                Logger.warn("Error: \(error), reason: \(reason)")
                return PaymentsError.invalidServerResponse
            case .attestationVerificationFailed(let reason):
                owsFailDebug("Error: \(error), reason: \(reason)")
                return PaymentsError.attestationVerificationFailed
            case .outdatedClient(let reason):
                owsFailDebug("Error: \(error), reason: \(reason)")
                return PaymentsError.outdatedClient
            case .serverRateLimited(let reason):
                owsFailDebug("Error: \(error), reason: \(reason)")
                return PaymentsError.serverRateLimited
            }
        }

        switch error {
        case let error as MobileCoin.SecurityError:
            // Wraps errors from Apple Security framework used in SecSSLCertificate init.
            owsFailDebug("Error: \(error)")
            return PaymentsError.invalidInput
        case let error as MobileCoin.InvalidInputError:
            owsFailDebug("Error: \(error)")
            return PaymentsError.invalidInput
        case let error as MobileCoin.BalanceUpdateError:
            switch error {
            case .connectionError(let error):
                return switchOnConnectionError(error)
            case .fogSyncError(let error):
                Logger.warn("Error: \(error)")
                return PaymentsError.fogOutOfSync
            }
        case let error as MobileCoin.ConnectionError:
            return switchOnConnectionError(error)
        case let error as MobileCoin.TransactionPreparationError:
            switch error {
            case .invalidInput(let reason):
                owsFailDebug("Error: \(error), reason: \(reason)")
                return PaymentsError.invalidInput
            case .insufficientBalance:
                Logger.warn("Error: \(error)")
                return PaymentsError.insufficientFunds
            case .defragmentationRequired:
                Logger.warn("Error: \(error)")
                return PaymentsError.defragmentationRequired
            case .connectionError(let connectionError):
                // Recurse.
                return convertMCError(error: connectionError)
            }
        case let error as MobileCoin.TransactionSubmissionError:
            switch error {
            case .connectionError(let connectionError):
                // Recurse.
                return convertMCError(error: connectionError)
            case .invalidTransaction:
                Logger.warn("Error: \(error)")
                return PaymentsError.invalidTransaction
            case .feeError:
                Logger.warn("Error: \(error)")
                return PaymentsError.invalidFee
            case .tombstoneBlockTooFar:
                Logger.warn("Error: \(error)")
                // Map to .invalidTransaction
                return PaymentsError.invalidTransaction
            case .inputsAlreadySpent:
                Logger.warn("Error: \(error)")
                return PaymentsError.inputsAlreadySpent
            case .missingMemo:
                Logger.warn("Error: \(error)")
                return PaymentsError.missingMemo
            case .outputAlreadyExists:
                // Transaction with same public key already exists (idempotence)
                Logger.warn("Error: \(error)")
                return PaymentsError.invalidTransaction
            }
        case let error as MobileCoin.DefragTransactionPreparationError:
            switch error {
            case .invalidInput(let reason):
                owsFailDebug("Error: \(error), reason: \(reason)")
                return PaymentsError.invalidInput
            case .insufficientBalance:
                Logger.warn("Error: \(error)")
                return PaymentsError.insufficientFunds
            case .connectionError(let connectionError):
                // Recurse.
                return convertMCError(error: connectionError)
            }
        case let error as MobileCoin.BalanceTransferEstimationFetcherError:
            switch error {
            case .feeExceedsBalance:
                // TODO: Review this mapping.
                Logger.warn("Error: \(error)")
                return PaymentsError.insufficientFunds
            case .balanceOverflow:
                // TODO: Review this mapping.
                Logger.warn("Error: \(error)")
                return PaymentsError.insufficientFunds
            case .connectionError(let connectionError):
                // Recurse.
                return convertMCError(error: connectionError)
            }
        case let error as MobileCoin.TransactionEstimationFetcherError:
            switch error {
            case .invalidInput(let reason):
                owsFailDebug("Error: \(error), reason: \(reason)")
                return PaymentsError.invalidInput
            case .insufficientBalance:
                Logger.warn("Error: \(error)")
                return PaymentsError.insufficientFunds
            case .connectionError(let connectionError):
                // Recurse.
                return convertMCError(error: connectionError)
            }
        default:
            owsFailDebug("Unexpected error: \(error)")
            return PaymentsError.unknownSDKError
        }
    }
}

// MARK: -

public extension PaymentsError {
    var isPaymentsNetworkFailure: Bool {
        switch self {
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
             .serverRateLimited,
             .serializationError,
             .verificationStatusUnknown,
             .ledgerBlockTimestampUnknown,
             .missingModel,
             .defragmentationRequired,
             .invalidTransaction,
             .inputsAlreadySpent,
             .defragmentationFailed,
             .invalidPassphrase,
             .invalidEntropy,
             .missingMemo,
             .killSwitch:
            return false
        case .connectionFailure,
             .fogOutOfSync,
             .timeout,
             .outgoingVerificationTakingTooLong:
            return true
        }
    }

    var isExpectedFromSDK: Bool {
        switch self {
        case .notEnabled,
             .userNotRegisteredOrAppNotReady,
             .userHasNoPublicAddress,
             .invalidCurrency,
             .invalidWalletKey,
             .invalidAmount,
             .invalidFee,
             .invalidModel,
             .indeterminateState,
             .unknownSDKError,
             .invalidInput,
             .authorizationFailure,
             .invalidServerResponse,
             .attestationVerificationFailed,
             .outdatedClient,
             .serverRateLimited,
             .serializationError,
             .verificationStatusUnknown,
             .ledgerBlockTimestampUnknown,
             .missingModel,
             .defragmentationRequired,
             .invalidTransaction,
             .inputsAlreadySpent,
             .defragmentationFailed,
             .invalidPassphrase,
             .invalidEntropy,
             .killSwitch,
             .connectionFailure,
             .timeout,
             .outgoingVerificationTakingTooLong,
             .fogOutOfSync,
             .missingMemo:
            return false
        case .tooOldToSubmit,
             .insufficientFunds:
            return true
        }
    }
}

// MARK: -

// A variant of owsFailDebugUnlessNetworkFailure() that can handle
// network failures from the MobileCoin SDK.
@inlinable
public func owsFailDebugUnlessMCNetworkFailure(_ error: Error,
                                               file: String = #file,
                                               function: String = #function,
                                               line: Int = #line) {
    if let paymentsError = error as? PaymentsError {
        if paymentsError.isPaymentsNetworkFailure {
            // Log but otherwise ignore network failures.
            Logger.warn("Error: \(error)", file: file, function: function, line: line)
        } else if paymentsError.isExpectedFromSDK {
            Logger.warn("Error: \(error)", file: file, function: function, line: line)
        } else {
            owsFailDebug("Error: \(error)", file: file, function: function, line: line)
        }
    } else if error is OWSAssertionError {
        owsFailDebug("Unexpected error: \(error)")
    } else {
        owsFailDebugUnlessNetworkFailure(error)
    }
}

// MARK: - URLs

extension MobileCoinAPI {
    static func formatAsBase58(publicAddress: MobileCoin.PublicAddress) -> String {
        return Base58Coder.encode(publicAddress)
    }

    static func parseAsPublicAddress(url: URL) -> MobileCoin.PublicAddress? {
        let result = MobUri.decode(uri: url.absoluteString)
        switch result {
        case .success(let payload):
            switch payload {
            case .publicAddress(let publicAddress):
                return publicAddress
            case .paymentRequest(let paymentRequest):
                // TODO: We could honor the amount and memo.
                return paymentRequest.publicAddress
            case .transferPayload:
                // TODO: We could handle transferPayload.
                owsFailDebug("Unexpected payload.")
                return nil
            }
        case .failure(let error):
            let error = Self.convertMCError(error: error)
            owsFailDebugUnlessMCNetworkFailure(error)
            return nil
        }
    }

    static func parse(publicAddressBase58 base58: String) -> MobileCoin.PublicAddress? {
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
