//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

final public class IncrementalTSAttachmentMigrationStore {

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

    public func getState(tx: DBReadTransaction) -> State {
        return (try? kvStore.getCodableValue(forKey: State.key, transaction: tx)) ?? .unstarted
    }

    public func setState(_ state: State, tx: DBWriteTransaction) throws {
        try kvStore.setCodable(state, key: State.key, transaction: tx)
    }

    // MARK: - Errors

    /// Value should be incremented when we apply a forward fix to the TSAttachment migration.
    /// When this value changes, users who had previously failed to migrate and are now skipping the migration
    /// will attempt to migrate once again.
    /// v1 = initial launch
    /// v2 = bug where we'd count migrations that got interrupted by app termination before finishing one batch
    ///    as "failed"; we increment the number so they retry now that this is resolved.
    /// v3 = a couple failures that mostly look like db corruption; added db corruption checks.
    private static let currentMigrationVersion = 3
    /// NOTE: in reality one more attempt than this number may happen before we give up. This is because
    /// we count an attempt as successful if it completes a single batch; if a subsequent batch fails the attempt
    /// was still counted as success so we will try again (with the failing batch now being the first batch) and
    /// a second failure in the now-first batch will count as a failed attempt and prevent future attempts.
    private static let maxNumAttemptsBeforeSkipping = 2
    private static let lastMigrationAttemptVersionKey = "TSAttachmentMigration_lastMigrationAttemptVersionKey"
    private static let lastMigrationAttemptDateKey = "TSAttachmentMigration_lastMigrationAttemptDateKey"
    private static let migrationIncompleteAttemptCountKey = "TSAttachmentMigration_migrationIncompleteAttemptCountKey"
    private static let didReportFailureInUIKey = "TSAttachmentMigration_didReportFailureInUIKey"

    public func shouldAttemptMigrationUntilFinished() -> Bool {
        let lastAttemptVersion = userDefaults.integer(forKey: Self.lastMigrationAttemptVersionKey)
        if lastAttemptVersion != Self.currentMigrationVersion {
            return true
        }
        let lastAttemptDate: Date? = userDefaults.object(forKey: Self.lastMigrationAttemptDateKey) as? Date
        if Date().timeIntervalSince((lastAttemptDate ?? .distantPast)) >= .week {
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
        userDefaults.set(Date(), forKey: Self.lastMigrationAttemptDateKey)
        userDefaults.set(prevIncompleteAttemptCount + 1, forKey: Self.migrationIncompleteAttemptCountKey)
        userDefaults.set(false, forKey: Self.didReportFailureInUIKey)
    }

    public func didSucceedMigrationBatch() {
        userDefaults.set(0, forKey: Self.migrationIncompleteAttemptCountKey)
        userDefaults.set(Date(), forKey: Self.lastMigrationAttemptDateKey)
        userDefaults.set(false, forKey: Self.didReportFailureInUIKey)
    }

    public func didEarlyExitBeforeAttemptingBatch() {
        let prevIncompleteAttemptCount = userDefaults.integer(forKey: Self.migrationIncompleteAttemptCountKey)
        guard prevIncompleteAttemptCount > 0 else {
            owsFailDebug("Not marked as making an attempt")
            return
        }
        userDefaults.set(prevIncompleteAttemptCount - 1, forKey: Self.migrationIncompleteAttemptCountKey)
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
    private static let hasLoggedBgProcessingTaskErrorKey = "TSAttachmentMigration_hasLoggedBGProcessingTaskErrorKey"

    public func bgProcessingTaskDidExperienceError(logString: String) {
        userDefaults.set(logString, forKey: Self.bgProcessingTaskErrorKey)
        userDefaults.setValue(false, forKey: Self.hasLoggedBgProcessingTaskErrorKey)
    }

    /// Returns (error string, has been logged before)
    public func consumeLastBGProcessingTaskError() -> (String, Bool)? {
        let value = userDefaults.string(forKey: Self.bgProcessingTaskErrorKey)
        guard let value else { return nil }
        let wasLoggedBefore = userDefaults.bool(forKey: Self.hasLoggedBgProcessingTaskErrorKey)
        if !wasLoggedBefore {
            userDefaults.setValue(true, forKey: Self.hasLoggedBgProcessingTaskErrorKey)
        }
        return (value, wasLoggedBefore)
    }

    // MARK: Checkpoints

    private static let lastCheckpointKey = "TSAttachmentMigration_lastCheckpointKey"

    public func saveLastCheckpoint(_ checkpointString: String) {
        userDefaults.set(checkpointString, forKey: Self.lastCheckpointKey)
    }

    public func getLastCheckpoint() -> String? {
        userDefaults.string(forKey: Self.lastCheckpointKey)
    }
}
