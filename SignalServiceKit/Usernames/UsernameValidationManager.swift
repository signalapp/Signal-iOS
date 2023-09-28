//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

// MARK: - Namespace

extension Usernames {
    fileprivate enum ValidationError: Error {
        case usernameMismatch
        case usernameLinkMismatch
    }

    public enum Validation {
        public enum Shims {
            public typealias AccountServiceClient = _UsernameValidationManager_AccountServiceClientShim
            public typealias MessageProcessor = _UsernameValidationManager_MessageProcessorShim
            public typealias StorageServiceManager = _UsernameValidationManager_StorageServiceManagerShim
        }

        enum Wrappers {
            internal typealias AccountServiceClient = _UsernameValidationManager_AccountServiceClientWrapper
            internal typealias MessageProcessor = _UsernameValidationManager_MessageProcessorWrapper
            internal typealias StorageServiceManager = _UsernameValidationManager_StorageServiceManagerWrapper
        }
    }
}

public protocol UsernameValidationManager {
    func validateUsernameIfNecessary(_ transaction: DBReadTransaction)
}

public class UsernameValidationManagerImpl: UsernameValidationManager {

    private enum Constants {
        static let collectionName: String = "UsernameValidation"
        static let lastValidationDateKey: String = "lastValidationDate"
    }

    internal struct Context {
        let accountServiceClient: Usernames.Validation.Shims.AccountServiceClient
        let database: DB
        let keyValueStoreFactory: KeyValueStoreFactory
        let localUsernameManager: LocalUsernameManager
        let messageProcessor: Usernames.Validation.Shims.MessageProcessor
        let schedulers: Schedulers
        let storageServiceManager: Usernames.Validation.Shims.StorageServiceManager
        let usernameLinkManager: UsernameLinkManager
    }

    // MARK: Init

    private let keyValueStore: KeyValueStore
    private let context: Context

    init(context: Context) {
        self.context = context
        keyValueStore = context.keyValueStoreFactory.keyValueStore(collection: Constants.collectionName)
    }

    // MARK: Username Validation

    public func validateUsernameIfNecessary(_ syncTx: DBReadTransaction) {
        guard shouldValidateUsername(syncTx) else {
            return
        }

        UsernameLogger.shared.info("Validating username.")

        firstly(on: context.schedulers.sync) { () -> Promise<Void> in
            return self.ensureUsernameStateUpToDate()
        }
        .then(on: context.schedulers.global()) { () -> Promise<Void> in
            let localUsernameState = self.context.database.read { tx in
                return self.context.localUsernameManager.usernameState(tx: tx)
            }

            switch localUsernameState {
            case .unset:
                // If we validate that we have no local username we can skip
                // validating the username link as it's irrelevant.
                return firstly(on: self.context.schedulers.sync) {
                    return self.validateLocalUsernameAgainstService(
                        localUsername: nil
                    )
                }
            case let .available(username, usernameLink):
                // If we have a username and we're in a good state, try and
                // validate both the username and the link.
                return firstly(on: self.context.schedulers.sync) {
                    return self.validateLocalUsernameAgainstService(
                        localUsername: username
                    )
                }
                .then(on: self.context.schedulers.sync) { () -> Promise<Void> in
                    return self.validateLocalUsernameLinkAgainstService(
                        localUsername: username,
                        localUsernameLink: usernameLink
                    )
                }
            case let .linkCorrupted(username):
                // If we have a username but know our link is broken, no need to
                // validate the link. (What would we even validate?)
                return firstly(on: self.context.schedulers.sync) {
                    return self.validateLocalUsernameAgainstService(
                        localUsername: username
                    )
                }
            case .usernameAndLinkCorrupted:
                // If we know we're in a bad state, we can bail out.
                return .value(())
            }
        }.done(on: context.schedulers.global()) {
            // Save the time we last finished validating successfully.

            self.context.database.write { tx in
                self.setLastValidation(date: Date(), tx)
            }
        }
        .catch(on: context.schedulers.global()) { error in
            UsernameLogger.shared.error("Error validating username: \(error)")
        }
    }

    private func shouldValidateUsername(_ transaction: DBReadTransaction) -> Bool {
        guard let lastValidationDate = lastValidationDate(transaction) else {
            return true
        }

        if Date() > lastValidationDate.addingTimeInterval(kDayInterval) {
            // It's been more than a day - check again.
            return true
        }

        return false
    }

    /// Ensure that we have the latest local state regarding our username.
    ///
    /// All of a user's devices can update the username and username link.
    /// Consequently, before we do any comparison of local and remote state, we
    /// should ensure we have the latest state from any linked devices.
    ///
    /// We first finish message processing, specifically because we might find a
    /// "fetch latest" sync message telling us to restore from Storage Service.
    /// We then wait for any in-progress restores.
    ///
    /// After these steps, we can be confident that we have the latest on our
    /// username.
    private func ensureUsernameStateUpToDate() -> Promise<Void> {
        return firstly(on: context.schedulers.sync) {
            self.context.messageProcessor.fetchingAndProcessingCompletePromise()
        }
        .then(on: context.schedulers.sync) {
            self.context.storageServiceManager.waitForPendingRestores()
        }
    }

    /// Validate the local username against the value stored on the service.
    ///
    /// - Returns
    /// A promise that resolves with the local username (if any), if the local
    /// value matches the service. The promise rejects if the local username
    /// does not match the service.
    private func validateLocalUsernameAgainstService(
        localUsername: String?
    ) -> Promise<Void> {
        typealias WhoAmIResponse = WhoAmIRequestFactory.Responses.WhoAmI

        return firstly(on: context.schedulers.sync) { () -> Promise<WhoAmIResponse> in
            return self.context.accountServiceClient.getAccountWhoAmI()
        }
        .done(on: context.schedulers.global()) { whoamiResponse throws in
            let validationSucceeded: Bool = {
                UsernameLogger.shared.info("Comparing usernames: \(localUsername == nil), \(whoamiResponse.usernameHash == nil)")

                switch (localUsername, whoamiResponse.usernameHash) {
                case (nil, nil):
                    // Both missing -> good
                    return true
                case (nil, .some), (.some, nil):
                    // One missing, one set -> bad
                    return false
                case let (.some(localUsername), .some(remoteUsernameHash)):
                    // Both present -> check the values

                    guard let hashedLocalUsername = try? Usernames.HashedUsername(
                        forUsername: localUsername
                    ) else {
                        return false
                    }

                    return hashedLocalUsername.hashString == remoteUsernameHash
                }
            }()

            if validationSucceeded {
                UsernameLogger.shared.info("Username validated successfully.")
            } else {
                self.context.database.write { tx in
                    self.context.localUsernameManager.setLocalUsernameCorrupted(
                        tx: tx
                    )
                }

                throw Usernames.ValidationError.usernameMismatch
            }
        }
    }

    private func validateLocalUsernameLinkAgainstService(
        localUsername: String,
        localUsernameLink: Usernames.UsernameLink
    ) -> Promise<Void> {
        return firstly(on: context.schedulers.sync) { () -> Promise<String?> in
            self.context.usernameLinkManager.decryptEncryptedLink(
                link: localUsernameLink
            )
        }.map(on: context.schedulers.global()) { usernameForLocalLink throws in
            if
                let usernameForLocalLink,
                usernameForLocalLink == localUsername
            {
                UsernameLogger.shared.info("Username link validated successfully.")
            } else {
                if usernameForLocalLink == nil {
                    UsernameLogger.shared.warn("Username missing for local link!")
                }

                self.context.database.write { tx in
                    self.context.localUsernameManager.setLocalUsernameWithCorruptedLink(
                        username: localUsername,
                        tx: tx
                    )
                }

                throw Usernames.ValidationError.usernameLinkMismatch
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

    internal func setLastValidation(date: Date, _ transaction: DBWriteTransaction) {
        self.keyValueStore.setDate(
            date,
            key: Constants.lastValidationDateKey,
            transaction: transaction
        )
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

internal class _UsernameValidationManager_MessageProcessorWrapper: Usernames.Validation.Shims.MessageProcessor {
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
    func waitForPendingRestores() -> Promise<Void>
}

internal class _UsernameValidationManager_StorageServiceManagerWrapper: Usernames.Validation.Shims.StorageServiceManager {
    private let storageServiceManager: StorageServiceManager
    public init(_ storageServiceManager: StorageServiceManager) {
        self.storageServiceManager = storageServiceManager
    }

    public func waitForPendingRestores() -> Promise<Void> {
        storageServiceManager.waitForPendingRestores().asVoid()
    }
}
