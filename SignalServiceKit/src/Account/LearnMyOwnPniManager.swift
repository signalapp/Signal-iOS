//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Curve25519Kit
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
    private let identityManager: Shims.IdentityManager
    private let preKeyManager: PreKeyManager
    private let profileFetcher: Shims.ProfileFetcher
    private let tsAccountManager: Shims.TSAccountManager

    private let db: DB
    private let keyValueStore: KeyValueStore
    private let schedulers: Schedulers

    init(
        accountServiceClient: Shims.AccountServiceClient,
        db: DB,
        identityManager: Shims.IdentityManager,
        keyValueStoreFactory: KeyValueStoreFactory,
        preKeyManager: PreKeyManager,
        profileFetcher: Shims.ProfileFetcher,
        schedulers: Schedulers,
        tsAccountManager: Shims.TSAccountManager
    ) {
        self.accountServiceClient = accountServiceClient
        self.identityManager = identityManager
        self.preKeyManager = preKeyManager
        self.profileFetcher = profileFetcher
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

        guard tsAccountManager.isPrimaryDevice(tx: tx) else {
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
            let localPniIdentityPublicKeyData: Data? = self.db.read { tx in
                self.identityManager.pniIdentityPublicKeyData(tx: tx)
            }

            return self.createPniKeysIfNecessary(
                localPni: localPni,
                localPniIdentityPublicKeyData: localPniIdentityPublicKeyData
            )
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
            let remoteAci = Aci(fromUUID: whoAmI.aci)
            let remotePni = Pni(fromUUID: whoAmI.pni)

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
                self.tsAccountManager.updateLocalIdentifiers(
                    e164: remoteE164,
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
        localPniIdentityPublicKeyData: Data?
    ) -> Promise<Void> {
        return firstly(on: schedulers.sync) { () -> Guarantee<Bool> in
            // First, check if we need to update our PNI keys on the service. We
            // should do so if we are missing our local PNI identity key, if the
            // service is missing our PNI identity key, or if the key on the
            // service does not match our local key.

            guard let localPniIdentityPublicKeyData else {
                self.logger.info("No local PNI identity key.")
                return .value(true)
            }

            return firstly(on: self.schedulers.sync) { () -> Promise<Data?> in
                return self.profileFetcher.fetchPniIdentityPublicKey(localPni: localPni)
            }.map(on: self.schedulers.global()) { remotePniIdentityPublicKeyData -> Bool in
                if
                    let remotePniIdentityPublicKeyData,
                    remotePniIdentityPublicKeyData == localPniIdentityPublicKeyData
                {
                    self.logger.info("Local PNI identity key matches server.")

                    self.db.write { tx in
                        self.keyValueStore.setBool(
                            true,
                            key: StoreConstants.hasCompletedPniLearning,
                            transaction: tx
                        )
                    }

                    return false
                }

                self.logger.warn("Local PNI identity key does not match server!")
                return true
            }.recover(on: self.schedulers.sync) { error -> Guarantee<Bool> in
                self.logger.error("Error checking remote identity key: \(error)!")
                return .value(false)
            }
        }.then(on: schedulers.sync) { (needsUpdate: Bool) -> Promise<Void> in
            guard needsUpdate else { return .value(()) }

            return firstly(on: self.schedulers.sync) { () -> Promise<Void> in
                return self.preKeyManager.createOrRotatePNIPreKeys(auth: .implicit())
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
        typealias IdentityManager = _LearnMyOwnPniManagerImpl_IdentityManager_Shim
        typealias ProfileFetcher = _LearnMyOwnPniManagerImpl_ProfileFetcher_Shim
        typealias TSAccountManager = _LearnMyOwnPniManagerImpl_TSAccountManager_Shim
    }

    enum Wrappers {
        typealias AccountServiceClient = _LearnMyOwnPniManagerImpl_AccountServiceClient_Wrapper
        typealias IdentityManager = _LearnMyOwnPniManagerImpl_IdentityManager_Wrapper
        typealias ProfileFetcher = _LearnMyOwnPniManagerImpl_ProfileFetcher_Wrapper
        typealias TSAccountManager = _LearnMyOwnPniManagerImpl_TSAccountManager_Wrapper
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

// MARK: IdentityManager

protocol _LearnMyOwnPniManagerImpl_IdentityManager_Shim {
    func pniIdentityPublicKeyData(tx: DBReadTransaction) -> Data?
}

class _LearnMyOwnPniManagerImpl_IdentityManager_Wrapper: _LearnMyOwnPniManagerImpl_IdentityManager_Shim {
    private let identityManager: OWSIdentityManager

    init(_ identityManager: OWSIdentityManager) {
        self.identityManager = identityManager
    }

    func pniIdentityPublicKeyData(tx: DBReadTransaction) -> Data? {
        return identityManager.identityKeyPair(
            for: .pni,
            transaction: SDSDB.shimOnlyBridge(tx)
        )?.publicKey
    }
}

// MARK: ProfileFetcher

protocol _LearnMyOwnPniManagerImpl_ProfileFetcher_Shim {
    func fetchPniIdentityPublicKey(localPni: Pni) -> Promise<Data?>
}

class _LearnMyOwnPniManagerImpl_ProfileFetcher_Wrapper: _LearnMyOwnPniManagerImpl_ProfileFetcher_Shim {
    private let schedulers: Schedulers

    init(schedulers: Schedulers) {
        self.schedulers = schedulers
    }

    func fetchPniIdentityPublicKey(localPni: Pni) -> Promise<Data?> {
        let logger = LearnMyOwnPniManagerImpl.logger

        return ProfileFetcherJob.fetchProfilePromise(
            serviceId: localPni,
            mainAppOnly: true,
            ignoreThrottling: true,
            shouldUpdateStore: false
        ).map(on: schedulers.sync) { fetchedProfile -> Data in
            return fetchedProfile.profile.identityKey
        }.recover(on: schedulers.sync) { error throws -> Promise<Data?> in
            switch error {
            case ParamParser.ParseError.missingField("identityKey"):
                logger.info("Server does not have a PNI identity key.")
                return .value(nil)
            case ProfileFetchError.notMainApp:
                throw OWSGenericError("Could not check remote identity key outside main app.")
            default:
                throw error
            }
        }
    }
}

// MARK: TSAccountManager

protocol _LearnMyOwnPniManagerImpl_TSAccountManager_Shim {
    func isPrimaryDevice(tx: DBReadTransaction) -> Bool
    func localIdentifiers(tx: DBReadTransaction) -> LocalIdentifiers?
    func updateLocalIdentifiers(e164: E164, aci: Aci, pni: Pni, tx: DBWriteTransaction)
}

class _LearnMyOwnPniManagerImpl_TSAccountManager_Wrapper: _LearnMyOwnPniManagerImpl_TSAccountManager_Shim {
    private let tsAccountManager: TSAccountManager

    init(_ tsAccountManager: TSAccountManager) {
        self.tsAccountManager = tsAccountManager
    }

    func isPrimaryDevice(tx: DBReadTransaction) -> Bool {
        return tsAccountManager.isPrimaryDevice(transaction: SDSDB.shimOnlyBridge(tx))
    }

    func localIdentifiers(tx: DBReadTransaction) -> LocalIdentifiers? {
        return tsAccountManager.localIdentifiers(transaction: SDSDB.shimOnlyBridge(tx))
    }

    func updateLocalIdentifiers(e164: E164, aci: Aci, pni: Pni, tx: DBWriteTransaction) {
        tsAccountManager.updateLocalPhoneNumber(
            E164ObjC(e164),
            aci: AciObjC(aci),
            pni: PniObjC(pni),
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }
}
