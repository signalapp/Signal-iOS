//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol IdentityKeyMismatchManager {
    /// Records that we encountered an issue we suspect is due to a problem with
    /// our PNI identity key.
    func recordSuspectedIssueWithPniIdentityKey(tx: DBWriteTransaction)

    /// Validates this device's PNI identity key against the one on the server,
    /// if necessary.
    ///
    /// It is possible for some linked devices to have missing or outdated PNI
    /// identity keys. To address this we will run "PNI Hello World", an
    /// operation in which the primary sends a message to linked devices with
    /// the correct PNI identity key.
    ///
    /// We cannot, unfortunately, guarantee that a linked device in this state
    /// will successfully receive the PNI Hello World. For example, its primary
    /// may never come online to fire it, or the associated message may age out
    /// of the queue. While these are edge cases, they will result in a linked
    /// device that cannot perform actions related to our PNI identity key, such
    /// as decrypting messages to our PNI or prekey API calls.
    ///
    /// Newly-linked devices will receive the PNI identity key as part of
    /// provisioning. Consequently, if we find ourselves with a missing or
    /// incorrect PNI identity key we will correct that state by unlinking the
    /// linked device. On re-link, it'll get the correct state.
    ///
    /// This operation checks for suspected issues with our PNI identity key and
    /// subsequently compares our local PNI identity key with the service. If
    /// our local key does not match we unlink this device.
    ///
    /// We do not expect many devices to have ended up in a bad state, and so we
    /// hope that this unlinking will be a rare last resort.
    func validateLocalPniIdentityKeyIfNecessary() async

    func validateIdentityKey(for identity: OWSIdentity) async
}

class IdentityKeyMismatchManagerImpl: IdentityKeyMismatchManager {
    private enum Constants {
        static let collection = "LinkedDevicePniKeyManagerImpl"
        static let hasRecordedSuspectedIssueKey = "hasSuspectedIssue"
    }

    private let logger = PrefixedLogger(prefix: "LDPKM")

    private let db: any DB
    private let identityKeyChecker: IdentityKeyChecker
    private let kvStore: KeyValueStore
    private let messageProcessor: Shims.MessageProcessor
    private let registrationStateChangeManager: RegistrationStateChangeManager
    private let tsAccountManager: TSAccountManager
    private let whoAmIManager: any WhoAmIManager

    private let isValidating = AtomicBool(false, lock: .init())

    init(
        db: any DB,
        identityKeyChecker: IdentityKeyChecker,
        messageProcessor: Shims.MessageProcessor,
        registrationStateChangeManager: RegistrationStateChangeManager,
        tsAccountManager: TSAccountManager,
        whoAmIManager: any WhoAmIManager,
    ) {
        self.db = db
        self.identityKeyChecker = identityKeyChecker
        self.kvStore = KeyValueStore(collection: Constants.collection)
        self.messageProcessor = messageProcessor
        self.registrationStateChangeManager = registrationStateChangeManager
        self.tsAccountManager = tsAccountManager
        self.whoAmIManager = whoAmIManager
    }

    func recordSuspectedIssueWithPniIdentityKey(tx: DBWriteTransaction) {
        guard tsAccountManager.registrationState(tx: tx).isPrimaryDevice == false else {
            return
        }

        kvStore.setBool(
            true,
            key: Constants.hasRecordedSuspectedIssueKey,
            transaction: tx,
        )
    }

    func validateLocalPniIdentityKeyIfNecessary() async {
        let logger = logger

        guard isValidating.tryToSetFlag() else {
            logger.warn("Skipping validation - already in flight!")
            return
        }
        defer {
            self.isValidating.set(false)
        }

        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == false else {
            return
        }

        do throws(CancellationError) {
            try await self.messageProcessor.waitForFetchingAndProcessing()
        } catch {
            return
        }

        let hasSuspectedIssue = self.db.read { tx in
            return self.kvStore.getBool(
                Constants.hasRecordedSuspectedIssueKey,
                defaultValue: false,
                transaction: tx,
            )
        }
        guard hasSuspectedIssue else {
            return
        }

        await validateIdentityKey(for: .pni)
    }

    func validateIdentityKey(for identity: OWSIdentity) async {
        let logger = logger
        logger.info("Validating identity key for \(identity)")
        do {
            let isValid = try await _validateIdentityKey(for: identity)
            await self.db.awaitableWrite { tx in
                if !isValid {
                    logger.warn("Marking as deregistered.")
                    self.registrationStateChangeManager.setIsDeregisteredOrDelinked(true, tx: tx)
                }
                if identity == .pni {
                    self.clearPniMessageDecryptionError(tx: tx)
                }
            }
        } catch {
            // Eat all the errors -- the caller should be triggering this in response
            // to its own error, and we always want to pass that error to the caller.
            logger.warn("Couldn't validate identity key: \(error)")
        }
    }

    private func _validateIdentityKey(for identity: OWSIdentity) async throws -> Bool {
        let logger = logger

        let localIdentifier: ServiceId
        do {
            let loadLocalIdentifiers = { [db, tsAccountManager] () throws -> LocalIdentifiers in
                return try db.read { tx in
                    return try tsAccountManager.registeredState(tx: tx).localIdentifiers
                }
            }

            switch identity {
            case .aci:
                // Our ACI can't change, so we don't need to check it.
                localIdentifier = try loadLocalIdentifiers().aci
            case .pni:
                // Our PNI might change, and if it does, we might get errors when trying to
                // fetch the identity key for the old one. Check for that here.
                let remotePni = try await whoAmIManager.makeWhoAmIRequest().pni
                guard try loadLocalIdentifiers().pni == remotePni else {
                    logger.warn("The PNI identity key isn't valid because the PNI isn't valid.")
                    return false
                }
                localIdentifier = remotePni
            }
        }

        return try await self.identityKeyChecker.serverHasSameKeyAsLocal(for: identity, localIdentifier: localIdentifier)
    }

    private func clearPniMessageDecryptionError(tx: DBWriteTransaction) {
        kvStore.removeValue(
            forKey: Constants.hasRecordedSuspectedIssueKey,
            transaction: tx,
        )
    }
}

// MARK: - Mocks

extension IdentityKeyMismatchManagerImpl {
    enum Shims {
        typealias MessageProcessor = _IdentityKeyMismatchManagerImpl_MessageProcessor_Shim
    }

    enum Wrappers {
        typealias MessageProcessor = _IdentityKeyMismatchManagerImpl_MessageProcessor_Wrapper
    }
}

// MARK: MessageProcessor

protocol _IdentityKeyMismatchManagerImpl_MessageProcessor_Shim {
    func waitForFetchingAndProcessing() async throws(CancellationError)
}

class _IdentityKeyMismatchManagerImpl_MessageProcessor_Wrapper: _IdentityKeyMismatchManagerImpl_MessageProcessor_Shim {
    private let messageProcessor: MessageProcessor

    init(_ messageProcessor: MessageProcessor) {
        self.messageProcessor = messageProcessor
    }

    func waitForFetchingAndProcessing() async throws(CancellationError) {
        try await messageProcessor.waitForFetchingAndProcessing()
    }
}
