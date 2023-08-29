//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

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
    func validateLocalPniIdentityKeyIfNecessary(tx: DBReadTransaction)
}

class LinkedDevicePniKeyManagerImpl: LinkedDevicePniKeyManager {
    private enum Constants {
        static let collection = "LinkedDevicePniKeyManagerImpl"
        static let hasRecordedSuspectedIssueKey = "hasSuspectedIssue"
    }

    /// Scenarios that should interrupt regular processing.
    private enum Interrupts: Error {
        case noPniDecryptionError
        case missingLocalPni
        case localPniIdentityKeyDidntMatchRemote

        /// Whether this interrupt should result in unlinking.
        var shouldResultInUnlink: Bool {
            switch self {
            case .noPniDecryptionError:
                return false
            case .missingLocalPni, .localPniIdentityKeyDidntMatchRemote:
                return true
            }
        }
    }

    private let logger = PrefixedLogger(prefix: "LDPKM")

    private let db: DB
    private let kvStore: KeyValueStore
    private let messageProcessor: Shims.MessageProcessor
    private let pniIdentityKeyChecker: PniIdentityKeyChecker
    private let schedulers: Schedulers
    private let tsAccountManager: Shims.TSAccountManager

    private let isValidating = AtomicBool(false, lock: .init())

    init(
        db: DB,
        keyValueStoreFactory: KeyValueStoreFactory,
        messageProcessor: Shims.MessageProcessor,
        pniIdentityKeyChecker: PniIdentityKeyChecker,
        schedulers: Schedulers,
        tsAccountManager: Shims.TSAccountManager
    ) {
        self.db = db
        self.kvStore = keyValueStoreFactory.keyValueStore(collection: Constants.collection)
        self.messageProcessor = messageProcessor
        self.pniIdentityKeyChecker = pniIdentityKeyChecker
        self.schedulers = schedulers
        self.tsAccountManager = tsAccountManager
    }

    func recordSuspectedIssueWithPniIdentityKey(tx: DBWriteTransaction) {
        guard !tsAccountManager.isPrimaryDevice(tx: tx) else {
            logger.warn("Not recording suspected PNI identity key issue - not a linked device!")
            return
        }

        kvStore.setBool(
            true,
            key: Constants.hasRecordedSuspectedIssueKey,
            transaction: tx
        )

        validateLocalPniIdentityKeyIfNecessary(tx: tx)
    }

    func validateLocalPniIdentityKeyIfNecessary(tx syncTx: DBReadTransaction) {
        let logger = logger

        guard isValidating.tryToSetFlag() else {
            logger.warn("Skipping validation - already in flight!")
            return
        }

        guard !tsAccountManager.isPrimaryDevice(tx: syncTx) else {
            logger.info("Skipping validation - not a linked device!")
            return
        }

        firstly(on: schedulers.sync) { () -> Promise<Void> in
            return self.messageProcessor.fetchingAndProcessingCompletePromise()
        }
        .then(on: schedulers.global()) { () throws -> Promise<Bool> in
            return try self.db.read { tx throws in
                guard self.kvStore.getBool(
                    Constants.hasRecordedSuspectedIssueKey,
                    defaultValue: false,
                    transaction: tx
                ) else {
                    logger.info("Skipping validation - no reason to suspect an issue.")
                    throw Interrupts.noPniDecryptionError
                }

                guard let localPni = self.tsAccountManager.localIdentifiers(
                    tx: tx
                )?.pni else {
                    logger.warn("Missing local PNI!")
                    throw Interrupts.missingLocalPni
                }

                return self.pniIdentityKeyChecker.serverHasSameKeyAsLocal(
                    localPni: localPni,
                    tx: tx
                )
            }
        }
        .done(on: schedulers.global()) { matched throws in
            guard matched else {
                logger.warn("Local PNI identity key didn't match remote!")
                throw Interrupts.localPniIdentityKeyDidntMatchRemote
            }

            self.db.write { tx in
                self.clearPniMessageDecryptionError(tx: tx)
            }

            logger.info("Local identity keys matched remote - no further action.")
        }
        .catch(on: schedulers.global()) { error in
            guard let interrupt = error as? Interrupts else {
                logger.error("Error during validation! \(error)")
                return
            }

            if interrupt.shouldResultInUnlink {
                logger.warn("Marking as deregistered.")
                self.tsAccountManager.setIsDeregistered()
            }

            self.db.write { tx in
                self.clearPniMessageDecryptionError(tx: tx)
            }
        }
        .ensure(on: schedulers.sync) {
            self.isValidating.set(false)
        }
        .cauterize()
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
        typealias TSAccountManager = _LinkedDevicePniKeyManagerImpl_TSAccountManager_Shim
    }

    enum Wrappers {
        typealias MessageProcessor = _LinkedDevicePniKeyManagerImpl_MessageProcessor_Wrapper
        typealias TSAccountManager = _LinkedDevicePniKeyManagerImpl_TSAccountManager_Wrapper
    }
}

// MARK: MessageProcessor

protocol _LinkedDevicePniKeyManagerImpl_MessageProcessor_Shim {
    func fetchingAndProcessingCompletePromise() -> Promise<Void>
}

class _LinkedDevicePniKeyManagerImpl_MessageProcessor_Wrapper: _LinkedDevicePniKeyManagerImpl_MessageProcessor_Shim {
    private let messageProcessor: MessageProcessor

    public init(_ messageProcessor: MessageProcessor) {
        self.messageProcessor = messageProcessor
    }

    public func fetchingAndProcessingCompletePromise() -> Promise<Void> {
        messageProcessor.fetchingAndProcessingCompletePromise()
    }
}

// MARK: TSAccountManager

protocol _LinkedDevicePniKeyManagerImpl_TSAccountManager_Shim {
    func localIdentifiers(tx: DBReadTransaction) -> LocalIdentifiers?
    func isPrimaryDevice(tx: DBReadTransaction) -> Bool
    func setIsDeregistered()
}

class _LinkedDevicePniKeyManagerImpl_TSAccountManager_Wrapper: _LinkedDevicePniKeyManagerImpl_TSAccountManager_Shim {
    private let tsAccountManager: TSAccountManager

    init(_ tsAccountManager: TSAccountManager) {
        self.tsAccountManager = tsAccountManager
    }

    func localIdentifiers(tx: DBReadTransaction) -> LocalIdentifiers? {
        return tsAccountManager.localIdentifiers(transaction: SDSDB.shimOnlyBridge(tx))
    }

    func isPrimaryDevice(tx: DBReadTransaction) -> Bool {
        return tsAccountManager.isPrimaryDevice(transaction: SDSDB.shimOnlyBridge(tx))
    }

    func setIsDeregistered() {
        tsAccountManager.isDeregistered = true
    }
}
