//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

extension Usernames {
    fileprivate enum ValidationError: Error {
        case usernameMismatch
        case usernameLinkMismatch
    }

    public enum Validation {
        public enum Shims {
            public typealias MessageProcessor = _UsernameValidationManager_MessageProcessorShim
            public typealias StorageServiceManager = _UsernameValidationManager_StorageServiceManagerShim
        }

        enum Wrappers {
            internal typealias MessageProcessor = _UsernameValidationManager_MessageProcessorWrapper
            internal typealias StorageServiceManager = _UsernameValidationManager_StorageServiceManagerWrapper
        }
    }
}

public protocol UsernameValidationManager {
    func validateUsernameIfNecessary() async
}

// MARK: -

public class UsernameValidationManagerImpl: UsernameValidationManager {

    private enum Constants {
        static let collectionName: String = "UsernameValidation"
        static let lastValidationDateKey: String = "lastValidationDate"
    }

    struct Context {
        let database: any DB
        let localUsernameManager: LocalUsernameManager
        let messageProcessor: Usernames.Validation.Shims.MessageProcessor
        let storageServiceManager: Usernames.Validation.Shims.StorageServiceManager
        let usernameLinkManager: UsernameLinkManager
        let whoAmIManager: WhoAmIManager
    }

    // MARK: Init

    private let context: Context
    private let keyValueStore: KeyValueStore
    private let taskQueue: SerialTaskQueue

    private var logger: UsernameLogger { .shared }

    init(context: Context) {
        self.context = context
        self.keyValueStore = KeyValueStore(collection: Constants.collectionName)
        self.taskQueue = SerialTaskQueue()
    }

    // MARK: Username Validation

    public func validateUsernameIfNecessary() async {
        do {
            try await taskQueue.enqueue {
                try await self._validateUsernameIfNecessary()
            }.value
        } catch {
            logger.error("Error validating username and/or link: \(error)")
        }
    }

    private func _validateUsernameIfNecessary() async throws {
        guard context.database.read(block: { shouldValidateUsername($0) }) else {
            return
        }

        logger.info("Validating username.")

        try await ensureUsernameStateUpToDate()

        let localUsernameState = self.context.database.read { tx in
            return self.context.localUsernameManager.usernameState(tx: tx)
        }

        switch localUsernameState {
        case .unset:
            // If we validate that we have no local username we can skip
            // validating the username link as it's irrelevant.
            try await validateLocalUsernameAgainstService(localUsername: nil)
        case let .available(username, usernameLink):
            // If we have a username and we're in a good state, try and
            // validate both the username and the link.
            try await validateLocalUsernameAgainstService(localUsername: username)

            try await validateLocalUsernameLinkAgainstService(
                localUsername: username,
                localUsernameLink: usernameLink
            )
        case let .linkCorrupted(username):
            // If we have a username but know our link is broken, no need to
            // validate the link. (What would we even validate?)
            try await validateLocalUsernameAgainstService(localUsername: username)
        case .usernameAndLinkCorrupted:
            // If we know we're in a bad state, we can skip validation.
            break
        }

        // Save the time we last finished validating successfully.
        await self.context.database.awaitableWrite { tx in
            self.setLastValidation(date: Date(), tx)
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
    private func ensureUsernameStateUpToDate() async throws {
        await self.context.messageProcessor.waitForFetchingAndProcessing().awaitable()
        try await self.context.storageServiceManager.waitForPendingRestores().awaitable()
    }

    /// Validate the local username against the value stored on the service.
    ///
    /// - Returns
    /// A promise that resolves with the local username (if any), if the local
    /// value matches the service. The promise rejects if the local username
    /// does not match the service.
    private func validateLocalUsernameAgainstService(
        localUsername: String?
    ) async throws {
        let whoamiResponse = try await self.context.whoAmIManager.makeWhoAmIRequest()

        let validationSucceeded: Bool = {
            self.logger.info("Comparing usernames; local: \(localUsername != nil), remote: \(whoamiResponse.usernameHash != nil)")

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
            self.logger.info("Username validated successfully.")
        } else {
            self.logger.warn("Username validation failed: marking local username as corrupted!")

            await self.context.database.awaitableWrite { tx in
                self.context.localUsernameManager.setLocalUsernameCorrupted(
                    tx: tx
                )
            }

            throw Usernames.ValidationError.usernameMismatch
        }
    }

    private func validateLocalUsernameLinkAgainstService(
        localUsername: String,
        localUsernameLink: Usernames.UsernameLink
    ) async throws {
        let usernameForLocalLink: String?
        do {
            usernameForLocalLink = try await self.context.usernameLinkManager.decryptEncryptedLink(
                link: localUsernameLink
            ).awaitable()
        } catch {
            switch error {
            case LibSignalClient.SignalError.usernameLinkInvalidEntropyDataLength:
                fallthrough
            case LibSignalClient.SignalError.usernameLinkInvalid:
                self.logger.warn("Local username link invalid: marking local username link corrupted!")

                await self.context.database.awaitableWrite { tx in
                    self.context.localUsernameManager.setLocalUsernameWithCorruptedLink(
                        username: localUsername,
                        tx: tx
                    )
                }
            default:
                break
            }

            throw error
        }

        if
            let usernameForLocalLink,
            usernameForLocalLink == localUsername
        {
            self.logger.info("Username link validated successfully.")
        } else {
            if usernameForLocalLink == nil {
                self.logger.warn("Username missing for local link!")
            }

            self.logger.warn("Username link validation failed: marking local username link corrupted!")

            await self.context.database.awaitableWrite { tx in
                self.context.localUsernameManager.setLocalUsernameWithCorruptedLink(
                    username: localUsername,
                    tx: tx
                )
            }

            throw Usernames.ValidationError.usernameLinkMismatch
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

// MARK: MessageProcessor

public protocol _UsernameValidationManager_MessageProcessorShim {
    func waitForFetchingAndProcessing() -> Guarantee<Void>
}

internal class _UsernameValidationManager_MessageProcessorWrapper: Usernames.Validation.Shims.MessageProcessor {
    private let messageProcessor: MessageProcessor
    public init(_ messageProcessor: MessageProcessor) {
        self.messageProcessor = messageProcessor
    }

    public func waitForFetchingAndProcessing() -> Guarantee<Void> {
        messageProcessor.waitForFetchingAndProcessing()
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
        storageServiceManager.waitForPendingRestores()
    }
}
