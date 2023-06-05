//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol DisappearingMessagesConfigurationStore {
    func fetch(for scope: DisappearingMessagesConfigurationScope, tx: DBReadTransaction) -> OWSDisappearingMessagesConfiguration?

    func remove(for thread: TSThread, tx: DBWriteTransaction)

    @discardableResult
    func set(
        token: DisappearingMessageToken,
        for scope: DisappearingMessagesConfigurationScope,
        tx: DBWriteTransaction
    ) -> (oldConfiguration: OWSDisappearingMessagesConfiguration, newConfiguration: OWSDisappearingMessagesConfiguration)
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
        tx: DBReadTransaction
    ) -> OWSDisappearingMessagesConfiguration {
        fetch(for: scope, tx: tx) ?? OWSDisappearingMessagesConfiguration(
            threadId: scope.persistenceKey,
            enabled: false,
            durationSeconds: 0
        )
    }

    public func durationSeconds(for thread: TSThread, tx: DBReadTransaction) -> UInt32 {
        fetchOrBuildDefault(for: .thread(thread), tx: tx).asToken.durationSeconds
    }
}

class DisappearingMessagesConfigurationStoreImpl: DisappearingMessagesConfigurationStore {
    func fetch(for scope: DisappearingMessagesConfigurationScope, tx: DBReadTransaction) -> OWSDisappearingMessagesConfiguration? {
        OWSDisappearingMessagesConfiguration.anyFetch(uniqueId: scope.persistenceKey, transaction: SDSDB.shimOnlyBridge(tx))
    }

    @discardableResult
    func set(
        token: DisappearingMessageToken,
        for scope: DisappearingMessagesConfigurationScope,
        tx: DBWriteTransaction
    ) -> (oldConfiguration: OWSDisappearingMessagesConfiguration, newConfiguration: OWSDisappearingMessagesConfiguration) {
        let oldConfiguration = fetchOrBuildDefault(for: scope, tx: tx)
        let newConfiguration = (
            token.isEnabled
            ? oldConfiguration.copyAsEnabled(withDurationSeconds: token.durationSeconds)
            : oldConfiguration.copy(withIsEnabled: false)
        )
        if newConfiguration.grdbId == nil || newConfiguration != oldConfiguration {
            newConfiguration.anyUpsert(transaction: SDSDB.shimOnlyBridge(tx))
        }
        return (oldConfiguration, newConfiguration)
    }

    func remove(for thread: TSThread, tx: DBWriteTransaction) {
        fetch(for: .thread(thread), tx: tx)?.anyRemove(transaction: SDSDB.shimOnlyBridge(tx))
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
        token: DisappearingMessageToken,
        for scope: DisappearingMessagesConfigurationScope,
        tx: DBWriteTransaction
    ) -> (oldConfiguration: OWSDisappearingMessagesConfiguration, newConfiguration: OWSDisappearingMessagesConfiguration) {
        let oldConfiguration = fetchOrBuildDefault(for: scope, tx: tx)
        let newConfiguration = OWSDisappearingMessagesConfiguration(
            threadId: scope.persistenceKey,
            enabled: token.isEnabled,
            durationSeconds: token.durationSeconds
        )
        values[scope.persistenceKey] = newConfiguration
        return (oldConfiguration, newConfiguration)
    }

    func remove(for thread: TSThread, tx: DBWriteTransaction) {
        values[thread.uniqueId] = nil
    }
}

#endif
