//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public protocol DisappearingMessagesConfigurationStore {
    typealias SetTokenResult = (
        oldConfiguration: DisappearingMessagesConfigurationRecord,
        newConfiguration: DisappearingMessagesConfigurationRecord,
    )

    func fetch(for scope: DisappearingMessagesConfigurationScope, tx: DBReadTransaction) -> DisappearingMessagesConfigurationRecord?

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
    func resetAllDMTimerVersions(tx: DBWriteTransaction)
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
    ) -> DisappearingMessagesConfigurationRecord {
        fetch(for: scope, tx: tx) ?? DisappearingMessagesConfigurationRecord(
            threadUniqueId: scope.persistenceKey,
            isEnabled: false,
            durationSeconds: 0,
            timerVersion: 1,
        )
    }

    public func durationSeconds(for thread: TSThread, tx: DBReadTransaction) -> UInt32 {
        fetchOrBuildDefault(for: .thread(thread), tx: tx).asToken.durationSeconds
    }
}

class DisappearingMessagesConfigurationStoreImpl: DisappearingMessagesConfigurationStore {
    private func baseQuery(forScope scope: DisappearingMessagesConfigurationScope) -> QueryInterfaceRequest<DisappearingMessagesConfigurationRecord> {
        return DisappearingMessagesConfigurationRecord
            .filter(Column(DisappearingMessagesConfigurationRecord.CodingKeys.threadUniqueId.rawValue) == scope.persistenceKey)
    }

    func fetch(for scope: DisappearingMessagesConfigurationScope, tx: DBReadTransaction) -> DisappearingMessagesConfigurationRecord? {
        let fetchQuery = baseQuery(forScope: scope)
        guard var result = failIfThrows(block: { try fetchQuery.fetchOne(tx.database) }) else {
            return nil
        }
        // What's in the database may have a nonzero duration but isEnabled=false.
        // Normalize so if isEnabled is false, duration is 0.
        if !result.isEnabled {
            result.durationSeconds = 0
        }
        return result
    }

    @discardableResult
    func set(
        token: VersionedDisappearingMessageToken,
        for scope: DisappearingMessagesConfigurationScope,
        tx: DBWriteTransaction,
    ) -> SetTokenResult {
        var configuration = fetchOrBuildDefault(for: scope, tx: tx)
        let oldConfiguration = configuration

        switch scope {
        case .thread(let thread) where thread is TSContactThread:
            if token.version == 0 {
                Logger.error("Dropping DM timer update for contact thread with version 0!")
                return (oldConfiguration, oldConfiguration)
            }

            if token.version < oldConfiguration.timerVersion {
                Logger.info("Dropping DM timer update for contact thread with outdated version. \(token.version) < \(oldConfiguration.timerVersion)")
                return (oldConfiguration, oldConfiguration)
            }
        case .universal, .thread:
            break
        }

        if token.version != 0 {
            configuration.timerVersion = token.version
        }
        configuration.isEnabled = token.isEnabled
        configuration.durationSeconds = token.durationSeconds

        let scopeDescription = switch scope {
        case .thread(let thread): "\(type(of: thread))"
        case .universal: "universal"
        }
        Logger.info("Setting \(scopeDescription) DM timer.")

        if configuration.id == nil {
            failIfThrows {
                try configuration.insert(tx.database)
            }
        } else if oldConfiguration.asVersionedToken != configuration.asVersionedToken {
            failIfThrows {
                try configuration.update(tx.database)
            }
        }

        return (oldConfiguration, configuration)
    }

    func remove(for thread: TSThread, tx: DBWriteTransaction) {
        failIfThrows {
            try baseQuery(forScope: .thread(thread)).deleteAll(tx.database)
        }
    }

    func resetAllDMTimerVersions(tx: DBWriteTransaction) {
        failIfThrows {
            try DisappearingMessagesConfigurationRecord.updateAll(tx.database, [
                Column(DisappearingMessagesConfigurationRecord.CodingKeys.timerVersion.rawValue).set(to: 1),
            ])
        }
    }
}

#if TESTABLE_BUILD

class MockDisappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore {
    var values = [String: DisappearingMessagesConfigurationRecord]()

    func fetch(for scope: DisappearingMessagesConfigurationScope, tx: DBReadTransaction) -> DisappearingMessagesConfigurationRecord? {
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
        let newConfiguration = DisappearingMessagesConfigurationRecord(
            threadUniqueId: scope.persistenceKey,
            isEnabled: token.isEnabled,
            durationSeconds: token.durationSeconds,
            timerVersion: newVersion,
        )
        values[scope.persistenceKey] = newConfiguration
        return (oldConfiguration, newConfiguration)
    }

    func remove(for thread: TSThread, tx: DBWriteTransaction) {
        values[thread.uniqueId] = nil
    }

    func resetAllDMTimerVersions(tx: DBWriteTransaction) {
        values.forEach { key, value in
            values[key] = DisappearingMessagesConfigurationRecord(
                threadUniqueId: value.threadUniqueId,
                isEnabled: value.isEnabled,
                durationSeconds: value.durationSeconds,
                timerVersion: 1,
            )
        }
    }
}

#endif
