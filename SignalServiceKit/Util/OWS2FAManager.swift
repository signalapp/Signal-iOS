//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public let kMin2FAv2PinLength: UInt = 4

public class OWS2FAManager {
    private var accountAttributesUpdater: AccountAttributesUpdater { DependenciesBridge.shared.accountAttributesUpdater }
    private var accountKeyStore: AccountKeyStore { DependenciesBridge.shared.accountKeyStore }
    private var db: DB { DependenciesBridge.shared.db }
    private var networkManager: NetworkManagerProtocol { SSKEnvironment.shared.networkManagerRef }
    private var svr: SecureValueRecovery { DependenciesBridge.shared.svr }
    private var tsAccountManager: TSAccountManager { DependenciesBridge.shared.tsAccountManager }

    private let keyValueStore = NewKeyValueStore(collection: "2FA")

    private enum StoreKeys {
        static let isRegistrationLockEnabled = "IsRegistrationLockEnabled"
        static let areRemindersEnabled = "AreRemindersEnabled"
        static let lastSuccessfulReminderDate = "LastSuccessfulReminderDate"
        static let pinCode = "PinCode"
        static let repetitionInterval = "RepetitionInterval"
        static let hasEverHadPin = "HasEverHadPin"
    }

    init() {
        // Does not take dependencies on init, because circular dependencies
        // abound in this class and I did not have the motivation to break them.

        SwiftSingletons.register(self)
    }

    // MARK: -

    public var isRegistrationLockV2Enabled: Bool {
        return db.read { isRegistrationLockV2Enabled(transaction: $0) }
    }

    public func isRegistrationLockV2Enabled(transaction: DBReadTransaction) -> Bool {
        return keyValueStore.fetchValue(
            Bool.self,
            forKey: StoreKeys.isRegistrationLockEnabled,
            tx: transaction,
        ) ?? false
    }

    // MARK: -

    public func hasEverHadPin(tx: DBReadTransaction) -> Bool {
        return keyValueStore.fetchValue(Bool.self, forKey: StoreKeys.hasEverHadPin, tx: tx) ?? false
    }

    public var isPinEnabledWithSneakyTransaction: Bool {
        return db.read { isPinEnabled(tx: $0) }
    }

    public func isPinEnabled(tx: DBReadTransaction) -> Bool {
        return pinCode(transaction: tx) != nil
    }

    public func pinCode(transaction: DBReadTransaction) -> String? {
        return keyValueStore.fetchValue(String.self, forKey: StoreKeys.pinCode, tx: transaction)
    }

    public enum PinType {
        case numeric
        case alphanumeric

        public static func forPin(_ pin: String) -> Self {
            let normalizedPin = SVRUtil.normalizePin(pin)
            return normalizedPin.digitsOnly() == normalizedPin ? .numeric : .alphanumeric
        }
    }

    // MARK: -

    public enum PinReminderRepetitionInterval: TimeInterval {
        case oneDay
        case threeDays
        case oneWeek
        case twoWeeks
        case fourWeeks

        /// Manual implementation because `RawRepresentable` requires you to use
        /// a literal in the raw value, so `.day` and such don't work.
        public init?(rawValue: TimeInterval) {
            switch rawValue {
            case Self.oneDay.rawValue: self = .oneDay
            case Self.threeDays.rawValue: self = .threeDays
            case Self.oneWeek.rawValue: self = .oneWeek
            case Self.twoWeeks.rawValue: self = .twoWeeks
            case Self.fourWeeks.rawValue: self = .fourWeeks
            default: return nil
            }
        }

        public var rawValue: TimeInterval {
            switch self {
            case .oneDay: 1 * .day
            case .threeDays: 3 * .day
            case .oneWeek: 1 * .week
            case .twoWeeks: 2 * .week
            case .fourWeeks: 4 * .week
            }
        }
    }

    public func repetitionInterval(tx: DBReadTransaction) -> PinReminderRepetitionInterval {
        if
            let persisted = keyValueStore.fetchValue(
                Double.self,
                forKey: StoreKeys.repetitionInterval,
                tx: tx,
            ).flatMap({ PinReminderRepetitionInterval(rawValue: $0) })
        {
            return persisted
        }

        return .oneDay
    }

    public func setRepetitionInterval(
        _ interval: PinReminderRepetitionInterval?,
        tx: DBWriteTransaction,
    ) {
        if let interval {
            keyValueStore.writeValue(interval.rawValue, forKey: StoreKeys.repetitionInterval, tx: tx)
        } else {
            keyValueStore.removeValue(forKey: StoreKeys.repetitionInterval, tx: tx)
        }
    }

    // MARK: -

    public var areRemindersEnabled: Bool {
        return db.read { areRemindersEnabled(transaction: $0) }
    }

    public func areRemindersEnabled(transaction: DBReadTransaction) -> Bool {
        return keyValueStore.fetchValue(Bool.self, forKey: StoreKeys.areRemindersEnabled, tx: transaction) ?? true
    }

    public func setAreRemindersEnabled(_ areRemindersEnabled: Bool, transaction: DBWriteTransaction) {
        keyValueStore.writeValue(areRemindersEnabled, forKey: StoreKeys.areRemindersEnabled, tx: transaction)
    }

    // MARK: -

    private func lastCompletedReminderDate(tx: DBReadTransaction) -> Date? {
        return keyValueStore.fetchValue(Date.self, forKey: StoreKeys.lastSuccessfulReminderDate, tx: tx)
    }

    private func setLastCompletedReminderDate(_ date: Date, tx: DBWriteTransaction) {
        keyValueStore.writeValue(date, forKey: StoreKeys.lastSuccessfulReminderDate, tx: tx)
    }

    private func nextReminderDate(tx: DBReadTransaction) -> Date {
        let lastCompletedReminderDate = lastCompletedReminderDate(tx: tx) ?? .distantPast
        let repetitionInterval = repetitionInterval(tx: tx)

        return lastCompletedReminderDate.addingTimeInterval(repetitionInterval.rawValue)
    }

    public func isDueForV2Reminder(transaction tx: DBReadTransaction) -> Bool {
        guard
            tsAccountManager.registrationState(tx: tx).isRegistered,
            isPinEnabled(tx: tx),
            areRemindersEnabled(transaction: tx)
        else {
            return false
        }

        return nextReminderDate(tx: tx) < Date()
    }

    // MARK: -

    public enum PinReminderRepetitionIntervalAdjustment {
        case setTo(PinReminderRepetitionInterval)
        case shorter
        case longer
    }

    public func recordReminderCompleted(
        repetitionIntervalAdjustment: PinReminderRepetitionIntervalAdjustment?,
        tx: DBWriteTransaction,
    ) {
        setLastCompletedReminderDate(Date(), tx: tx)

        let currentInterval = repetitionInterval(tx: tx)
        let newInterval: PinReminderRepetitionInterval
        if let repetitionIntervalAdjustment {
            newInterval = switch (repetitionIntervalAdjustment, currentInterval) {
            case (.setTo(let _newInterval), _): _newInterval
            case (.shorter, .oneDay): .oneDay
            case (.longer, .oneDay): .threeDays
            case (.shorter, .threeDays): .oneDay
            case (.longer, .threeDays): .oneWeek
            case (.shorter, .oneWeek): .threeDays
            case (.longer, .oneWeek): .twoWeeks
            case (.shorter, .twoWeeks): .oneWeek
            case (.longer, .twoWeeks): .fourWeeks
            case (.shorter, .fourWeeks): .twoWeeks
            case (.longer, .fourWeeks): .fourWeeks
            }
        } else {
            newInterval = currentInterval
        }

        Logger.info("Updating repetition interval: \(currentInterval) -> \(newInterval).")
        setRepetitionInterval(newInterval, tx: tx)
    }

    // MARK: -

    public func verifyPin(_ pin: String, tx: DBReadTransaction) -> Bool {
        let pinToMatch = pinCode(transaction: tx)
        owsAssertDebug(pinToMatch != nil, "can't verify pin when 2fa is disabled")
        return SVRUtil.normalizePin(pin) == pinToMatch
    }

    // MARK: -

    public func markDisabled(transaction tx: DBWriteTransaction) {
        keyValueStore.removeValue(forKey: StoreKeys.pinCode, tx: tx)
        keyValueStore.removeValue(forKey: StoreKeys.isRegistrationLockEnabled, tx: tx)
        tx.addSyncCompletion {
            self.triggerAccountAttributesUpdate()
        }
    }

    public func clearLocalPinCode(transaction: DBWriteTransaction) {
        keyValueStore.removeValue(forKey: StoreKeys.pinCode, tx: transaction)
    }

    /// Marks the given PIN as enabled locally.
    /// - SeeAlso ``enablePin(_:)``
    public func markEnabled(
        pin: String,
        resetReminderInterval: Bool,
        transaction: DBWriteTransaction,
    ) {
        owsPrecondition(!pin.isEmpty)

        setNormalizedPin(pin, tx: transaction)

        if resetReminderInterval {
            // Reset the reminder repetition interval for the new pin.
            setRepetitionInterval(nil, tx: transaction)
            // Schedule next reminder relative to now
            setLastCompletedReminderDate(Date(), tx: transaction)
        }

        transaction.addSyncCompletion {
            self.triggerAccountAttributesUpdate()
        }
    }

    public func restorePinFromBackup(_ pin: String, transaction: DBWriteTransaction) {
        setNormalizedPin(pin, tx: transaction)
    }

    private func setNormalizedPin(_ pin: String, tx: DBWriteTransaction) {
        owsPrecondition(!pin.isEmpty)

        keyValueStore.writeValue(pin, forKey: StoreKeys.pinCode, tx: tx)
        keyValueStore.writeValue(true, forKey: StoreKeys.hasEverHadPin, tx: tx)
    }

    // MARK: -

    /// "Enables" the PIN by using it to back up the master key, then setting
    /// local state as appropriate.
    ///
    /// - Important
    /// This does not enable reglock. See ``enableRegistrationLockV2()``.
    public func enablePin(_ pin: String) async throws {
        owsAssertDebug(!pin.isEmpty)

        // Enabling V2 2FA doesn't inherently enable registration lock,
        // it's managed by a separate setting.
        let aep = db.read { tx in accountKeyStore.getAccountEntropyPool(tx: tx) }
        guard let aep else {
            throw OWSAssertionError("missing aep")
        }

        try await svr.backupMasterKey(
            pin: pin,
            masterKey: aep.getMasterKey(),
            force: false,
            authMethod: .implicit,
        )

        await db.awaitableWrite { tx in
            markEnabled(pin: pin, resetReminderInterval: true, transaction: tx)
        }
    }

    // MARK: -

    public func enableRegistrationLockV2(logger: PrefixedLogger) async throws {
        let aep = db.read { tx in accountKeyStore.getAccountEntropyPool(tx: tx) }
        guard let aep else {
            throw OWSAssertionError("can't enable registration lock without an aep")
        }

        let token = aep.getMasterKey().deriveRegistrationLock()
        let request = OWSRequestFactory.enableRegistrationLockV2Request(token: token, logger: logger)
        _ = try await networkManager.asyncRequest(request)

        await db.awaitableWrite { transaction in
            keyValueStore.writeValue(
                true,
                forKey: StoreKeys.isRegistrationLockEnabled,
                tx: transaction,
            )
        }

        triggerAccountAttributesUpdate()
    }

    public func markRegistrationLockV2Enabled(transaction: DBWriteTransaction) {
        guard !tsAccountManager.registrationState(tx: transaction).isRegistered else {
            return owsFailDebug("Unexpectedly attempted to mark reglock as enabled after registration")
        }

        keyValueStore.writeValue(
            true,
            forKey: StoreKeys.isRegistrationLockEnabled,
            tx: transaction,
        )
    }

    public func disableRegistrationLockV2() async throws {
        let request = OWSRequestFactory.disableRegistrationLockV2Request()
        _ = try await networkManager.asyncRequest(request)

        await db.awaitableWrite { transaction in
            keyValueStore.removeValue(
                forKey: StoreKeys.isRegistrationLockEnabled,
                tx: transaction,
            )
        }

        triggerAccountAttributesUpdate()
    }

    // MARK: -

    private func triggerAccountAttributesUpdate() {
        Task {
            do {
                try await accountAttributesUpdater.updateAccountAttributes(authedAccount: .implicit())
            } catch {
                Logger.warn("\(error)")
            }
        }
    }

    // MARK: -

    public static func isWeakPin(_ pin: String) -> Bool {
        let normalizedPin = SVRUtil.normalizePin(pin)

        guard pin.count >= kMin2FAv2PinLength else { return true }

        // We only check numeric pins for weakness
        guard normalizedPin.digitsOnly() == normalizedPin else { return false }

        var allTheSame = true
        var forwardSequential = true
        var reverseSequential = true

        var previousWholeNumberValue: Int?
        for character in normalizedPin {
            guard let current = character.wholeNumberValue else {
                owsFailDebug("numeric pin unexpectedly contatined non-numeric characters")
                break
            }

            defer { previousWholeNumberValue = current }
            guard let previous = previousWholeNumberValue else { continue }

            if previous != current { allTheSame = false }
            if previous + 1 != current { forwardSequential = false }
            if previous - 1 != current { reverseSequential = false }

            if !allTheSame, !forwardSequential, !reverseSequential { break }
        }

        return allTheSame || forwardSequential || reverseSequential
    }
}
