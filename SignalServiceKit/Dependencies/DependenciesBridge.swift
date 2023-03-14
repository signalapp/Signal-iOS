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

    /// Only available after calling `setupSingleton(...)`.
    public static var shared: DependenciesBridge {
        guard let _shared else {
            owsFail("DependenciesBridge has not yet been set up!")
        }

        return _shared
    }
    private static var _shared: DependenciesBridge?

    public let schedulers: Schedulers

    public let db: DB
    public let keyValueStoreFactory: KeyValueStoreFactory

    public let changePhoneNumberPniManager: ChangePhoneNumberPniManager

    public let kbsCredentialStorage: KBSAuthCredentialStorage
    public let keyBackupService: KeyBackupService

    public let registrationSessionManager: RegistrationSessionManager

    public let usernameLookupManager: UsernameLookupManager
    public let usernameEducationManager: UsernameEducationManager
    public let usernameValidationManager: UsernameValidationManager

    /// Initialize and configure the ``DependenciesBridge`` singleton.
    fileprivate static func setupSingleton(
        accountServiceClient: AccountServiceClient,
        databaseStorage: SDSDatabaseStorage,
        identityManager: OWSIdentityManager,
        messageProcessor: MessageProcessor,
        messageSender: MessageSender,
        networkManager: NetworkManager,
        ows2FAManager: OWS2FAManager,
        pniProtocolStore: SignalProtocolStore,
        signalService: OWSSignalServiceProtocol,
        storageServiceManager: StorageServiceManagerProtocol,
        syncManager: SyncManagerProtocol,
        tsAccountManager: TSAccountManager
    ) {
        _shared = .init(
            accountServiceClient: accountServiceClient,
            databaseStorage: databaseStorage,
            identityManager: identityManager,
            messageProcessor: messageProcessor,
            messageSender: messageSender,
            networkManager: networkManager,
            ows2FAManager: ows2FAManager,
            pniProtocolStore: pniProtocolStore,
            signalService: signalService,
            storageServiceManager: storageServiceManager,
            syncManager: syncManager,
            tsAccountManager: tsAccountManager,
            tsConstants: TSConstants.shared // This is safe to hard-code.
        )
    }

    private init(
        accountServiceClient: AccountServiceClient,
        databaseStorage: SDSDatabaseStorage,
        identityManager: OWSIdentityManager,
        messageProcessor: MessageProcessor,
        messageSender: MessageSender,
        networkManager: NetworkManager,
        ows2FAManager: OWS2FAManager,
        pniProtocolStore: SignalProtocolStore,
        signalService: OWSSignalServiceProtocol,
        storageServiceManager: StorageServiceManagerProtocol,
        syncManager: SyncManagerProtocol,
        tsAccountManager: TSAccountManager,
        tsConstants: TSConstantsProtocol
    ) {
        self.schedulers = DispatchQueueSchedulers()
        self.db = SDSDB(databaseStorage: databaseStorage)
        self.keyValueStoreFactory = SDSKeyValueStoreFactory()

        self.kbsCredentialStorage = KBSAuthCredentialStorageImpl(keyValueStoreFactory: keyValueStoreFactory)
        self.keyBackupService = KeyBackupServiceImpl(
            accountManager: KBS.Wrappers.TSAccountManager(tsAccountManager),
            appContext: CurrentAppContext(),
            credentialStorage: kbsCredentialStorage,
            databaseStorage: db,
            keyValueStoreFactory: keyValueStoreFactory,
            remoteAttestation: KBS.Wrappers.RemoteAttestation(),
            schedulers: schedulers,
            signalService: signalService,
            storageServiceManager: KBS.Wrappers.StorageServiceManager(storageServiceManager),
            syncManager: syncManager,
            tsConstants: tsConstants,
            twoFAManager: KBS.Wrappers.OWS2FAManager(ows2FAManager)
        )

        self.changePhoneNumberPniManager = ChangePhoneNumberPniManagerImpl(
            schedulers: schedulers,
            identityManager: ChangePhoneNumberPniManagerImpl.Wrappers.IdentityManager(identityManager),
            messageSender: ChangePhoneNumberPniManagerImpl.Wrappers.MessageSender(messageSender),
            preKeyManager: ChangePhoneNumberPniManagerImpl.Wrappers.PreKeyManager(),
            pniSignedPreKeyStore: ChangePhoneNumberPniManagerImpl.Wrappers.SignedPreKeyStore(pniProtocolStore.signedPreKeyStore),
            tsAccountManager: ChangePhoneNumberPniManagerImpl.Wrappers.TSAccountManager(tsAccountManager)
        )

        self.registrationSessionManager = RegistrationSessionManagerImpl(
            dateProvider: { Date() },
            db: db,
            keyValueStoreFactory: keyValueStoreFactory,
            schedulers: schedulers,
            signalService: signalService
        )

        self.usernameLookupManager = UsernameLookupManagerImpl()
        self.usernameEducationManager = UsernameEducationManagerImpl(keyValueStoreFactory: keyValueStoreFactory)

        self.usernameValidationManager = UsernameValidationManagerImpl(
            context: .init(
                accountManager: Usernames.Validation.Wrappers.TSAccountManager(tsAccountManager),
                accountServiceClient: Usernames.Validation.Wrappers.AccountServiceClient(accountServiceClient),
                database: db,
                keyValueStoreFactory: keyValueStoreFactory,
                messageProcessor: Usernames.Validation.Wrappers.MessageProcessor(messageProcessor),
                networkManager: networkManager,
                schedulers: schedulers,
                storageServiceManager: Usernames.Validation.Wrappers.StorageServiceManager(storageServiceManager),
                usernameLookupManager: usernameLookupManager
            )
        )
    }
}

// MARK: - Singleton setup during app setup

/// An `@objc` static wrapper for setting up ``DependenciesBridge``. Intended
/// for use during app setup.
@objc
public class DependenciesBridgeSetup: NSObject {

    /// Set up the ``DependenciesBridge`` singleton. See that class for more
    /// details as to its purpose.
    ///
    /// Important that this happen during app setup, to ensure that singletons
    /// in ``DependenciesBridge`` are available to singletons downstream in the
    /// app setup dependencies graph.
    @objc
    static func setupSingleton(
        accountServiceClient: AccountServiceClient,
        databaseStorage: SDSDatabaseStorage,
        identityManager: OWSIdentityManager,
        messageProcessor: MessageProcessor,
        messageSender: MessageSender,
        networkManager: NetworkManager,
        ows2FAManager: OWS2FAManager,
        pniProtocolStore: SignalProtocolStore,
        signalService: OWSSignalServiceProtocol,
        storageServiceManager: StorageServiceManagerProtocol,
        syncManager: SyncManagerProtocol,
        tsAccountManager: TSAccountManager
    ) {
        DependenciesBridge.setupSingleton(
            accountServiceClient: accountServiceClient,
            databaseStorage: databaseStorage,
            identityManager: identityManager,
            messageProcessor: messageProcessor,
            messageSender: messageSender,
            networkManager: networkManager,
            ows2FAManager: ows2FAManager,
            pniProtocolStore: pniProtocolStore,
            signalService: signalService,
            storageServiceManager: storageServiceManager,
            syncManager: syncManager,
            tsAccountManager: tsAccountManager
        )
    }
}
