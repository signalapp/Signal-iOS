//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

/// It is possible that a user does not know their own PNI. However, in order to
/// be PNP-compatible, a user's PNI and PNI identity key must be synced between
/// the client and service. This manager handles syncing the PNI and related
/// keys as necessary.
public protocol LearnMyOwnPniManager {
    func learnMyOwnPniIfNecessary() -> Promise<Void>
}

final class LearnMyOwnPniManagerImpl: LearnMyOwnPniManager {
    fileprivate static let logger = PrefixedLogger(prefix: "LMOPMI")
    private var logger: PrefixedLogger { Self.logger }

    private let accountServiceClient: Shims.AccountServiceClient
    private let registrationStateChangeManager: RegistrationStateChangeManager
    private let tsAccountManager: TSAccountManager

    private let db: any DB
    private let schedulers: Schedulers

    init(
        accountServiceClient: Shims.AccountServiceClient,
        db: any DB,
        registrationStateChangeManager: RegistrationStateChangeManager,
        schedulers: Schedulers,
        tsAccountManager: TSAccountManager
    ) {
        self.accountServiceClient = accountServiceClient
        self.registrationStateChangeManager = registrationStateChangeManager
        self.tsAccountManager = tsAccountManager

        self.db = db
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
        return learnMyOwnPniChainedPromise.enqueue {
            return self.db.read { tx in
                self._learnMyOwnPniIfNecessary(tx: tx)
            }
        }
    }

    private func _learnMyOwnPniIfNecessary(tx: DBReadTransaction) -> Promise<Void> {
        guard tsAccountManager.registrationState(tx: tx).isPrimaryDevice ?? true else {
            return .value(())
        }

        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
            logger.warn("Skipping PNI learning, no local identifiers!")
            return .value(())
        }

        return firstly(on: schedulers.sync) { () -> Promise<Void> in
            return self.fetchMyPniIfNecessary(localIdentifiers: localIdentifiers)
        }.recover(on: schedulers.sync) { error in
            self.logger.error("Error learning local PNI! \(error)")
            throw error
        }
    }

    private func fetchMyPniIfNecessary(localIdentifiers: LocalIdentifiers) -> Promise<Void> {
        if localIdentifiers.pni != nil {
            return .value(())
        }

        return firstly(on: self.schedulers.sync) { () -> Promise<WhoAmIRequestFactory.Responses.WhoAmI> in
            self.accountServiceClient.getAccountWhoAmI()
        }.map(on: schedulers.global()) { whoAmI in
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
