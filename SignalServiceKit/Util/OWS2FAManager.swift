//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public let kMin2FAv2PinLength: UInt = 4

private let kOWS2FAManager_IsRegistrationLockV2Enabled = "isRegistrationLockV2Enabled"
private let kOWS2FAManager_AreRemindersEnabled = "kOWS2FAManager_AreRemindersEnabled"
private let kOWS2FAManager_LastSuccessfulReminderDateKey = "kOWS2FAManager_LastSuccessfulReminderDateKey"
private let kOWS2FAManager_PinCode = "kOWS2FAManager_PinCode"
private let kOWS2FAManager_RepetitionInterval = "kOWS2FAManager_RepetitionInterval"

public class OWS2FAManager {
    private var accountAttributesUpdater: AccountAttributesUpdater { DependenciesBridge.shared.accountAttributesUpdater }
    private var accountKeyStore: AccountKeyStore { DependenciesBridge.shared.accountKeyStore }
    private var db: DB { DependenciesBridge.shared.db }
    private var keyValueStore: KeyValueStore { KeyValueStore(collection: "kOWS2FAManager_Collection") }
    private var networkManager: NetworkManagerProtocol { SSKEnvironment.shared.networkManagerRef }
    private var svr: SecureValueRecovery { DependenciesBridge.shared.svr }
    private var tsAccountManager: TSAccountManager { DependenciesBridge.shared.tsAccountManager }

    init() {
        // Does not take dependencies on init, because circular dependencies
        // abound in this class and I did not have the motivation to break them.

        SwiftSingletons.register(self)
    }

    // MARK: -

    public var is2FAEnabled: Bool {
        return db.read { svr.hasBackedUpMasterKey(transaction: $0) }
    }

    public var isRegistrationLockV2Enabled: Bool {
        return db.read { isRegistrationLockV2Enabled(transaction: $0) }
    }
    public func isRegistrationLockV2Enabled(transaction: DBReadTransaction) -> Bool {
        return keyValueStore.getBool(
            kOWS2FAManager_IsRegistrationLockV2Enabled,
            defaultValue: false,
            transaction: transaction
        )
    }

    // MARK: -

    public var pinCode: String? {
        return db.read { pinCode(transaction: $0) }
    }
    public func pinCode(transaction: DBReadTransaction) -> String? {
        return keyValueStore.getString(kOWS2FAManager_PinCode, transaction: transaction)
    }

    // MARK: -

    static var allRepetitionIntervals: [TimeInterval] = [12 * .hour, 1 * .day, 3 * .day, 7 * .day, 14 * .day]
    var defaultRepetitionInterval: TimeInterval {
        return Self.allRepetitionIntervals.first!
    }
    public func setDefaultRepetitionInterval(transaction: DBWriteTransaction) {
        keyValueStore.removeValue(forKey: kOWS2FAManager_RepetitionInterval, transaction: transaction)
    }
    public var repetitionInterval: TimeInterval {
        return db.read { repetitionInterval(transaction: $0) }
    }
    func repetitionInterval(transaction: DBReadTransaction) -> TimeInterval {
        return keyValueStore.getDouble(kOWS2FAManager_RepetitionInterval, defaultValue: defaultRepetitionInterval, transaction: transaction)
    }

    // MARK: -

    public var areRemindersEnabled: Bool {
        return db.read { areRemindersEnabled(transaction: $0) }
    }
    public func areRemindersEnabled(transaction: DBReadTransaction) -> Bool {
        return keyValueStore.getBool(kOWS2FAManager_AreRemindersEnabled, defaultValue: true, transaction: transaction)
    }
    public func setAreRemindersEnabled(_ areRemindersEnabled: Bool, transaction: DBWriteTransaction) {
        keyValueStore.setBool(areRemindersEnabled, key: kOWS2FAManager_AreRemindersEnabled, transaction: transaction)
    }

    // MARK: -

    public func lastCompletedReminderDate(transaction: DBReadTransaction) -> Date? {
        return keyValueStore.getDate(kOWS2FAManager_LastSuccessfulReminderDateKey, transaction: transaction)
    }
    public func setLastCompletedReminderDate(_ date: Date, transaction: DBWriteTransaction) {
        keyValueStore.setDate(date, key: kOWS2FAManager_LastSuccessfulReminderDateKey, transaction: transaction)
    }
    public func nextReminderDate(transaction: DBReadTransaction) -> Date {
        let lastCompletedReminderDate = lastCompletedReminderDate(transaction: transaction) ?? .distantPast
        let repetitionInterval = repetitionInterval(transaction: transaction)

        return lastCompletedReminderDate.addingTimeInterval(repetitionInterval)
    }

    public func isDueForV2Reminder(transaction: DBReadTransaction) -> Bool {
        guard tsAccountManager.registrationState(tx: transaction).isRegistered else { return false }
        guard svr.hasBackedUpMasterKey(transaction: transaction) else { return false }
        if pinCode(transaction: transaction).isEmptyOrNil {
            Logger.info("Missing 2FA pin, prompting for reminder so we can backfill it.")
            return true
        }
        guard areRemindersEnabled(transaction: transaction) else { return false }

        return nextReminderDate(transaction: transaction) < Date()
    }

    public func reminderCompleted(incorrectAttempts: Bool) {
        db.write { transaction in
            setLastCompletedReminderDate(Date(), transaction: transaction)

            let oldInterval = repetitionInterval(transaction: transaction)
            let newInterval = adjustRepetitionInterval(oldInterval: oldInterval, incorrectAttempts: incorrectAttempts)

            Logger.info("Updating repetition interval: \(oldInterval) -> \(newInterval). Had incorrect attempts: \(incorrectAttempts)")
            keyValueStore.setDouble(newInterval, key: kOWS2FAManager_RepetitionInterval, transaction: transaction)
        }
    }

    private func adjustRepetitionInterval(oldInterval: TimeInterval, incorrectAttempts: Bool) -> TimeInterval {
        let allIntervals = Self.allRepetitionIntervals
        guard let oldIndex = allIntervals.firstIndex(where: { oldInterval <= $0 }) else {
            return allIntervals.first!
        }
        let newIndex: Int
        if incorrectAttempts {
            newIndex = oldIndex <= 0 ? 0 : oldIndex - 1
        } else {
            newIndex = oldIndex < allIntervals.count - 1 ? oldIndex + 1 : oldIndex
        }

        return allIntervals[newIndex]
    }

    // MARK: -

    public func verifyPin(_ pin: String, result: @escaping (Bool) -> Void) {
        let pinToMatch = pinCode

        if is2FAEnabled {
            if let pinToMatch, !pinToMatch.isEmpty {
                result(pinToMatch == SVRUtil.normalizePin(pin))
            } else {
                svr.verifyPin(pin) { isValid in
                    result(isValid)

                    if isValid {
                        Logger.info("Verified PIN code")
                        self.db.write { self.setPinCode(pin, transaction: $0) }
                    }
                }
            }
        } else {
            owsFailDebug("unexpectedly attempting to verify pin when 2fa is disabled")
            result(false)
        }
    }

    // MARK: -

    public func markDisabled(transaction tx: DBWriteTransaction) {
        keyValueStore.removeValue(forKey: kOWS2FAManager_PinCode, transaction: tx)
        keyValueStore.removeValue(forKey: kOWS2FAManager_IsRegistrationLockV2Enabled, transaction: tx)
        tx.addSyncCompletion {
            self.triggerAccountAttributesUpdate()
        }
    }

    public func clearLocalPinCode(transaction: DBWriteTransaction) {
        keyValueStore.removeValue(forKey: kOWS2FAManager_PinCode, transaction: transaction)
    }

    public func markEnabled(pin: String, transaction: DBWriteTransaction) {
        setPinCode(pin, transaction: transaction)

        // Reset the reminder repetition interval for the new pin.
        setDefaultRepetitionInterval(transaction: transaction)

        // Schedule next reminder relative to now
        setLastCompletedReminderDate(Date(), transaction: transaction)

        transaction.addSyncCompletion {
            self.triggerAccountAttributesUpdate()
        }
    }

    public func restorePinFromBackup(_ pin: String, transaction: DBWriteTransaction) {
        keyValueStore.setString(pin, key: kOWS2FAManager_PinCode, transaction: transaction)
    }

    private func setPinCode(_ pin: String, transaction: DBWriteTransaction) {
        if pin.isEmpty {
            clearLocalPinCode(transaction: transaction)
            return
        }

        let pin = SVRUtil.normalizePin(pin)
        keyValueStore.setString(pin, key: kOWS2FAManager_PinCode, transaction: transaction)
    }

    // MARK: -

    @MainActor
    public func requestEnable2FA(withPin pin: String) async throws {
        owsAssertDebug(!pin.isEmpty)

        // Enabling V2 2FA doesn't inherently enable registration lock,
        // it's managed by a separate setting.
        guard let masterKey = db.read(block: {
            accountKeyStore.getMasterKey(tx: $0)
        }) else {
            throw OWSAssertionError("Missing master key")
        }

        _ = try await svr.backupMasterKey(
            pin: pin,
            masterKey: masterKey,
            authMethod: .implicit
        ).awaitable()

        await db.awaitableWrite { tx in
            markEnabled(pin: pin, transaction: tx)
        }
    }

    public func disable2FA() {
        if is2FAEnabled {
            Task {
                do {
                    try await self.svr.deleteKeys().awaitable()
                    try await self.disableRegistrationLockV2()
                } catch {
                }
                await db.awaitableWrite { self.markDisabled(transaction: $0) }
            }
        } else {
            owsFailDebug("Unexpectedly attempting to disable 2fa for disabled mode")
        }
    }

    // MARK: -

    public func enableRegistrationLockV2() async throws {
        let token = db.read { tx in
            let masterKey = accountKeyStore.getMasterKey(tx: tx)
            return masterKey?.data(
                for: .registrationLock
            ).canonicalStringRepresentation
        }
        guard let token else {
            throw OWSAssertionError("Cannot enable registration lock without an existing PIN")
        }

        let request = OWSRequestFactory.enableRegistrationLockV2Request(token: token)
        _ = try await networkManager.asyncRequest(request)

        await db.awaitableWrite { transaction in
            keyValueStore.setBool(
                true,
                key: kOWS2FAManager_IsRegistrationLockV2Enabled,
                transaction: transaction
            )
        }

        triggerAccountAttributesUpdate()
    }

    public func markRegistrationLockV2Enabled(transaction: DBWriteTransaction) {
        guard !tsAccountManager.registrationState(tx: transaction).isRegistered else {
            return owsFailDebug("Unexpectedly attempted to mark reglock as enabled after registration")
        }

        keyValueStore.setBool(
            true,
            key: kOWS2FAManager_IsRegistrationLockV2Enabled,
            transaction: transaction
        )
    }

    public func disableRegistrationLockV2() async throws {
        let request = OWSRequestFactory.disableRegistrationLockV2Request()
        _ = try await networkManager.asyncRequest(request)

        await db.awaitableWrite { transaction in
            keyValueStore.removeValue(
                forKey: kOWS2FAManager_IsRegistrationLockV2Enabled,
                transaction: transaction
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

            if !allTheSame && !forwardSequential && !reverseSequential { break }
        }

        return allTheSame || forwardSequential || reverseSequential
    }
}
