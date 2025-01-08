//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol IncrementalMessageTSAttachmentMigratorFactory {

    func migrator(
        appContext: AppContext,
        appReadiness: AppReadiness,
        databaseStorage: SDSDatabaseStorage,
        remoteConfigManager: RemoteConfigManager,
        tsAccountManager: TSAccountManager
    ) -> IncrementalMessageTSAttachmentMigrator
}

public class IncrementalMessageTSAttachmentMigratorFactoryImpl: IncrementalMessageTSAttachmentMigratorFactory {

    private let store: IncrementalTSAttachmentMigrationStore

    public init(store: IncrementalTSAttachmentMigrationStore) {
        self.store = store
    }

    public func migrator(
        appContext: AppContext,
        appReadiness: AppReadiness,
        databaseStorage: SDSDatabaseStorage,
        remoteConfigManager: RemoteConfigManager,
        tsAccountManager: TSAccountManager
    ) -> IncrementalMessageTSAttachmentMigrator {
        return IncrementalMessageTSAttachmentMigratorImpl(
            appContext: appContext,
            appReadiness: appReadiness,
            databaseStorage: databaseStorage,
            remoteConfigManager: remoteConfigManager,
            store: store,
            tsAccountManager: tsAccountManager
        )
    }
}

public class NoOpIncrementalMessageTSAttachmentMigratorFactory: IncrementalMessageTSAttachmentMigratorFactory {

    public init() {}

    public func migrator(
        appContext: AppContext,
        appReadiness: AppReadiness,
        databaseStorage: SDSDatabaseStorage,
        remoteConfigManager: RemoteConfigManager,
        tsAccountManager: TSAccountManager
    ) -> IncrementalMessageTSAttachmentMigrator {
        return NoOpIncrementalMessageTSAttachmentMigrator()
    }
}

#if TESTABLE_BUILD

public class IncrementalMessageTSAttachmentMigratorFactoryMock: IncrementalMessageTSAttachmentMigratorFactory {

    public init() {}

    public func migrator(
        appContext: AppContext,
        appReadiness: AppReadiness,
        databaseStorage: SDSDatabaseStorage,
        remoteConfigManager: RemoteConfigManager,
        tsAccountManager: TSAccountManager
    ) -> IncrementalMessageTSAttachmentMigrator {
        return IncrementalMessageTSAttachmentMigratorMock()
    }
}

#endif
