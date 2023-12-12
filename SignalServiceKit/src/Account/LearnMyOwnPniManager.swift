//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit

/// It is possible that a user does not know their own PNI. However, in order to
/// be PNP-compatible, a user's PNI and PNI identity key must be synced between
/// the client and service. This manager handles syncing the PNI and related
/// keys as necessary.
public protocol LearnMyOwnPniManager {
    func learnMyOwnPniIfNecessary() -> Promise<Void>
}

final class LearnMyOwnPniManagerImpl: LearnMyOwnPniManager {
    private enum StoreConstants {
        static let collectionName = "LearnMyOwnPniManagerImpl"
        static let hasCompletedPniLearning = "hasCompletedPniLearning"
    }

    fileprivate static let logger = PrefixedLogger(prefix: "LMOPMI")
    private var logger: PrefixedLogger { Self.logger }

    private let accountServiceClient: Shims.AccountServiceClient
    private let pniIdentityKeyChecker: PniIdentityKeyChecker
    private let preKeyManager: PreKeyManager
    private let registrationStateChangeManager: RegistrationStateChangeManager
    private let tsAccountManager: TSAccountManager

    private let db: DB
    private let keyValueStore: KeyValueStore
    private let schedulers: Schedulers

    init(
        accountServiceClient: Shims.AccountServiceClient,
        db: DB,
        keyValueStoreFactory: KeyValueStoreFactory,
        pniIdentityKeyChecker: PniIdentityKeyChecker,
        preKeyManager: PreKeyManager,
        registrationStateChangeManager: RegistrationStateChangeManager,
        schedulers: Schedulers,
        tsAccountManager: TSAccountManager
    ) {
        self.accountServiceClient = accountServiceClient
        self.pniIdentityKeyChecker = pniIdentityKeyChecker
        self.preKeyManager = preKeyManager
        self.registrationStateChangeManager = registrationStateChangeManager
        self.tsAccountManager = tsAccountManager

        self.db = db
        self.keyValueStore = keyValueStoreFactory.keyValueStore(collection: StoreConstants.collectionName)
        self.schedulers = schedulers
    }

    /// Wrap everything in a chained promise so we don't issue requests
    /// concurrently and end up with broken state.
    ///
    /// Before making requests (but after getting dequeued) each call will
    /// check local state to see if things corrected while enqueued, so
    /// enqueuing is cheap.
    ///
    /// - Note
    /// This only ever gets called in one place, on app launch, so this safety
    /// is overkill. But it doesn't hurt to have.
    private lazy var learnMyOwnPniChainedPromise = ChainedPromise(scheduler: schedulers.main)

    func learnMyOwnPniIfNecessary() -> Promise<Void> {
        return learnMyOwnPniChainedPromise.enqueue { [weak self] in
            guard let self else {
                return .init(error: OWSAssertionError("unretained self"))
            }

            return self.db.read { tx in
                self._learnMyOwnPniIfNecessary(tx: tx)
            }
        }
    }

    private func _learnMyOwnPniIfNecessary(tx: DBReadTransaction) -> Promise<Void> {
        let hasCompletedPniLearningAlready = keyValueStore.getBool(
            StoreConstants.hasCompletedPniLearning,
            defaultValue: false,
            transaction: tx
        )

        guard !hasCompletedPniLearningAlready else {
            logger.info("Skipping PNI learning, already completed.")
            return .value(())
        }

        guard tsAccountManager.registrationState(tx: tx).isPrimaryDevice ?? true else {
            logger.info("Skipping PNI learning on linked device.")
            return .value(())
        }

        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
            logger.warn("Skipping PNI learning, no local identifiers!")
            return .value(())
        }

        return firstly(on: schedulers.sync) { () -> Promise<Pni> in
            return self.fetchMyPniIfNecessary(localIdentifiers: localIdentifiers)
        }.then(on: schedulers.global()) { localPni -> Promise<Void> in
            return self.db.read { tx in
                return self.createPniKeysIfNecessary(
                    localPni: localPni,
                    tx: tx
                )
            }
        }.recover(on: schedulers.sync) { error in
            self.logger.error("Error learning local PNI! \(error)")
            throw error
        }
    }

    private func fetchMyPniIfNecessary(localIdentifiers: LocalIdentifiers) -> Promise<Pni> {
        if let localPni = localIdentifiers.pni {
            logger.info("Skipping PNI fetch, PNI already available.")
            return .value(localPni)
        }

        return firstly(on: self.schedulers.sync) { () -> Promise<WhoAmIRequestFactory.Responses.WhoAmI> in
            self.accountServiceClient.getAccountWhoAmI()
        }.map(on: schedulers.global()) { whoAmI -> Pni in
            let remoteE164 = whoAmI.e164
            let remoteAci = whoAmI.aci
            let remotePni = whoAmI.pni

            self.logger.info("Successfully fetched PNI: \(remotePni)")

            guard
                localIdentifiers.aci == remoteAci,
                localIdentifiers.contains(phoneNumber: remoteE164)
            else {
                throw OWSGenericError(
                    "Remote ACI \(remoteAci) and e164 \(remoteE164) were not present in local identifiers, skipping PNI save."
                )
            }

            self.db.write { tx in
                self.registrationStateChangeManager.didUpdateLocalPhoneNumber(
                    remoteE164,
                    aci: remoteAci,
                    pni: remotePni,
                    tx: tx
                )
            }

            return remotePni
        }
    }

    /// Even if we know our own PNI, it's possible that the identity key for
    /// our PNI identity is out of date or was never uploaded to the service.
    /// This method ensures the local PNI identity key matches that on the
    /// service.
    private func createPniKeysIfNecessary(
        localPni: Pni,
        tx syncTx: DBReadTransaction
    ) -> Promise<Void> {
        return self.pniIdentityKeyChecker.serverHasSameKeyAsLocal(
            localPni: localPni,
            tx: syncTx
        )
        .then(on: schedulers.global()) { matched -> Promise<Void> in
            if matched {
                self.db.write { tx in
                    self.keyValueStore.setBool(
                        true,
                        key: StoreConstants.hasCompletedPniLearning,
                        transaction: tx
                    )
                }

                return .value(())
            }

            return Promise.wrapAsync {
                return try await self.preKeyManager.createOrRotatePNIPreKeys(auth: .implicit()).value
            }.map(on: self.schedulers.global()) {
                self.logger.info("Successfully created PNI keys!")

                self.db.write { tx in
                    self.keyValueStore.setBool(
                        true,
                        key: StoreConstants.hasCompletedPniLearning,
                        transaction: tx
                    )
                }
            }.catch(on: self.schedulers.sync) { error in
                self.logger.error("Error creating and uploading PNI keys: \(error)!")
            }
        }
    }
}

// MARK: - Dependencies

extension LearnMyOwnPniManagerImpl {
    enum Shims {
        typealias AccountServiceClient = _LearnMyOwnPniManagerImpl_AccountServiceClient_Shim
    }

    enum Wrappers {
        typealias AccountServiceClient = _LearnMyOwnPniManagerImpl_AccountServiceClient_Wrapper
    }
}

// MARK: AccountServiceClient

protocol _LearnMyOwnPniManagerImpl_AccountServiceClient_Shim {
    func getAccountWhoAmI() -> Promise<WhoAmIRequestFactory.Responses.WhoAmI>
}

class _LearnMyOwnPniManagerImpl_AccountServiceClient_Wrapper: _LearnMyOwnPniManagerImpl_AccountServiceClient_Shim {
    private let accountServiceClient: AccountServiceClient

    init(_ accountServiceClient: AccountServiceClient) {
        self.accountServiceClient = accountServiceClient
    }

    public func getAccountWhoAmI() -> Promise<WhoAmIRequestFactory.Responses.WhoAmI> {
        accountServiceClient.getAccountWhoAmI()
    }
}
