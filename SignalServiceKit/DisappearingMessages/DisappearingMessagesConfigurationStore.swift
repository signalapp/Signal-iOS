//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol DisappearingMessagesConfigurationStore {
    typealias SetTokenResult = (
        oldConfiguration: OWSDisappearingMessagesConfiguration,
        newConfiguration: OWSDisappearingMessagesConfiguration,
    )

    func fetch(for scope: DisappearingMessagesConfigurationScope, tx: DBReadTransaction) -> OWSDisappearingMessagesConfiguration?

    func remove(for thread: TSThread, tx: DBWriteTransaction)

    @discardableResult
    func set(
        token: VersionedDisappearingMessageToken,
        for scope: DisappearingMessagesConfigurationScope,
        tx: DBWriteTransaction,
    ) -> SetTokenResult

    /// Keep all DM timers, but reset their versions.
    /// Done when we may become out of sync with our other devices and need
    /// to reset versions to get back in sync. For example, if we are a linked device
    /// that becomes delinked, if a new primary device registers from an empty DB
    /// its DM timer versions will all reset to 0. They should override ours so we
    /// have to reset ourselves.
    func resetAllDMTimerVersions(tx: DBWriteTransaction) throws
}

extension DisappearingMessagesConfigurationStore {

    /// Convenience method for group threads to pass an unversioned token.
    @discardableResult
    func set(
        token: DisappearingMessageToken,
        for groupThread: TSGroupThread,
        tx: DBWriteTransaction,
    ) -> SetTokenResult {
        set(
            token: .forGroupThread(
                isEnabled: token.isEnabled,
                durationSeconds: token.durationSeconds,
            ),
            for: .thread(groupThread),
            tx: tx,
        )
    }

    /// Convenience method for the universal timer to pass an unversioned token.
    @discardableResult
    func setUniversalTimer(
        token: DisappearingMessageToken,
        tx: DBWriteTransaction,
    ) -> SetTokenResult {
        set(
            token: .forUniversalTimer(
                isEnabled: token.isEnabled,
                durationSeconds: token.durationSeconds,
            ),
            for: .universal,
            tx: tx,
        )
    }
}

public enum DisappearingMessagesConfigurationScope {
    case universal
    case thread(TSThread)

    private enum Constants {
        /// The persistence key for the global setting for new chats.
        static let universalThreadId = "kUniversalTimerThreadId"
    }

    fileprivate var persistenceKey: String {
        switch self {
        case .universal:
            return Constants.universalThreadId
        case .thread(let thread):
            return thread.uniqueId
        }
    }
}

extension DisappearingMessagesConfigurationStore {
    public func fetchOrBuildDefault(
        for scope: DisappearingMessagesConfigurationScope,
        tx: DBReadTransaction,
    ) -> OWSDisappearingMessagesConfiguration {
        fetch(for: scope, tx: tx) ?? OWSDisappearingMessagesConfiguration(
            threadId: scope.persistenceKey,
            enabled: false,
            durationSeconds: 0,
            timerVersion: 1,
        )
    }

    public func durationSeconds(for thread: TSThread, tx: DBReadTransaction) -> UInt32 {
        fetchOrBuildDefault(for: .thread(thread), tx: tx).asToken.durationSeconds
    }
}

class DisappearingMessagesConfigurationStoreImpl: DisappearingMessagesConfigurationStore {
    func fetch(for scope: DisappearingMessagesConfigurationScope, tx: DBReadTransaction) -> OWSDisappearingMessagesConfiguration? {
        guard
            let config = OWSDisappearingMessagesConfiguration.anyFetch(
                uniqueId: scope.persistenceKey,
                transaction: tx,
            )
        else {
            return nil
        }
        // What's in the database may have a nonzero duration but isEnabled=false.
        // Normalize so if isEnabled is false, duration is 0.
        if !config.isEnabled, config.durationSeconds != 0 {
            return config.copy(withDurationSeconds: 0, timerVersion: config.timerVersion)
        }
        return config
    }

    @discardableResult
    func set(
        token: VersionedDisappearingMessageToken,
        for scope: DisappearingMessagesConfigurationScope,
        tx: DBWriteTransaction,
    ) -> SetTokenResult {
        let oldConfiguration = fetchOrBuildDefault(for: scope, tx: tx)
        if
            token.version > 0,
            case let .thread(thread) = scope,
            thread is TSContactThread
        {
            // We got a dm timer; check against the version we have locally and reject if lower.
            if token.version < oldConfiguration.timerVersion {
                Logger.info("Dropping DM timer update with outdated version")
                return (oldConfiguration, oldConfiguration)
            }
        }
        let newVersion = token.version == 0 ? oldConfiguration.timerVersion : token.version
        let newConfiguration = (
            token.isEnabled
                ? oldConfiguration.copyAsEnabled(withDurationSeconds: token.durationSeconds, timerVersion: newVersion)
                : oldConfiguration.copy(withIsEnabled: false, timerVersion: newVersion),
        )
        if newConfiguration.grdbId == nil || newConfiguration != oldConfiguration {
            newConfiguration.anyUpsert(transaction: tx)
        }
        return (oldConfiguration, newConfiguration)
    }

    func remove(for thread: TSThread, tx: DBWriteTransaction) {
        fetch(for: .thread(thread), tx: tx)?.anyRemove(transaction: tx)
    }

    func resetAllDMTimerVersions(tx: DBWriteTransaction) throws {
        try tx.database.execute(sql: """
            UPDATE \(OWSDisappearingMessagesConfigurationSerializer.table.tableName)
            SET \(OWSDisappearingMessagesConfigurationSerializer.timerVersionColumn.columnName) = 1;
        """)
    }
}

#if TESTABLE_BUILD

class MockDisappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore {
    var values = [String: OWSDisappearingMessagesConfiguration]()

    func fetch(for scope: DisappearingMessagesConfigurationScope, tx: DBReadTransaction) -> OWSDisappearingMessagesConfiguration? {
        values[scope.persistenceKey]
    }

    @discardableResult
    func set(
        token: VersionedDisappearingMessageToken,
        for scope: DisappearingMessagesConfigurationScope,
        tx: DBWriteTransaction,
    ) -> SetTokenResult {
        let oldConfiguration = fetchOrBuildDefault(for: scope, tx: tx)
        let newVersion = oldConfiguration.timerVersion
        let newConfiguration = OWSDisappearingMessagesConfiguration(
            threadId: scope.persistenceKey,
            enabled: token.isEnabled,
            durationSeconds: token.durationSeconds,
            timerVersion: newVersion,
        )
        values[scope.persistenceKey] = newConfiguration
        return (oldConfiguration, newConfiguration)
    }

    func remove(for thread: TSThread, tx: DBWriteTransaction) {
        values[thread.uniqueId] = nil
    }

    func resetAllDMTimerVersions(tx: DBWriteTransaction) throws {
        values.forEach { key, value in
            values[key] = OWSDisappearingMessagesConfiguration(
                threadId: value.uniqueId,
                enabled: value.isEnabled,
                durationSeconds: value.durationSeconds,
                timerVersion: 1,
            )
        }
    }
}

#endif
