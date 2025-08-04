//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import MobileCoin
public import SignalServiceKit

// MARK: - Wallet Operations

@objc
public protocol WalletOperations: AnyObject {
    func walletAddressBase58() -> String?
    var paymentsEntropy: Data? { get }
}

// MARK: - Payment Processing

@objc
public protocol PaymentProcessing: AnyObject {
    func prepareOutgoingPayment(
        recipient: SendPaymentRecipient,
        paymentAmount: TSPaymentAmount,
        memoMessage: String?,
        isOutgoingTransfer: Bool,
        canDefragment: Bool
    ) async throws -> PreparedPayment

    func initiateOutgoingPayment(preparedPayment: PreparedPayment) async throws -> TSPaymentModel

    func blockOnOutgoingVerification(paymentModel: TSPaymentModel) async throws -> Bool
}

// MARK: - Balance Management

@objc
public protocol BalanceManagement: AnyObject {
    var currentPaymentBalance: PaymentBalance? { get }
    func updateCurrentPaymentBalance()
    func clearCurrentPaymentBalance()
}

// MARK: - Validation

@objc
public protocol PaymentValidation: AnyObject {
    func isValidMobileCoinPublicAddress(_ publicAddressData: Data) -> Bool
    func isValidPassphraseWord(_ word: String?) -> Bool
}

// MARK: - Transaction Management

@objc
public protocol TransactionManagement: AnyObject {
    func scheduleReconciliationNow(transaction: DBWriteTransaction)
    
    func replaceAsUnidentified(paymentModel oldPaymentModel: TSPaymentModel,
                               transaction: DBWriteTransaction)
    
    func findPaymentModels(withMCLedgerBlockIndex mcLedgerBlockIndex: UInt64,
                           mcIncomingTransactionPublicKey: Data,
                           transaction: DBReadTransaction) -> [TSPaymentModel]
    
    func clearState(transaction: DBWriteTransaction)
}

// MARK: - Security

@objc
public protocol PaymentSecurity: AnyObject {
    var passphrase: PaymentsPassphrase? { get }
    func passphrase(forPaymentsEntropy paymentsEntropy: Data) -> PaymentsPassphrase?
    func paymentsEntropy(forPassphrase passphrase: PaymentsPassphrase) -> Data?
}

// MARK: - Fee Management

@objc
public protocol FeeManagement: AnyObject {
    func getEstimatedFee(forPaymentAmount paymentAmount: TSPaymentAmount) async throws -> TSPaymentAmount
    func maximumPaymentAmount() async throws -> TSPaymentAmount
}

// MARK: - State Management

@objc
public protocol PaymentStateManagement: AnyObject {
    var shouldShowPaymentsUI: Bool { get }
    var isKillSwitchActive: Bool { get }
    func didReceiveMCAuthError()
}

// MARK: - Legacy Compatibility

@objc
public protocol Payments: AnyObject {
    // This protocol maintains backward compatibility
    // Concrete implementations should conform to all the focused protocols below
}

// MARK: - Swift-Specific Extensions

public protocol PaymentsSwift: Payments {
    // This protocol can be used to compose the focused protocols for Swift implementations
}

// MARK: - Protocol Composition

extension Payments where Self: WalletOperations & PaymentProcessing & BalanceManagement & PaymentValidation & TransactionManagement & PaymentSecurity & FeeManagement & PaymentStateManagement {
    // Default implementations can be provided here if needed
}

// MARK: - Usage Example

/*
 To implement a concrete payments service, conform to the focused protocols:

 class ConcretePaymentsService: NSObject,
     WalletOperations,
     PaymentProcessing,
     BalanceManagement,
     PaymentValidation,
     TransactionManagement,
     PaymentSecurity,
     FeeManagement,
     PaymentStateManagement {
     
     // Implement all required methods from each protocol
     // This approach provides better separation of concerns and testability
 }

 // For backward compatibility, also conform to the legacy protocols:
 extension ConcretePaymentsService: Payments, PaymentsSwift { }
 */

// MARK: -

extension PaymentsPassphrase {

    public static func parse(passphrase: String,
                             validateWords: Bool) throws -> PaymentsPassphrase {
        let words = Array(passphrase.lowercased().stripped.components(separatedBy: " ").compactMap { $0.nilIfEmpty })
        guard words.count == PaymentsConstants.passphraseWordCount else {
            Logger.warn("words.count \(words.count) != \(PaymentsConstants.passphraseWordCount)")
            throw PaymentsError.invalidPassphrase
        }
        if validateWords {
            for word in words {
                guard SUIEnvironment.shared.paymentsSwiftRef.isValidPassphraseWord(word) else {
                    Logger.warn("Invalid passphrase word.")
                    throw PaymentsError.invalidPassphrase
                }
            }
        }
        return try PaymentsPassphrase(words: words)
    }
}

// MARK: -

public protocol SendPaymentRecipient {
    var address: SignalServiceAddress? { get }
    var isIdentifiedPayment: Bool { get }
}

// MARK: -

public protocol PreparedPayment {
    var transaction: MobileCoin.Transaction { get }
    var receipt: MobileCoin.Receipt { get }
    var feeAmount: TSPaymentAmount { get }
}

// MARK: -

public struct PaymentBalance {
    public let amount: TSPaymentAmount
    public let date: Date

    public init(amount: TSPaymentAmount, date: Date) {
        self.amount = amount
        self.date = date
    }
}

// MARK: -

public class MockPayments: NSObject {
}

// MARK: - Mock Implementations

extension MockPayments: WalletOperations {
    public func walletAddressBase58() -> String? {
        owsFail("Not implemented.")
    }
    
    public var paymentsEntropy: Data? { nil }
}

extension MockPayments: PaymentProcessing {
    public func prepareOutgoingPayment(
        recipient: SendPaymentRecipient,
        paymentAmount: TSPaymentAmount,
        memoMessage: String?,
        isOutgoingTransfer: Bool,
        canDefragment: Bool
    ) async throws -> PreparedPayment {
        owsFail("Not implemented.")
    }

    public func initiateOutgoingPayment(preparedPayment: PreparedPayment) async throws -> TSPaymentModel {
        owsFail("Not implemented.")
    }

    public func blockOnOutgoingVerification(paymentModel: TSPaymentModel) async throws -> Bool {
        owsFail("Not implemented.")
    }
}

extension MockPayments: BalanceManagement {
    public var currentPaymentBalance: PaymentBalance? {
        owsFail("Not implemented.")
    }

    public func updateCurrentPaymentBalance() {
        owsFail("Not implemented.")
    }

    public func clearCurrentPaymentBalance() {
        owsFail("Not implemented.")
    }
}

extension MockPayments: PaymentValidation {
    public func isValidMobileCoinPublicAddress(_ publicAddressData: Data) -> Bool {
        owsFail("Not implemented.")
    }

    public func isValidPassphraseWord(_ word: String?) -> Bool {
        owsFail("Not implemented.")
    }
}

extension MockPayments: TransactionManagement {
    public func scheduleReconciliationNow(transaction: DBWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func replaceAsUnidentified(paymentModel oldPaymentModel: TSPaymentModel,
                                      transaction: DBWriteTransaction) {
        owsFail("Not implemented.")
    }

    public func findPaymentModels(withMCLedgerBlockIndex mcLedgerBlockIndex: UInt64,
                                  mcIncomingTransactionPublicKey: Data,
                                  transaction: DBReadTransaction) -> [TSPaymentModel] {
        owsFail("Not implemented.")
    }

    public func clearState(transaction: DBWriteTransaction) {
        owsFail("Not implemented.")
    }
}

extension MockPayments: PaymentSecurity {
    public var passphrase: PaymentsPassphrase? { nil }

    public func passphrase(forPaymentsEntropy paymentsEntropy: Data) -> PaymentsPassphrase? {
        owsFail("Not implemented.")
    }

    public func paymentsEntropy(forPassphrase passphrase: PaymentsPassphrase) -> Data? {
        owsFail("Not implemented.")
    }
}

extension MockPayments: FeeManagement {
    public func getEstimatedFee(forPaymentAmount paymentAmount: TSPaymentAmount) async throws -> TSPaymentAmount {
        owsFail("Not implemented.")
    }

    public func maximumPaymentAmount() async throws -> TSPaymentAmount {
        owsFail("Not implemented.")
    }
}

extension MockPayments: PaymentStateManagement {
    public var shouldShowPaymentsUI: Bool {
        owsFail("Not implemented.")
    }

    public var isKillSwitchActive: Bool { false }

    public func didReceiveMCAuthError() {
        owsFail("Not implemented.")
    }
}

// MARK: - Legacy Compatibility

extension MockPayments: Payments {
    // MockPayments now implements all required protocols through the focused protocol extensions above
}

extension MockPayments: PaymentsSwift {
    // Additional Swift-specific functionality can be added here if needed
}
