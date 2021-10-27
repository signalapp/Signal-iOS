//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class PaymentsHelperImpl: NSObject, PaymentsHelperSwift {

    // MARK: - PaymentsState

    private static let arePaymentsEnabledKey = "isPaymentEnabled"
    private static let paymentsEntropyKey = "paymentsEntropy"

    private let paymentStateCache = AtomicOptional<PaymentsState>(nil)

    @objc
    public static let arePaymentsEnabledDidChange = Notification.Name("arePaymentsEnabledDidChange")

    public func warmCaches() {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)

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
        
        transaction.addAsyncCompletionOffMain {
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
    
    private static func generateRandomPaymentsEntropy() -> Data {
        Cryptography.generateRandomBytes(PaymentsConstants.paymentsEntropyLength)
    }
    
    // MARK: -
    
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

    public func clearState(transaction: SDSAnyWriteTransaction) {
        Self.keyValueStore.removeAll(transaction: transaction)
        
        paymentStateCache.set(nil)
        paymentBalanceCache.set(nil)
        
        discardApiHandle()
    }
}

// MARK: -

public struct PaymentsPassphrase: Equatable, Dependencies {

    public let words: [String]

    public init(words: [String]) throws {
        guard words.count == PaymentsConstants.passphraseWordCount else {
            owsFailDebug("words.count \(words.count) != \(PaymentsConstants.passphraseWordCount)")
            throw PaymentsError.invalidPassphrase
        }

        self.words = words
    }

    public var wordCount: Int { words.count }

    public var asPassphrase: String { words.joined(separator: " ") }

    public var debugDescription: String { asPassphrase }
}
