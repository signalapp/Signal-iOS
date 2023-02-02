//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Temporary bridge between [legacy code that uses global accessors for manager instances]
/// and [new code that expects references to instances to be explicitly passed around].
///
/// Ideally, all references to dependencies (singletons or otherwise) are passed to a class
/// in its initializer. Most existing code is not written that way, and expects to pull dependencies
/// from global static state (e.g. `SSKEnvironment` and `Dependencies`)
///
/// This lets you put off piping through references many layers deep to the usage site,
/// and access global state but with a few advantages over legacy methods:
/// 1) Not a protocol + extension; you must explicitly access members via the shared instance
/// 2) Swift-only, no need for @objc
/// 3) Classes within this container should themselves adhere to modern design principles: NOT accessing
///   global state or `Dependencies`, being protocolized, taking all dependencies
///   explicitly on initialization, and encapsulated for easy testing.
///
/// It is preferred **NOT** to use this class, and to take dependencies on init instead, but it is
/// better to use this class than to use `Dependencies`.
public class DependenciesBridge {

    public static let shared = DependenciesBridge()

    public let db: DB
    public let keyValueStoreFactory: KeyValueStoreFactory

    public let kbsCredentialStorage: KBSAuthCredentialStorage
    public let keyBackupService: KeyBackupServiceProtocol

    private init() {
        self.db = SDSDB(databaseStorage: GlobalDependencies.databaseStorage)
        self.keyValueStoreFactory = SDSKeyValueStoreFactory()
        self.kbsCredentialStorage = KBSAuthCredentialStorageImpl(keyValueStoreFactory: keyValueStoreFactory)
        self.keyBackupService = KeyBackupService(
            accountManager: KBS.Wrappers.TSAccountManager(GlobalDependencies.tsAccountManager),
            appContext: CurrentAppContext(),
            credentialStorage: kbsCredentialStorage,
            databaseStorage: db,
            keyValueStoreFactory: keyValueStoreFactory,
            remoteAttestation: KBS.Wrappers.RemoteAttestation(),
            signalService: GlobalDependencies.signalService,
            storageServiceManager: KBS.Wrappers.StorageServiceManager(GlobalDependencies.storageServiceManager),
            syncManager: GlobalDependencies.syncManager,
            tsConstants: TSConstants.shared,
            twoFAManager: KBS.Wrappers.OWS2FAManager(OWS2FAManager.shared)
        )
    }

    private struct GlobalDependencies: Dependencies {}
}
