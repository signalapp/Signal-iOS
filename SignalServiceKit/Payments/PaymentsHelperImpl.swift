//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

final public class PaymentsHelperImpl: PaymentsHelperSwift, PaymentsHelper {

    public init() {
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
        RemoteConfig.current.paymentsResetKillSwitch || !hasValidPhoneNumberForPayments
    }

    public var hasValidPhoneNumberForPayments: Bool {
        guard DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return false
        }
        guard let localNumber = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.phoneNumber else {
            return false
        }
        let paymentsDisabledRegions = RemoteConfig.current.paymentsDisabledRegions
        if paymentsDisabledRegions.isEmpty {
            return Self.isValidPhoneNumberForPayments_fixedAllowlist(localNumber)
        } else {
            return Self.isValidPhoneNumberForPayments_remoteConfigBlocklist(localNumber, paymentsDisabledRegions: paymentsDisabledRegions)
        }
    }

    private static func isValidPhoneNumberForPayments_fixedAllowlist(_ e164: String) -> Bool {
        guard let phoneNumber = SSKEnvironment.shared.phoneNumberUtilRef.parseE164(e164) else {
            owsFailDebug("Could not parse phone number: \(e164).")
            return false
        }
        guard let callingCode = phoneNumber.getCallingCode() else {
            owsFailDebug("Missing callingCode: \(e164).")
            return false
        }
        let validCallingCodes: [Int] = [
            // France
            33,
            // Switzerland
            41,
            // Parts of UK.
            44,
            // Germany
            49
        ]
        return validCallingCodes.contains(callingCode)
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
    fileprivate static let keyValueStore = KeyValueStore(collection: "Payments")
    public var keyValueStore: KeyValueStore { Self.keyValueStore}

    private static let arePaymentsEnabledKey = "isPaymentEnabled"
    private static let paymentsEntropyKey = "paymentsEntropy"
    private static let lastKnownLocalPaymentAddressProtoDataKey = "lastKnownLocalPaymentAddressProtoData"

    private let paymentStateCache = AtomicOptional<PaymentsState>(nil, lock: .sharedGlobal)

    public func warmCaches() {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)

        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            self.paymentStateCache.set(Self.loadPaymentsState(transaction: transaction))
        }
    }

    public var paymentsState: PaymentsState {
        paymentStateCache.get() ?? .disabled
    }

    public var arePaymentsEnabled: Bool {
        paymentsState.isEnabled
    }

    public func arePaymentsEnabled(tx: DBReadTransaction) -> Bool {
        Self.loadPaymentsState(transaction: tx).isEnabled
    }

    public var paymentsEntropy: Data? {
        paymentsState.paymentsEntropy
    }

    public func enablePayments(transaction: DBWriteTransaction) {
        // We must preserve any existing paymentsEntropy, and then prefer "old" entropy, then last resort generate new entropy.
        let existingPaymentsEntropy = self.paymentsEntropy
        let oldPaymentsEntropy = Self.loadPaymentsState(transaction: transaction).paymentsEntropy
        let paymentsEntropy = existingPaymentsEntropy ?? oldPaymentsEntropy ?? Self.generateRandomPaymentsEntropy()
        _ = enablePayments(withPaymentsEntropy: paymentsEntropy, transaction: transaction)
    }

    public func enablePayments(withPaymentsEntropy newPaymentsEntropy: Data, transaction: DBWriteTransaction) -> Bool {
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

    public func disablePayments(transaction: DBWriteTransaction) {
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
                                 transaction: DBWriteTransaction) {
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
            return
        }
        if let oldPaymentsEntropy = oldPaymentsState.paymentsEntropy,
           let newPaymentsEntropy = newPaymentsState.paymentsEntropy,
           oldPaymentsEntropy != newPaymentsEntropy {
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

        SSKEnvironment.shared.paymentsEventsRef.updateLastKnownLocalPaymentAddressProtoData(transaction: transaction)

        let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)?.aci
        TSPaymentsActivationRequestModel
            .allThreadsWithPaymentActivationRequests(transaction: transaction)
            .forEach { thread in
                // Only send out payments activated messages from the originating device.
                if originatedLocally {
                    let message = OWSPaymentActivationRequestFinishedMessage(thread: thread, transaction: transaction)
                    let preparedMessage = PreparedOutgoingMessage.preprepared(
                        transientMessageWithoutAttachments: message
                    )
                    SSKEnvironment.shared.messageSenderJobQueueRef.add(
                        message: preparedMessage,
                        transaction: transaction
                    )
                }
                // But always insert an info message wherever we were requested.
                if let localAci {
                    let infoMessage = TSInfoMessage(
                        thread: thread,
                        messageType: .paymentsActivated,
                        infoMessageUserInfo: [
                            .paymentActivatedAci: localAci.serviceIdString
                        ]
                    )
                    infoMessage.anyInsert(transaction: transaction)
                }
            }
        // Regardless of where it was originated, wipe the pending activation request state.
        // Now that we have activated, they're useless.
        _ = try? TSPaymentsActivationRequestModel.deleteAll(transaction.database)

        transaction.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: PaymentsConstants.arePaymentsEnabledDidChange, object: nil)

            Task {
                SSKEnvironment.shared.paymentsEventsRef.paymentsStateDidChange()

                if originatedLocally {
                    // We only need to re-upload the profile if the change originated
                    // locally.
                    Logger.info("Re-uploading local profile due to payments state change.")
                    await DependenciesBridge.shared.db.awaitableWrite { tx in
                        _ = SSKEnvironment.shared.profileManagerRef.reuploadLocalProfile(
                            unsavedRotatedProfileKey: nil,
                            mustReuploadAvatar: false,
                            authedAccount: .implicit(),
                            tx: tx
                        )
                    }

                    SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
                }
            }
        }
    }

    private static func loadPaymentsState(transaction: DBReadTransaction) -> PaymentsState {
        guard DependenciesBridge.shared.tsAccountManager.registrationState(tx: transaction).isRegistered else {
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
        Randomness.generateRandomBytes(PaymentsConstants.paymentsEntropyLength)
    }

    public func clearState(transaction: DBWriteTransaction) {
        Self.keyValueStore.removeAll(transaction: transaction)

        paymentStateCache.set(nil)
    }

    public func setLastKnownLocalPaymentAddressProtoData(_ data: Data?, transaction: DBWriteTransaction) {
        Self.keyValueStore.setData(data, key: Self.lastKnownLocalPaymentAddressProtoDataKey, transaction: transaction)
    }

    public func lastKnownLocalPaymentAddressProtoData(transaction: DBWriteTransaction) -> Data? {
        SSKEnvironment.shared.paymentsEventsRef.updateLastKnownLocalPaymentAddressProtoData(transaction: transaction)
        return Self.keyValueStore.getData(Self.lastKnownLocalPaymentAddressProtoDataKey, transaction: transaction)
    }

    // MARK: -

    private static let arePaymentsEnabledForUserStore = KeyValueStore(collection: "arePaymentsEnabledForUserStore")

    public func setArePaymentsEnabled(for serviceId: ServiceId, hasPaymentsEnabled: Bool, transaction tx: DBWriteTransaction) {
        Self.arePaymentsEnabledForUserStore.setBool(hasPaymentsEnabled, key: serviceId.serviceIdUppercaseString, transaction: tx)
    }

    public func arePaymentsEnabled(for address: SignalServiceAddress, transaction tx: DBReadTransaction) -> Bool {
        guard let serviceId = address.serviceId else {
            Logger.warn("User is missing serviceId.")
            return false
        }
        return Self.arePaymentsEnabledForUserStore.getBool(
            serviceId.serviceIdUppercaseString,
            defaultValue: false,
            transaction: tx
        )
    }

    // MARK: - Version Compatibility

    private let isPaymentsVersionOutdatedCache = AtomicValue<Bool>(false, lock: .sharedGlobal)

    public var isPaymentsVersionOutdated: Bool {
        isPaymentsVersionOutdatedCache.get()
    }

    public func setPaymentsVersionOutdated(_ value: Bool) {
        let oldValue = isPaymentsVersionOutdatedCache.swap(value)
        guard oldValue != value else { return }
        NotificationCenter.default.postOnMainThread(name: PaymentsConstants.isPaymentsVersionOutdatedDidChange, object: nil)
    }

    // MARK: - Incoming Messages

    public func processIncomingPaymentNotification(
        thread: TSThread,
        paymentNotification: TSPaymentNotification,
        senderAci: Aci,
        transaction: DBWriteTransaction
    ) {
        Logger.info("")
        guard paymentNotification.isValid else {
            owsFailDebug("Invalid paymentNotification.")
            return
        }
        upsertPaymentModelForIncomingPaymentNotification(paymentNotification,
                                                         thread: thread,
                                                         senderAci: senderAci,
                                                         transaction: transaction)
    }

    public func processIncomingPaymentsActivationRequest(
        thread: TSThread,
        senderAci: Aci,
        transaction: DBWriteTransaction
    ) {
        Logger.info("")

        // If we are activated already, immediately reply and finish.
        // Only do this on the primary so we don't end up replying
        // multiple times across every device that is requested.
        if
            Self.loadPaymentsState(transaction: transaction).isEnabled
        {
            if DependenciesBridge.shared.tsAccountManager.registrationState(tx: transaction).isPrimaryDevice ?? false {
                let message = OWSPaymentActivationRequestFinishedMessage(thread: thread, transaction: transaction)
                let preparedMessage = PreparedOutgoingMessage.preprepared(
                    transientMessageWithoutAttachments: message
                )
                SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: transaction)
            }
            return
        }

        // Create a model; we use this after we activate payments to
        // know who requested we activate, so we can send them
        // a message telling them we activated.
        TSPaymentsActivationRequestModel.createIfNotExists(
            threadUniqueId: thread.uniqueId,
            senderAci: senderAci,
            transaction: transaction
        )
        // Insert the info message to display in chat.
        let infoMessage: TSInfoMessage = .paymentsActivationRequestMessage(
            thread: thread,
            senderAci: senderAci
        )
        infoMessage.anyInsert(transaction: transaction)
    }

    public func processIncomingPaymentsActivatedMessage(
        thread: TSThread,
        senderAci: Aci,
        transaction: DBWriteTransaction
    ) {
        Logger.info("")
        let infoMessage: TSInfoMessage = .paymentsActivatedMessage(
            thread: thread,
            senderAci: senderAci
        )
        infoMessage.anyInsert(transaction: transaction)

        setArePaymentsEnabled(
            for: senderAci,
            hasPaymentsEnabled: true,
            transaction: transaction
        )
    }

    public func processReceivedTranscriptPaymentNotification(
        thread: TSThread,
        paymentNotification: TSPaymentNotification,
        messageTimestamp: UInt64,
        transaction: DBWriteTransaction
    ) {
        Logger.info("Ignoring payment notification from sync transcript.")
    }

    public func processIncomingPaymentSyncMessage(
        _ paymentProto: SSKProtoSyncMessageOutgoingPayment,
        messageTimestamp: UInt64,
        transaction: DBWriteTransaction
    ) {
        Logger.info("")
        do {
            guard let mobileCoinProto = paymentProto.mobileCoin else {
                throw OWSAssertionError("Invalid payment sync message: Missing mobileCoinProto.")
            }
            var recipientAci: Aci?
            if let recipientAciString = paymentProto.recipientServiceID {
                guard let aci = Aci.parseFrom(aciString: recipientAciString) else {
                    throw OWSAssertionError("Invalid payment sync message: Missing recipientServiceID.")
                }
                recipientAci = aci
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
            let memoMessage = paymentProto.note?.nilIfEmpty.map {
                DependenciesBridge.shared.attachmentContentValidator.truncatedMessageBodyForInlining(
                    MessageBody(text: $0, ranges: .empty),
                    tx: transaction
                )
            }

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
            _ = try SSKEnvironment.shared.mobileCoinHelperRef.info(forReceiptData: mcReceiptData)
            let ledgerBlockIndex = mobileCoinProto.ledgerBlockIndex
            guard ledgerBlockIndex > 0 else {
                throw OWSAssertionError("Invalid payment sync message: Invalid ledgerBlockIndex.")
            }
            let ledgerBlockTimestamp = mobileCoinProto.ledgerBlockTimestamp
            // We use .outgoingComplete. We can safely assume that the device which
            // sent the payment has verified and notified.
            let paymentState: TSPaymentState = .outgoingComplete

            let paymentType: TSPaymentType
            if recipientPublicAddressData == nil {
                // Possible defragmentation.
                guard recipientAci == nil else {
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
                paymentType = .outgoingDefragmentationNotFromLocalDevice
            } else {
                // Possible outgoing payment.
                guard recipientAci != nil else {
                    throw OWSAssertionError("Invalid payment sync message: missing recipientUuid.")
                }
                guard paymentAmount.isValidAmount(canBeEmpty: false) else {
                    throw OWSAssertionError("Invalid payment sync message: invalid paymentAmount.")
                }
                paymentType = .outgoingPaymentNotFromLocalDevice
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
                                              createdDate: Date(millisecondsSince1970: messageTimestamp),
                                              senderOrRecipientAci: recipientAci.map { AciObjC($0) },
                                              memoMessage: memoMessage?.inlinedBody.text,
                                              isUnread: false,
                                              interactionUniqueId: nil,
                                              mobileCoin: mobileCoin)

            try tryToInsertPaymentModel(paymentModel, transaction: transaction)

            // If we inserted without error, its new (no duplicates) so we should
            // insert the outgoing message in chat.
            if
                paymentType == .outgoingPaymentNotFromLocalDevice,
                let recipientAci,
                recipientAci != DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction)?.aci
            {
                let thread = TSContactThread.getOrCreateThread(
                    withContactAddress: SignalServiceAddress(recipientAci),
                    transaction: transaction
                )
                let paymentNotification = TSPaymentNotification(
                    memoMessage: memoMessage?.inlinedBody.text,
                    mcReceiptData: mcReceiptData
                )
                let dmConfigurationStore = DependenciesBridge.shared.disappearingMessagesConfigurationStore
                let dmConfig = dmConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: transaction)
                let message = OWSOutgoingPaymentMessage(
                    thread: thread,
                    messageBody: memoMessage,
                    paymentNotification: paymentNotification,
                    expiresInSeconds: dmConfig.durationSeconds,
                    expireTimerVersion: dmConfig.timerVersion,
                    tx: transaction
                )
                message.anyInsert(transaction: transaction)
                paymentModel.update(withInteractionUniqueId: message.uniqueId, transaction: transaction)
            }
        } catch {
            owsFailDebug("Error: \(error)")
            return
        }
    }

    // This method enforces invariants around TSPaymentModel.
    public func tryToInsertPaymentModel(
        _ paymentModel: TSPaymentModel,
        transaction: DBWriteTransaction
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
    }

    // This method enforces invariants around TSPaymentModel.
    private func isProposedPaymentModelRedundant(
        _ paymentModel: TSPaymentModel,
        transaction: DBWriteTransaction
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
                    owsFailDebug("spentKeyImage conflict.")
                    return true
                }
                if !outputPublicKeys.isDisjoint(with: otherOutputPublicKeys) {
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
                                                                  senderAci: Aci,
                                                                  transaction: DBWriteTransaction) {
        do {
            let mcReceiptData = paymentNotification.mcReceiptData
            let receiptInfo = try SSKEnvironment.shared.mobileCoinHelperRef.info(forReceiptData: mcReceiptData)

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
                                              senderOrRecipientAci: AciObjC(senderAci),
                                              memoMessage: paymentNotification.memoMessage?.nilIfEmpty,
                                              isUnread: true,
                                              interactionUniqueId: nil,
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

public struct PaymentsPassphrase: Equatable {

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
