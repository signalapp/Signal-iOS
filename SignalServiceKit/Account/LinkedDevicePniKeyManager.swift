//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol LinkedDevicePniKeyManager {
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
}

class LinkedDevicePniKeyManagerImpl: LinkedDevicePniKeyManager {
    private enum Constants {
        static let collection = "LinkedDevicePniKeyManagerImpl"
        static let hasRecordedSuspectedIssueKey = "hasSuspectedIssue"
    }

    private let logger = PrefixedLogger(prefix: "LDPKM")

    private let db: any DB
    private let kvStore: KeyValueStore
    private let messageProcessor: Shims.MessageProcessor
    private let pniIdentityKeyChecker: PniIdentityKeyChecker
    private let registrationStateChangeManager: RegistrationStateChangeManager
    private let tsAccountManager: TSAccountManager

    private let isValidating = AtomicBool(false, lock: .init())

    init(
        db: any DB,
        messageProcessor: Shims.MessageProcessor,
        pniIdentityKeyChecker: PniIdentityKeyChecker,
        registrationStateChangeManager: RegistrationStateChangeManager,
        tsAccountManager: TSAccountManager
    ) {
        self.db = db
        self.kvStore = KeyValueStore(collection: Constants.collection)
        self.messageProcessor = messageProcessor
        self.pniIdentityKeyChecker = pniIdentityKeyChecker
        self.registrationStateChangeManager = registrationStateChangeManager
        self.tsAccountManager = tsAccountManager
    }

    func recordSuspectedIssueWithPniIdentityKey(tx: DBWriteTransaction) {
        guard tsAccountManager.registrationState(tx: tx).isPrimaryDevice == false else {
            return
        }

        kvStore.setBool(
            true,
            key: Constants.hasRecordedSuspectedIssueKey,
            transaction: tx
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

        await self.messageProcessor.waitForFetchingAndProcessing()

        let hasSuspectedIssue = self.db.read { tx in
            return self.kvStore.getBool(
                Constants.hasRecordedSuspectedIssueKey,
                defaultValue: false,
                transaction: tx
            )
        }
        guard hasSuspectedIssue else {
            return
        }

        do {
            let isValid = try await _validateLocalPniIdentityKey()
            await self.db.awaitableWrite { tx in
                if !isValid {
                    logger.warn("Marking as deregistered.")
                    self.registrationStateChangeManager.setIsDeregisteredOrDelinked(true, tx: tx)
                }
                self.clearPniMessageDecryptionError(tx: tx)
            }
        } catch {
            logger.warn("Couldn't check PNI identity key: \(error)")
        }
    }

    private func _validateLocalPniIdentityKey() async throws -> Bool {
        let logger = logger

        let localPni = self.db.read { tx in
            return self.tsAccountManager.localIdentifiers(tx: tx)?.pni
        }
        guard let localPni else {
            logger.warn("Missing local PNI.")
            return false
        }

        let matched = try await self.pniIdentityKeyChecker.serverHasSameKeyAsLocal(localPni: localPni)
        guard matched else {
            logger.warn("Local PNI identity key didn't match remote!")
            return false
        }

        return true
    }

    private func clearPniMessageDecryptionError(tx: DBWriteTransaction) {
        kvStore.removeValue(
            forKey: Constants.hasRecordedSuspectedIssueKey,
            transaction: tx
        )
    }
}

// MARK: - Mocks

extension LinkedDevicePniKeyManagerImpl {
    enum Shims {
        typealias MessageProcessor = _LinkedDevicePniKeyManagerImpl_MessageProcessor_Shim
    }

    enum Wrappers {
        typealias MessageProcessor = _LinkedDevicePniKeyManagerImpl_MessageProcessor_Wrapper
    }
}

// MARK: MessageProcessor

protocol _LinkedDevicePniKeyManagerImpl_MessageProcessor_Shim {
    func waitForFetchingAndProcessing() async
}

class _LinkedDevicePniKeyManagerImpl_MessageProcessor_Wrapper: _LinkedDevicePniKeyManagerImpl_MessageProcessor_Shim {
    private let messageProcessor: MessageProcessor

    public init(_ messageProcessor: MessageProcessor) {
        self.messageProcessor = messageProcessor
    }

    public func waitForFetchingAndProcessing() async {
        await messageProcessor.waitForFetchingAndProcessing().awaitable()
    }
}
