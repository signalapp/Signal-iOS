//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public let kMin2FAv2PinLength: UInt = 4
public let kLegacyTruncated2FAv1PinLength: UInt = 16

private let kOWS2FAManager_AreRemindersEnabled = "kOWS2FAManager_AreRemindersEnabled"
private let kOWS2FAManager_HasMigratedTruncatedPinKey = "kOWS2FAManager_HasMigratedTruncatedPinKey"
private let kOWS2FAManager_LastSuccessfulReminderDateKey = "kOWS2FAManager_LastSuccessfulReminderDateKey"
private let kOWS2FAManager_PinCode = "kOWS2FAManager_PinCode"
private let kOWS2FAManager_RepetitionInterval = "kOWS2FAManager_RepetitionInterval"

public enum OWS2FAMode {
    case disabled
    case V1
    case V2
}

public class OWS2FAManager {
    init(appReadiness: AppReadiness) {
        SwiftSingletons.register(self)

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            if self.mode == .V1 {
                Logger.info("Migrating V1 reglock to V2 reglock")

                Task {
                    do {
                        try await self.migrateToRegistrationLockV2()
                        Logger.info("Successfully migrated to registration lock V2")
                    } catch {
                        owsFailDebug("Failed to migrate V1 reglock to V2 reglock: \(error.userErrorDescription)")
                    }
                }
            }
        }
    }
}

extension OWS2FAManager {

    public static var keyValueStore = KeyValueStore(collection: "kOWS2FAManager_Collection")
    public static var isRegistrationLockV2EnabledKey = "isRegistrationLockV2Enabled"

    public var mode: OWS2FAMode {
        let hasBackedUpMasterKey = SSKEnvironment.shared.databaseStorageRef.read { self.hasBackedUpMasterKey(transaction: $0) }
        if hasBackedUpMasterKey {
            return .V2
        } else if pinCode != nil {
            return .V1
        } else {
            return .disabled
        }
    }

    public var is2FAEnabled: Bool {
        return mode != .disabled
    }

    public var isRegistrationLockEnabled: Bool {
        switch mode {
        case .V2:
            return isRegistrationLockV2Enabled
        case .V1:
            return true // In v1 reg lock and 2fa are the same thing.
        case .disabled:
            return false
        }
    }

    public var isRegistrationLockV2Enabled: Bool {
        return SSKEnvironment.shared.databaseStorageRef.read { isRegistrationLockV2Enabled(transaction: $0) }
    }
    public func isRegistrationLockV2Enabled(transaction: SDSAnyReadTransaction) -> Bool {
        return Self.keyValueStore.getBool(
            OWS2FAManager.isRegistrationLockV2EnabledKey,
            defaultValue: false,
            transaction: transaction.asV2Read
        )
    }

    public var pinCode: String? {
        return SSKEnvironment.shared.databaseStorageRef.read { pinCode(transaction: $0) }
    }
    public func pinCode(transaction: SDSAnyReadTransaction) -> String? {
        return Self.keyValueStore.getString(kOWS2FAManager_PinCode, transaction: transaction.asV2Read)
    }

    static var allRepetitionIntervals: [TimeInterval] = [12 * kHourInterval, 1 * kDayInterval, 3 * kDayInterval, 7 * kDayInterval, 14 * kDayInterval]
    var defaultRepetitionInterval: TimeInterval {
        return Self.allRepetitionIntervals.first!
    }
    public func setDefaultRepetitionInterval(transaction: SDSAnyWriteTransaction) {
        Self.keyValueStore.removeValue(forKey: kOWS2FAManager_RepetitionInterval, transaction: transaction.asV2Write)
    }
    public var repetitionInterval: TimeInterval {
        return SSKEnvironment.shared.databaseStorageRef.read { repetitionInterval(transaction: $0) }
    }
    func repetitionInterval(transaction: SDSAnyReadTransaction) -> TimeInterval {
        return Self.keyValueStore.getDouble(kOWS2FAManager_RepetitionInterval, defaultValue: defaultRepetitionInterval, transaction: transaction.asV2Read)
    }

    public var areRemindersEnabled: Bool {
        return SSKEnvironment.shared.databaseStorageRef.read { areRemindersEnabled(transaction: $0) }
    }
    public func areRemindersEnabled(transaction: SDSAnyReadTransaction) -> Bool {
        return Self.keyValueStore.getBool(kOWS2FAManager_AreRemindersEnabled, defaultValue: true, transaction: transaction.asV2Read)
    }
    public func setAreRemindersEnabled(_ areRemindersEnabled: Bool, transaction: SDSAnyWriteTransaction) {
        Self.keyValueStore.setBool(areRemindersEnabled, key: kOWS2FAManager_AreRemindersEnabled, transaction: transaction.asV2Write)
    }

    public func lastCompletedReminderDate(transaction: SDSAnyReadTransaction) -> Date? {
        return Self.keyValueStore.getDate(kOWS2FAManager_LastSuccessfulReminderDateKey, transaction: transaction.asV2Read)
    }
    public func setLastCompletedReminderDate(_ date: Date, transaction: SDSAnyWriteTransaction) {
        Self.keyValueStore.setDate(date, key: kOWS2FAManager_LastSuccessfulReminderDateKey, transaction: transaction.asV2Write)
    }
    public func nextReminderDate(transaction: SDSAnyReadTransaction) -> Date {
        let lastCompletedReminderDate = lastCompletedReminderDate(transaction: transaction) ?? .distantPast
        let repetitionInterval = repetitionInterval(transaction: transaction)

        return lastCompletedReminderDate.addingTimeInterval(repetitionInterval)
    }

    public func isDueForV2Reminder(transaction: SDSAnyReadTransaction) -> Bool {
        guard DependenciesBridge.shared.tsAccountManager.registrationState(tx: transaction.asV2Read).isRegistered else { return false }
        guard hasBackedUpMasterKey(transaction: transaction) else { return false }
        if pinCode(transaction: transaction).isEmptyOrNil {
            Logger.info("Missing 2FA pin, prompting for reminder so we can backfill it.")
            return true
        }
        guard areRemindersEnabled(transaction: transaction) else { return false }

        return nextReminderDate(transaction: transaction) < Date()
    }

    public func reminderCompleted(incorrectAttempts: Bool) {
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            setLastCompletedReminderDate(Date(), transaction: transaction)

            let oldInterval = repetitionInterval(transaction: transaction)
            let newInterval = adjustRepetitionInterval(oldInterval: oldInterval, incorrectAttempts: incorrectAttempts)

            Logger.info("Updating repetition interval: \(oldInterval) -> \(newInterval). Had incorrect attempts: \(incorrectAttempts)")
            Self.keyValueStore.setDouble(newInterval, key: kOWS2FAManager_RepetitionInterval, transaction: transaction.asV2Write)
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

    public func verifyPin(_ pin: String, result: @escaping (Bool) -> Void) {
        let pinToMatch = pinCode

        switch mode {
        case .V2:
            if let pinToMatch, !pinToMatch.isEmpty {
                result(pinToMatch == SVRUtil.normalizePin(pin))
            } else {
                verifyKBSPin(pin) { isValid in
                    result(isValid)

                    if isValid {
                        Logger.info("Verified PIN code")
                        SSKEnvironment.shared.databaseStorageRef.write { self.setPinCode(pin, transaction: $0) }
                    }
                }
            }
        case .V1:
            // Convert the pin to arabic numerals, we never want to
            // operate with pins in other numbering systems.
            if let pinToMatch {
                result(pinToMatch.ensureArabicNumerals == pin.ensureArabicNumerals)
            } else {
                result(false)
            }
        case .disabled:
            owsFailDebug("unexpectedly attempting to verify pin when 2fa is disabled")
            result(false)
        }
    }

    public var needsLegacyPinMigration: Bool {
        let hasMigratedTruncatedPin = SSKEnvironment.shared.databaseStorageRef.read { Self.keyValueStore.getBool(kOWS2FAManager_HasMigratedTruncatedPinKey, defaultValue: false, transaction: $0.asV2Read) }
        if hasMigratedTruncatedPin {
            return false
        }

        // Older versions of the app truncated newly created pins to 16 characters. We no longer do that.
        // If we detect that the user's pin is the truncated length and it was created before we stopped
        // truncating pins, we'll need to ensure we migrate to the user's entire pin next time we prompt
        // them for it.
        if mode == .V1 && (pinCode?.count ?? 0) >= kLegacyTruncated2FAv1PinLength {
            return true
        }

        // We don't need to migrate this pin, either because it's v2 or short enough that
        // we never truncated it. Mark it as complete so we don't need to check again.
        SSKEnvironment.shared.databaseStorageRef.write { markLegacyPinAsMigrated(transaction: $0) }
        return false
    }
    internal func markLegacyPinAsMigrated(transaction: SDSAnyWriteTransaction) {
        Self.keyValueStore.setBool(true, key: kOWS2FAManager_HasMigratedTruncatedPinKey, transaction: transaction.asV2Write)
    }

    public func markDisabled(transaction: SDSAnyWriteTransaction) {
        Self.keyValueStore.removeValues(forKeys: [kOWS2FAManager_PinCode, Self.isRegistrationLockV2EnabledKey], transaction: transaction.asV2Write)
        transaction.addSyncCompletion {
            Self.triggerAccountAttributesUpdate()
        }
    }

    public func markEnabled(pin: String, transaction: SDSAnyWriteTransaction) {
        setPinCode(pin, transaction: transaction)

        // Since we just created this pin, we know it doesn't need migration. Mark it as such.
        markLegacyPinAsMigrated(transaction: transaction)

        // Reset the reminder repetition interval for the new pin.
        setDefaultRepetitionInterval(transaction: transaction)

        // Schedule next reminder relative to now
        setLastCompletedReminderDate(Date(), transaction: transaction)

        transaction.addSyncCompletion {
            Self.triggerAccountAttributesUpdate()
        }
    }

    internal func setPinCode(_ pin: String, transaction: SDSAnyWriteTransaction) {
        if pin.isEmpty {
            clearLocalPinCode(transaction: transaction)
            return
        }

        var pin = pin
        if hasBackedUpMasterKey(transaction: transaction) {
            pin = SVRUtil.normalizePin(pin)
        } else {
            // Convert the pin to arabic numerals, we never want to
            // operate with pins in other numbering systems.
            pin = pin.ensureArabicNumerals
        }

        Self.keyValueStore.setString(pin, key: kOWS2FAManager_PinCode, transaction: transaction.asV2Write)
    }

    public func requestEnable2FA(withPin pin: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            requestEnable2FA(pin: pin, success: {
                continuation.resume()
            }) { error in
                continuation.resume(throwing: error)
            }
        }
    }

    @discardableResult
    private static func triggerAccountAttributesUpdate() -> Task<(), Never> {
        return Task {
            do {
                try await DependenciesBridge.shared.accountAttributesUpdater.updateAccountAttributes(authedAccount: .implicit())
            } catch {
                Logger.warn("\(error)")
            }
        }
    }

    public func requestEnable2FA(pin: String, success: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        owsAssertDebug(!pin.isEmpty)

        // Enabling V2 2FA doesn't inherently enable registration lock,
        // it's managed by a separate setting.
        DependenciesBridge.shared.svr.generateAndBackupKeys(pin: pin, authMethod: .implicit).done {
            AssertIsOnMainThread()
            SSKEnvironment.shared.databaseStorageRef.write { self.markEnabled(pin: pin, transaction: $0) }
            success()
        }.catch { error in
            AssertIsOnMainThread()
            failure(error)
        }
    }

    public func disable2FA() {
        switch mode {
        case .V2:
            Task {
                do {
                    try await DependenciesBridge.shared.svr.deleteKeys().awaitable()
                    try await self.disableRegistrationLockV2()
                } catch {
                }
                await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { self.markDisabled(transaction: $0) }
            }
        case .V1:
            disable2FAV1()
        case .disabled:
            owsFailDebug("Unexpectedly attempting to disable 2fa for disabled mode")
        }
    }

    public func enableRegistrationLockV2() async throws {
        let token = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return DependenciesBridge.shared.svrKeyDeriver.data(
                for: .registrationLock,
                tx: tx.asV2Read
            )?.canonicalStringRepresentation
        }
        guard let token else {
            throw OWSAssertionError("Cannot enable registration lock without an existing PIN")
        }

        let request = OWSRequestFactory.enableRegistrationLockV2Request(token: token)
        _ = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request)

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            Self.keyValueStore.setBool(
                true,
                key: OWS2FAManager.isRegistrationLockV2EnabledKey,
                transaction: transaction.asV2Write
            )
        }

        Self.triggerAccountAttributesUpdate()
    }

    public func markRegistrationLockV2Enabled(transaction: SDSAnyWriteTransaction) {
        guard !DependenciesBridge.shared.tsAccountManager.registrationState(tx: transaction.asV2Read).isRegistered else {
            return owsFailDebug("Unexpectedly attempted to mark reglock as enabled after registration")
        }

        Self.keyValueStore.setBool(
            true,
            key: OWS2FAManager.isRegistrationLockV2EnabledKey,
            transaction: transaction.asV2Write
        )
    }

    public func disableRegistrationLockV2() async throws {
        let request = OWSRequestFactory.disableRegistrationLockV2Request()
        _ = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request)

        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            Self.keyValueStore.removeValue(
                forKey: OWS2FAManager.isRegistrationLockV2EnabledKey,
                transaction: transaction.asV2Write
            )
        }

        Self.triggerAccountAttributesUpdate()
    }

    public func migrateToRegistrationLockV2() async throws {
        guard let pinCode = pinCode else {
            throw OWSAssertionError("tried to migrate to registration lock V2 without legacy PIN")
        }

        try await requestEnable2FA(withPin: pinCode)
        try await enableRegistrationLockV2()
    }

    private func disable2FAV1() {
        Task {
            do {
                let request = OWSRequestFactory.disable2FARequest()
                _ = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request)
                await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                    self.markDisabled(transaction: transaction)
                }
            } catch {
                owsFailDebugUnlessNetworkFailure(error)
            }
        }
    }

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

    public func clearLocalPinCode(transaction: SDSAnyWriteTransaction) {
        Self.keyValueStore.removeValue(forKey: kOWS2FAManager_PinCode, transaction: transaction.asV2Write)
    }

    // MARK: - KeyBackupService Wrappers/Helpers

    public func hasBackedUpMasterKey(transaction: SDSAnyReadTransaction) -> Bool {
        return DependenciesBridge.shared.svr.hasBackedUpMasterKey(transaction: transaction.asV2Read)
    }

    public func verifyKBSPin(_ pin: String, resultHandler: @escaping (Bool) -> Void) {
        DependenciesBridge.shared.svr.verifyPin(pin, resultHandler: resultHandler)
    }
}
