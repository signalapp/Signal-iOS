//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

extension Usernames {
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
    func validateUsername() async throws -> Bool
}

// MARK: -

public class UsernameValidationManagerImpl: UsernameValidationManager {
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
    private let taskQueue = ConcurrentTaskQueue(concurrentLimit: 1)

    private var logger: UsernameLogger { .shared }

    init(context: Context) {
        self.context = context
    }

    // MARK: Username Validation

    public func validateUsername() async throws -> Bool {
        do {
            return try await taskQueue.run {
                return try await self._validateUsername()
            }
        } catch {
            logger.error("Error validating username and/or link: \(error)")
            throw error
        }
    }

    private func _validateUsername() async throws -> Bool {
        logger.info("Validating username.")

        try await ensureUsernameStateUpToDate()

        let localUsernameState = self.context.database.read { tx in
            return self.context.localUsernameManager.usernameState(tx: tx)
        }

        switch localUsernameState {
        case .unset:
            // If we validate that we have no local username we can skip
            // validating the username link as it's irrelevant.
            return try await validateLocalUsernameAgainstService(localUsername: nil)
        case let .available(username, usernameLink):
            // If we have a username and we're in a good state, try and
            // validate both the username and the link.
            guard try await validateLocalUsernameAgainstService(localUsername: username) else {
                return false
            }
            return try await validateLocalUsernameLinkAgainstService(
                localUsername: username,
                localUsernameLink: usernameLink
            )
        case let .linkCorrupted(username):
            // If we have a username but know our link is broken, no need to
            // validate the link. (What would we even validate?)
            return try await validateLocalUsernameAgainstService(localUsername: username)
        case .usernameAndLinkCorrupted:
            // If we know we're in a bad state, we can skip validation.
            return false
        }
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
        try await self.context.messageProcessor.waitForFetchingAndProcessing()
        try await self.context.storageServiceManager.waitForPendingRestores()
    }

    /// Validate the local username against the value stored on the service.
    ///
    /// - Returns
    /// A promise that resolves with the local username (if any), if the local
    /// value matches the service. The promise rejects if the local username
    /// does not match the service.
    private func validateLocalUsernameAgainstService(
        localUsername: String?
    ) async throws -> Bool {
        let whoAmIResponse = try await self.context.whoAmIManager.makeWhoAmIRequest()

        let validationSucceeded: Bool = {
            self.logger.info("Comparing usernames; local: \(localUsername != nil), remote: \(whoAmIResponse.usernameHash != nil)")

            switch (localUsername, whoAmIResponse.usernameHash) {
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
        }
        return validationSucceeded
    }

    private func validateLocalUsernameLinkAgainstService(
        localUsername: String,
        localUsernameLink: Usernames.UsernameLink
    ) async throws -> Bool {
        let validationSucceeded: Bool
        do {
            let usernameForLocalLink = try await self.context.usernameLinkManager.decryptEncryptedLink(
                link: localUsernameLink
            )
            if usernameForLocalLink == nil {
                self.logger.warn("Couldn't find our own username link")
            }
            validationSucceeded = (usernameForLocalLink == localUsername)
        } catch
            LibSignalClient.SignalError.usernameLinkInvalidEntropyDataLength,
            LibSignalClient.SignalError.usernameLinkInvalid
        {
            self.logger.warn("Couldn't parse our own username link")
            validationSucceeded = false
        }

        if validationSucceeded {
            self.logger.info("Successfully validated our own username link")
        } else {
            self.logger.warn("Couldn't validate our own username link; marking invalid")
            await self.context.database.awaitableWrite { tx in
                self.context.localUsernameManager.setLocalUsernameWithCorruptedLink(
                    username: localUsername,
                    tx: tx
                )
            }
        }
        return validationSucceeded
    }
}

// MARK: - Protocolized Wrappers

// MARK: MessageProcessor

public protocol _UsernameValidationManager_MessageProcessorShim {
    func waitForFetchingAndProcessing() async throws(CancellationError)
}

internal class _UsernameValidationManager_MessageProcessorWrapper: Usernames.Validation.Shims.MessageProcessor {
    private let messageProcessor: MessageProcessor
    public init(_ messageProcessor: MessageProcessor) {
        self.messageProcessor = messageProcessor
    }

    public func waitForFetchingAndProcessing() async throws(CancellationError) {
        try await messageProcessor.waitForFetchingAndProcessing()
    }
}

// MARK: StorageServiceManager

public protocol _UsernameValidationManager_StorageServiceManagerShim {
    func waitForPendingRestores() async throws
}

internal class _UsernameValidationManager_StorageServiceManagerWrapper: Usernames.Validation.Shims.StorageServiceManager {
    private let storageServiceManager: StorageServiceManager
    public init(_ storageServiceManager: StorageServiceManager) {
        self.storageServiceManager = storageServiceManager
    }

    public func waitForPendingRestores() async throws {
        try await storageServiceManager.waitForPendingRestores()
    }
}
