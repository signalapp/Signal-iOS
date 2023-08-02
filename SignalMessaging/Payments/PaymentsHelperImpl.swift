//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit
import SignalServiceKit

public class PaymentsHelperImpl: Dependencies, PaymentsHelperSwift, PaymentsHelper {

    public required init() {
        self.observeNotifications()
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(registrationStateDidChange),
                                               name: .registrationStateDidChange,
                                               object: nil)
    }

    @objc
    private func registrationStateDidChange() {
        // Caches should be re-warmed after a registration state change.
        warmCaches()
    }

    public var isKillSwitchActive: Bool {
        RemoteConfig.paymentsResetKillSwitch || !hasValidPhoneNumberForPayments
    }

    public var hasValidPhoneNumberForPayments: Bool {
        guard Self.tsAccountManager.isRegisteredAndReady else {
            return false
        }
        guard let localNumber = Self.tsAccountManager.localNumber else {
            return false
        }
        let paymentsDisabledRegions = RemoteConfig.paymentsDisabledRegions
        if paymentsDisabledRegions.isEmpty {
            return Self.isValidPhoneNumberForPayments_fixedAllowlist(localNumber)
        } else {
            return Self.isValidPhoneNumberForPayments_remoteConfigBlocklist(localNumber,
                                                                            paymentsDisabledRegions: paymentsDisabledRegions)
             }
    }

    private static func isValidPhoneNumberForPayments_fixedAllowlist(_ e164: String) -> Bool {
        guard let phoneNumber = PhoneNumber(fromE164: e164) else {
            owsFailDebug("Could not parse phone number: \(e164).")
            return false
        }
        guard let nsCountryCode = phoneNumber.getCountryCode() else {
            owsFailDebug("Missing countryCode: \(e164).")
            return false
        }
        let validCountryCodes: [Int] = [
            // France
            33,
            // Switzerland
            41,
            // Parts of UK.
            44,
            // Germany
            49
        ]
        return validCountryCodes.contains(nsCountryCode.intValue)
    }

    internal static func isValidPhoneNumberForPayments_remoteConfigBlocklist(
        _ e164: String,
        paymentsDisabledRegions: PhoneNumberRegions
    ) -> Bool {
        owsAssertDebug(
            !paymentsDisabledRegions.isEmpty,
            "Missing paymentsDisabledRegions. Used the fixed allowlist instead."
        )
        return !paymentsDisabledRegions.contains(e164: e164)
    }

    public var canEnablePayments: Bool {
        guard !isKillSwitchActive else {
            return false
        }
        return hasValidPhoneNumberForPayments
    }

    // MARK: - PaymentsState

    // NOTE: This k-v store is shared by PaymentsHelperImpl and PaymentsImpl.
    fileprivate static let keyValueStore = SDSKeyValueStore(collection: "Payments")
    public var keyValueStore: SDSKeyValueStore { Self.keyValueStore}

    private static let arePaymentsEnabledKey = "isPaymentEnabled"
    private static let paymentsEntropyKey = "paymentsEntropy"
    private static let lastKnownLocalPaymentAddressProtoDataKey = "lastKnownLocalPaymentAddressProtoData"

    private let paymentStateCache = AtomicOptional<PaymentsState>(nil)

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
        // We must preserve any existing paymentsEntropy, and then prefer "old" entropy, then last resort generate new entropy.
        let existingPaymentsEntropy = self.paymentsEntropy
        let oldPaymentsEntropy = Self.loadPaymentsState(transaction: transaction).paymentsEntropy
        let paymentsEntropy = existingPaymentsEntropy ?? oldPaymentsEntropy ?? Self.generateRandomPaymentsEntropy()
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
                         originatedLocally: true,
                         transaction: transaction)
        owsAssertDebug(arePaymentsEnabled)
        return true
    }

    public func disablePayments(transaction: SDSAnyWriteTransaction) {
        switch paymentsState {
        case .enabled(let paymentsEntropy):
            setPaymentsState(.disabledWithPaymentsEntropy(paymentsEntropy: paymentsEntropy),
                             originatedLocally: true,
                             transaction: transaction)
        case .disabled, .disabledWithPaymentsEntropy:
            owsFailDebug("Payments already disabled.")
        }
        owsAssertDebug(!arePaymentsEnabled)
    }

    public func setPaymentsState(_ newPaymentsState: PaymentsState,
                                 originatedLocally: Bool,
                                 transaction: SDSAnyWriteTransaction) {
        let oldPaymentsState = self.paymentsState
        var newPaymentsState = newPaymentsState

        // If payments was enabled remotely (e.g. on another device or previous install) we want
        // to enable it even if the current device no longer supports enabling payments. This will
        // behave as if the payments kill switch is turned on until the user is on a payments enabled
        // install, but preserve their access to payments in the UI.
        let canEnablePaymentsLocallyOrRemotely = self.canEnablePayments || !originatedLocally

        if newPaymentsState.isEnabled && !canEnablePaymentsLocallyOrRemotely {
            // If we cannot enable payments, ensure that any new entropy is always preserved.
            if let paymentsEntropy = newPaymentsState.paymentsEntropy {
                newPaymentsState = .disabledWithPaymentsEntropy(paymentsEntropy: paymentsEntropy)
            } else {
                newPaymentsState = .disabled
            }
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

        paymentsEvents.updateLastKnownLocalPaymentAddressProtoData(transaction: transaction)

        transaction.addAsyncCompletionOffMain {
            NotificationCenter.default.postNotificationNameAsync(PaymentsConstants.arePaymentsEnabledDidChange, object: nil)

            Self.paymentsEvents.paymentsStateDidChange()

            if originatedLocally {
                // We only need to re-upload the profile if the change originated
                // locally.
                Logger.info("Re-uploading local profile due to payments state change.")
                Self.profileManager.reuploadLocalProfile(authedAccount: .implicit())

                Self.storageServiceManager.recordPendingLocalAccountUpdates()
            }
        }
    }

    private static func loadPaymentsState(transaction: SDSAnyReadTransaction) -> PaymentsState {
        guard tsAccountManager.isRegisteredAndReady(transaction: transaction) else {
            return .disabled
        }
        let paymentsEntropy = keyValueStore.getData(paymentsEntropyKey, transaction: transaction)
        let arePaymentsEnabled = keyValueStore.getBool(Self.arePaymentsEnabledKey,
                                                       defaultValue: false,
                                                       transaction: transaction)
        return PaymentsState.build(arePaymentsEnabled: arePaymentsEnabled,
                                   paymentsEntropy: paymentsEntropy)
    }

    private static func generateRandomPaymentsEntropy() -> Data {
        Cryptography.generateRandomBytes(PaymentsConstants.paymentsEntropyLength)
    }

    public func clearState(transaction: SDSAnyWriteTransaction) {
        Self.keyValueStore.removeAll(transaction: transaction)

        paymentStateCache.set(nil)
    }

    public func setLastKnownLocalPaymentAddressProtoData(_ data: Data?, transaction: SDSAnyWriteTransaction) {
        Self.keyValueStore.setData(data, key: Self.lastKnownLocalPaymentAddressProtoDataKey, transaction: transaction)
    }

    public func lastKnownLocalPaymentAddressProtoData(transaction: SDSAnyWriteTransaction) -> Data? {
        paymentsEvents.updateLastKnownLocalPaymentAddressProtoData(transaction: transaction)
        return Self.keyValueStore.getData(Self.lastKnownLocalPaymentAddressProtoDataKey, transaction: transaction)
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

    // MARK: - Version Compatibility

    private let isPaymentsVersionOutdatedCache = AtomicValue<Bool>(false)

    public var isPaymentsVersionOutdated: Bool {
        isPaymentsVersionOutdatedCache.get()
    }

    public func setPaymentsVersionOutdated(_ value: Bool) {
        let oldValue = isPaymentsVersionOutdatedCache.swap(value)
        guard oldValue != value else { return }
        NotificationCenter.default.postNotificationNameAsync(PaymentsConstants.isPaymentsVersionOutdatedDidChange, object: nil)
    }

    // MARK: - Incoming Messages

    public func processIncomingPaymentRequest(
        thread: TSThread,
        paymentRequest: TSPaymentRequest,
        transaction: SDSAnyWriteTransaction
    ) {
        // TODO: Handle requests.
        owsFailDebug("Not yet implemented.")
    }

    public func processIncomingPaymentNotification(
        thread: TSThread,
        paymentNotification: TSPaymentNotification,
        senderAddress: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("")
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

    public func processIncomingPaymentCancellation(
        thread: TSThread,
        paymentCancellation: TSPaymentCancellation,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("")
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

    public func processReceivedTranscriptPaymentRequest(
        thread: TSThread,
        paymentRequest: TSPaymentRequest,
        messageTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("")
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

    public func processReceivedTranscriptPaymentNotification(
        thread: TSThread,
        paymentNotification: TSPaymentNotification,
        messageTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("Ignoring payment notification from sync transcript.")
    }

    public func processReceivedTranscriptPaymentCancellation(
        thread: TSThread,
        paymentCancellation: TSPaymentCancellation,
        messageTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("")
        let requestUuidString = paymentCancellation.requestUuidString
        if let paymentRequestModel = Self.findPaymentRequestModel(forRequestUuidString: requestUuidString,
                                                                  expectedIsIncomingRequest: nil,
                                                                  transaction: transaction) {
            paymentRequestModel.anyRemove(transaction: transaction)
        }
    }

    public func processIncomingPaymentSyncMessage(
        _ paymentProto: SSKProtoSyncMessageOutgoingPayment,
        messageTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("")
        do {
            guard let mobileCoinProto = paymentProto.mobileCoin else {
                throw OWSAssertionError("Invalid payment sync message: Missing mobileCoinProto.")
            }
            var recipientServiceId: ServiceId?
            if let recipientServiceIdString = paymentProto.recipientServiceID {
                guard let serviceId = try? ServiceId.parseFrom(serviceIdString: recipientServiceIdString) else {
                    throw OWSAssertionError("Invalid payment sync message: Missing recipientServiceId.")
                }
                if !FeatureFlags.phoneNumberIdentifiers, serviceId is Pni {
                    throw OWSAssertionError("Invalid payment sync message: Unexpected Pni.")
                }
                recipientServiceId = serviceId
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
                  !mcReceiptData.isEmpty else {
                      throw OWSAssertionError("Invalid payment sync message: Missing or invalid receipt.")
                  }
            _ = try self.mobileCoinHelper.info(forReceiptData: mcReceiptData)
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
                guard recipientServiceId == nil else {
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
                guard recipientServiceId != nil else {
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
                                              addressUuidString: recipientServiceId?.serviceIdUppercaseString,
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
    public func tryToInsertPaymentModel(
        _ paymentModel: TSPaymentModel,
        transaction: SDSAnyWriteTransaction
    ) throws {

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

    // Incoming requests are for outgoing payments and vice versa.
    private class func findPaymentRequestModel(
        forRequestUuidString requestUuidString: String,
        expectedIsIncomingRequest: Bool?,
        transaction: SDSAnyReadTransaction
    ) -> TSPaymentRequestModel? {

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

    // This method enforces invariants around TSPaymentModel.
    private func isProposedPaymentModelRedundant(
        _ paymentModel: TSPaymentModel,
        transaction: SDSAnyWriteTransaction
    ) throws -> Bool {
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
                let otherSpentKeyImages = otherPaymentModel.mobileCoin?.spentKeyImages ?? []
                let otherOutputPublicKeys = otherPaymentModel.mobileCoin?.outputPublicKeys ?? []
                if !spentKeyImages.isDisjoint(with: otherSpentKeyImages) {
                    for value in spentKeyImages {
                        Logger.verbose("spentKeyImage: \(value.hexadecimalString)")
                    }
                    for value in otherSpentKeyImages {
                        Logger.verbose("otherSpentKeyImage: \(value.hexadecimalString)")
                    }
                    owsFailDebug("spentKeyImage conflict.")
                    return true
                }
                if !outputPublicKeys.isDisjoint(with: otherOutputPublicKeys) {
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

    // MARK: - Upsert Payment Records

    private func upsertPaymentModelForIncomingPaymentNotification(_ paymentNotification: TSPaymentNotification,
                                                                  thread: TSThread,
                                                                  senderAddress: SignalServiceAddress,
                                                                  transaction: SDSAnyWriteTransaction) {
        do {
            let mcReceiptData = paymentNotification.mcReceiptData
            let receiptInfo = try self.mobileCoinHelper.info(forReceiptData: mcReceiptData)

            let mobileCoin = MobileCoinPayment(recipientPublicAddressData: nil,
                                               transactionData: nil,
                                               receiptData: paymentNotification.mcReceiptData,
                                               incomingTransactionPublicKeys: [ receiptInfo.txOutPublicKey ],
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
