//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
extension AppSetup {
    /// Set up the ``DependenciesBridge`` singleton. See that class for more
    /// details as to its purpose.
    ///
    /// Important that this happen during app setup, to ensure that singletons
    /// in ``DependenciesBridge`` are available to singletons downstream in the
    /// app setup dependencies graph.
    static func setupDependenciesBridge(
        databaseStorage: SDSDatabaseStorage,
        tsAccountManager: TSAccountManager,
        signalService: OWSSignalServiceProtocol,
        storageServiceManager: StorageServiceManagerProtocol,
        syncManager: SyncManagerProtocol,
        ows2FAManager: OWS2FAManager
    ) {
        DependenciesBridge.setupSingleton(
            databaseStorage: databaseStorage,
            tsAccountManager: tsAccountManager,
            signalService: signalService,
            storageServiceManager: storageServiceManager,
            syncManager: syncManager,
            ows2FAManager: ows2FAManager
        )
    }
}
