//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class IncrementalTSAttachmentMigrationStore {

    public enum State: Int, Codable {
        case unstarted
        case started
        case finished

        static let key = "state"
    }

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    private let kvStore = KeyValueStore(collection: "IncrementalMessageTSAttachmentMigrator")

    public func getState(tx: SDSAnyReadTransaction) -> State {
        return (try? kvStore.getCodableValue(forKey: State.key, transaction: tx.asV2Read)) ?? .unstarted
    }

    public func setState(_ state: State, tx: SDSAnyWriteTransaction) throws {
        try kvStore.setCodable(state, key: State.key, transaction: tx.asV2Write)
    }

    // MARK: - Errors

    /// Value should be incremented when we apply a forward fix to the TSAttachment migration.
    /// When this value changes, users who had previously failed to migrate and are now skipping the migration
    /// will attempt to migrate once again.
    private static let currentMigrationVersion = 1
    /// NOTE: in reality one more attempt than this number may happen before we give up. This is because
    /// we count an attempt as successful if it completes a single batch; if a subsequent batch fails the attempt
    /// was still counted as success so we will try again (with the failing batch now being the first batch) and
    /// a second failure in the now-first batch will count as a failed attempt and prevent future attempts.
    private static let maxNumAttemptsBeforeSkipping = 1
    private static let lastMigrationAttemptVersionKey = "TSAttachmentMigration_lastMigrationAttemptVersionKey"
    private static let migrationIncompleteAttemptCountKey = "TSAttachmentMigration_migrationIncompleteAttemptCountKey"
    private static let didReportFailureInUIKey = "TSAttachmentMigration_didReportFailureInUIKey"

    public func shouldAttemptMigrationUntilFinished() -> Bool {
        let lastAttemptVersion = userDefaults.integer(forKey: Self.lastMigrationAttemptVersionKey)
        if lastAttemptVersion != Self.currentMigrationVersion {
            return true
        }
        let incompleteAttemptCount = userDefaults.integer(forKey: Self.migrationIncompleteAttemptCountKey)
        return incompleteAttemptCount < Self.maxNumAttemptsBeforeSkipping
    }

    public func willAttemptMigrationUntilFinished() {
        let lastAttemptVersion = userDefaults.integer(forKey: Self.lastMigrationAttemptVersionKey)
        let prevIncompleteAttemptCount: Int
        if lastAttemptVersion == Self.currentMigrationVersion {
            prevIncompleteAttemptCount = userDefaults.integer(forKey: Self.migrationIncompleteAttemptCountKey)
        } else {
            prevIncompleteAttemptCount = 0
        }
        userDefaults.set(Self.currentMigrationVersion, forKey: Self.lastMigrationAttemptVersionKey)
        userDefaults.set(prevIncompleteAttemptCount + 1, forKey: Self.migrationIncompleteAttemptCountKey)
        userDefaults.set(false, forKey: Self.didReportFailureInUIKey)
    }

    public func didSucceedMigrationBatch() {
        userDefaults.set(0, forKey: Self.migrationIncompleteAttemptCountKey)
        userDefaults.set(false, forKey: Self.didReportFailureInUIKey)
    }

    public func shouldReportFailureInUI() -> Bool {
        if userDefaults.bool(forKey: Self.didReportFailureInUIKey) {
            return false
        }
        return !shouldAttemptMigrationUntilFinished()
    }

    public func didReportFailureInUI() {
        userDefaults.set(true, forKey: Self.didReportFailureInUIKey)
    }

    // MARK: BGProcessingTask

    private static let bgProcessingTaskErrorKey = "TSAttachmentMigration_bgProcessingTaskErrorKey"

    public func bgProcessingTaskDidExperienceError(logString: String) {
        userDefaults.set(logString, forKey: Self.bgProcessingTaskErrorKey)
    }

    public func consumeLastBGProcessingTaskError() -> String? {
        let value = userDefaults.string(forKey: Self.bgProcessingTaskErrorKey)
        userDefaults.removeObject(forKey: Self.bgProcessingTaskErrorKey)
        return value
    }
}
