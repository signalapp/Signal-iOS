//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - Namespace

extension Usernames {
    fileprivate enum ValidationError: Error {
        case missingLocalUsername
        case invalidLocalUsername
        case missingRemoteUsernameHash
        case mismatchedUsernameHashes
    }

    public enum Validation {
        static public let usernameValidationDidChange = Notification.Name("usernameValidationDidChange")

        public enum Shims {
            public typealias AccountServiceClient = _UsernameValidationManager_AccountServiceClientShim
            public typealias MessageProcessor = _UsernameValidationManager_MessageProcessorShim
            public typealias StorageServiceManager = _UsernameValidationManager_StorageServiceManagerShim
            public typealias TSAccountManager = _UsernameValidationManager_TSAccountManagerShim
        }

        internal enum Wrappers {
            internal typealias AccountServiceClient = _UsernameValidationManager_AccountServiceClientWrapper
            internal typealias MessageProcessor = _UsernameValidationManager_MessageProcessorWrapper
            internal typealias StorageServiceManager = _UsernameValidationManager_StorageServiceManagerWrapper
            internal typealias TSAccountManager = _UsernameValidationManager_TSAccountManagerWrapper
        }
    }
}

public protocol UsernameValidationManager {
    func validateUsernameIfNecessary(_ transaction: DBReadTransaction)
    func hasUsernameFailedValidation(_ transaction: DBReadTransaction) -> Bool
    func clearUsernameHasFailedValidation(_ transaction: DBWriteTransaction)
}

public class UsernameValidationManagerImpl: UsernameValidationManager {

    private enum Constants {
        static let collectionName: String = "UsernameValidation"
        static let lastValidationDateKey: String = "lastValidationDate"
        static let usernameFailedValidationKey: String = "usernameFailedValidation"
    }

    internal struct Context {
        let accountManager: Usernames.Validation.Shims.TSAccountManager
        let accountServiceClient: Usernames.Validation.Shims.AccountServiceClient
        let database: DB
        let keyValueStoreFactory: KeyValueStoreFactory
        let messageProcessor: Usernames.Validation.Shims.MessageProcessor
        let networkManager: NetworkManager
        let schedulers: Schedulers
        let storageServiceManager: Usernames.Validation.Shims.StorageServiceManager
        let usernameLookupManager: UsernameLookupManager
    }

    // MARK: Init

    private let keyValueStore: KeyValueStoreProtocol
    private let context: Context

    init(context: Context) {
        self.context = context
        keyValueStore = context.keyValueStoreFactory.keyValueStore(collection: Constants.collectionName)
    }

    // MARK: Username Validation

    public func validateUsernameIfNecessary(_ transaction: DBReadTransaction) {
        guard let localAci = context.accountManager.localUUID else {
            return
        }
        guard shouldValidateUsername(transaction) else {
            return
        }

        let localUsername = context.usernameLookupManager.fetchUsername(
            forAci: localAci,
            transaction: transaction
        )

        Logger.info("Validating username")

        // There is a small chance of a race condition between primary and
        // linked devices if the system is busy at startup.
        //
        // One way this could happen is if a linked device
        // comes online for the first time in a while and is processing a
        // backlog of messages and hasn't fully updated to the most recent
        // username. If the validation fires on the linked device before
        // the backlog is processed (and the username change is realized),
        // it could result in the linked device thinking the usernames are
        // out of sync and trigger the deletion of the username.
        //
        // To help avoid this scenario the validation logic attempts to
        // wait for any in-flight message processing & storage service
        // tasks to finish before starting the validation.
        firstly(on: context.schedulers.global()) {
            self.context.messageProcessor.fetchingAndProcessingCompletePromise()
        }
        .then(on: context.schedulers.global()) {
            self.context.storageServiceManager.waitForPendingRestores()
        }
        .then(on: context.schedulers.global()) {
            self.context.accountServiceClient.getAccountWhoAmI()
        }
        .then(on: context.schedulers.global()) { whoamiResponse in
            let result = self.validate(
                localUsername: localUsername,
                remoteUsernameHash: whoamiResponse.usernameHash
            )

            switch result {
            case .success:
                Logger.info("Successfully validated username")
                self.context.database.write { transaction in
                    self.setLastValidation(date: Date(), transaction)
                    // Shouldn't be a failure set at this point, but clear
                    // just to be sure.
                    self.setUsernameHasFailedValidation(false, transaction: transaction)
                }
                return Promise.value(())
            case .failure(let error):
                Logger.warn("Username failed validation: \(error)")
                return self.handleInvalidUsername(for: localAci)
            }
        }
        .catch(on: context.schedulers.global()) { error in
            Logger.error("Error validating username: \(error)")
        }
    }

    private func shouldValidateUsername(_ transaction: DBReadTransaction) -> Bool {
        guard let lastValidationDate = lastValidationDate(transaction) else {
            return true
        }

        // check if it's been 12 hours since last validation
        let checkInterval = 12 * kHourInterval
        let currentDate = Date()
        let checkDate =  Date.init(
            timeInterval: checkInterval,
            since: lastValidationDate)
        if currentDate < checkDate {
            Logger.debug("Skipping; date: \(String(describing: currentDate)) < \(String(describing: checkDate)).")
            return false
        }

        return true
    }

    private func validate(
        localUsername: String?,
        remoteUsernameHash: String?
    ) -> Result<Void, Error> {
        guard let localUsername else {
            if remoteUsernameHash != nil {
                // Found a remote hash, expected a local and didn't get one
                return .failure(Usernames.ValidationError.missingLocalUsername)
            } else {
                // Both missing, ok to return
                return .success(())
            }
        }

        // In normal usage, this shouldn't fail since the username would
        // have been validated during initial setup.  But if the username
        // somehow fails to convert into a valid hashed username, treat it
        // as if it were a missing user name and go through the cleanup steps.
        guard
            let localUserHash = try? Usernames.HashedUsername(forUsername: localUsername)
        else {
            return .failure(Usernames.ValidationError.invalidLocalUsername)
        }

        // Found a local username hash, check that the remote username hash exists
        guard let remoteUserHash = remoteUsernameHash else {
            return .failure(Usernames.ValidationError.missingRemoteUsernameHash)
        }

        // Found both local and remote, check that they match.
        if localUserHash.hashString != remoteUserHash {
            return .failure(Usernames.ValidationError.mismatchedUsernameHashes)
        }

        return .success(())
    }

    /// Clean up the invalid username, both locally and on the server.
    ///     1. remove the associated username hash (remote)
    ///     2. remove the username on the account record (local) & save
    ///     3. post a notification that something has changed
    ///     4. make a note that the user is in a bad state.
    private func handleInvalidUsername(for aci: UUID) -> Promise<Void> {
        return firstly(on: context.schedulers.global()) {
            // Delete remotely
            Usernames
                .API(
                    networkManager: self.context.networkManager,
                    schedulers: self.context.schedulers
                )
                .attemptToDeleteCurrentUsername()
        }
        .done(on: context.schedulers.global()) {
            self.context.database.write { transaction in
                // Delete locally
                self.context.usernameLookupManager.saveUsername(
                    nil,
                    forAci: aci,
                    transaction: transaction
                )

                // Push local changes to storage service
                self.context.storageServiceManager.recordPendingLocalAccountUpdates()

                // Mark the username failed validation to signal to the UI
                // to notify the user.
                self.setUsernameHasFailedValidation(true, transaction: transaction)
                self.setLastValidation(date: nil, transaction)
            }
        }
    }

    // MARK: Internal validation state

    internal func lastValidationDate(_ transaction: DBReadTransaction) -> Date? {
        keyValueStore.getDate(
            Constants.lastValidationDateKey,
            transaction: transaction
        )
    }

    internal func setLastValidation(date: Date?, _ transaction: DBWriteTransaction) {
        if let date = date {
            self.keyValueStore.setDate(
                date,
                key: Constants.lastValidationDateKey,
                transaction: transaction
            )
        } else {
            self.keyValueStore.removeValue(
                forKey: Constants.lastValidationDateKey,
                transaction: transaction
            )
        }
    }

    private func setUsernameHasFailedValidation(_ didFail: Bool, transaction: DBWriteTransaction) {
        guard didFail != hasUsernameFailedValidation(transaction) else { return }

        self.keyValueStore.setBool(
            didFail,
            key: Constants.usernameFailedValidationKey,
            transaction: transaction
        )

        // Notify on any change of the username validation
        // to allow any UI to update in response
        NotificationCenter.default.postNotificationNameAsync(
            Usernames.Validation.usernameValidationDidChange,
            object: nil
        )
    }

    // MARK: UsernameValidationManager methods

    public func hasUsernameFailedValidation(_ transaction: DBReadTransaction) -> Bool {
        return self.keyValueStore.getBool(
            Constants.usernameFailedValidationKey,
            transaction: transaction
        ) ?? false
    }

    public func clearUsernameHasFailedValidation(_ transaction: DBWriteTransaction) {
        setUsernameHasFailedValidation(false, transaction: transaction)
    }
}

// MARK: - Protocolized Wrappers

// MARK: AccountServiceClient

public protocol _UsernameValidationManager_AccountServiceClientShim {
    func getAccountWhoAmI() -> Promise<WhoAmIRequestFactory.Responses.WhoAmI>
}

internal class _UsernameValidationManager_AccountServiceClientWrapper: Usernames.Validation.Shims.AccountServiceClient {
    private let accountServiceClient: AccountServiceClient
    public init(_ accountServiceClient: AccountServiceClient) {
        self.accountServiceClient = accountServiceClient
    }

    public func getAccountWhoAmI() -> Promise<WhoAmIRequestFactory.Responses.WhoAmI> {
        accountServiceClient.getAccountWhoAmI()
    }
}

// MARK: MessageProcessor

public protocol _UsernameValidationManager_MessageProcessorShim {
    func fetchingAndProcessingCompletePromise() -> Promise<Void>
}

internal class _UsernameValidationManager_MessageProcessorWrapper:
    Usernames.Validation.Shims.MessageProcessor {
    private let messageProcessor: MessageProcessor
    public init(_ messageProcessor: MessageProcessor) {
        self.messageProcessor = messageProcessor
    }

    public func fetchingAndProcessingCompletePromise() -> Promise<Void> {
        messageProcessor.fetchingAndProcessingCompletePromise()
    }
}

// MARK: StorageServiceManager

public protocol _UsernameValidationManager_StorageServiceManagerShim {
    func recordPendingLocalAccountUpdates()
    func waitForPendingRestores() -> Promise<Void>
}

internal class _UsernameValidationManager_StorageServiceManagerWrapper:
    Usernames.Validation.Shims.StorageServiceManager {
    private let storageServiceManager: StorageServiceManagerProtocol
    public init(_ storageServiceManager: StorageServiceManagerProtocol) {
        self.storageServiceManager = storageServiceManager
    }

    public func recordPendingLocalAccountUpdates() {
        storageServiceManager.recordPendingLocalAccountUpdates()
    }

    public func waitForPendingRestores() -> Promise<Void> {
        storageServiceManager.waitForPendingRestores().asVoid()
    }
}

// MARK: TSAccountManager

public protocol _UsernameValidationManager_TSAccountManagerShim {
    var localUUID: UUID? { get }
}

internal class _UsernameValidationManager_TSAccountManagerWrapper: Usernames.Validation.Shims.TSAccountManager {
    private let accountManager: TSAccountManager
    public init(_ accountManager: TSAccountManager) { self.accountManager = accountManager }

    public var localUUID: UUID? {
        return accountManager.localAddress?.uuid
    }
}
