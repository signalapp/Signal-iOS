//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class PreKeyTask {

    enum Constants {
        // We generate 100 one-time prekeys at a time.
        // Replenish whenever 10 or less remain
        internal static let EphemeralPreKeysMinimumCount: UInt = 10

        // Signed prekeys should be rotated every at least every 2 days
        internal static let SignedPreKeyRotationTime: TimeInterval = 2 * kDayInterval
    }

    private struct CurrentState {
        let currentSignedPreKey: SignedPreKeyRecord?
        let preKeyRecordCount: Int
    }

    private class Update {
        var signedPreKey: SignedPreKeyRecord?
        var preKeyRecords: [PreKeyRecord]?

        func isEmpty() -> Bool {
            return (signedPreKey == nil && preKeyRecords == nil)
        }
    }

    public enum Error: Swift.Error {
        case noIdentityKey
        case notRegistered
        case cancelled
    }

    public struct Context {
        let accountManager: PreKey.Shims.AccountManager
        let dateProvider: DateProvider
        let db: DB
        let identityManager: PreKey.Shims.IdentityManager
        let messageProcessor: PreKey.Shims.MessageProcessor
        let protocolStoreManager: SignalProtocolStoreManager
        let schedulers: Schedulers
        let serviceClient: AccountServiceClient
    }

    private let context: Context
    private let identity: OWSIdentity
    private let auth: ChatServiceAuth

    private let requestedTargets: PreKey.Operation.Target
    private let forceRefresh: Bool
    private let allowCreate: Bool

    private let preKeyStore: SignalPreKeyStore
    private let signedPreKeyStore: SignalSignedPreKeyStore

    public init(
        for identity: OWSIdentity,
        action: PreKey.Operation.Action,
        auth: ChatServiceAuth,
        context: Context
    ) {
        self.identity = identity
        self.auth = auth
        self.context = context

        let protocolStore = context.protocolStoreManager.signalProtocolStore(for: identity)

        self.preKeyStore = protocolStore.preKeyStore
        self.signedPreKeyStore = protocolStore.signedPreKeyStore

        switch action {
        case .create(let targets):
            forceRefresh = true
            allowCreate = true
            requestedTargets = targets
        case .refresh(let targets, let forceRefresh):
            self.forceRefresh = forceRefresh
            allowCreate = false
            requestedTargets = targets
        }
    }

    /// PreKeyTask is broken down into the following steps
    /// 1. Fetch the identity key.  If this is a create operation, create the key, otherwise error if missing
    /// 2. If registered and not a create operation, check that message processing is idle before continuing
    /// 3. Check the server for the number of remaining PreKeys (skip on create/force refresh)
    /// 4. Run any logic to determine what requested operations are really necessary
    /// 5. Generate the necessary keys for the resulting operations
    /// 6. Upload these new keys to the server
    /// 7. Store the new keys and run any cleanup logic
    public func runPreKeyTask() -> Promise<Void> {

        let globalQueue = { self.context.schedulers.global() }

        // Get the identity key
        var identityKeyPair = context.identityManager.identityKeyPair(for: identity)
        if identityKeyPair == nil {
            if allowCreate {
                let isPrimaryDevice = self.context.db.read { tx in
                    self.context.accountManager.isPrimaryDevice(tx: tx)
                }
                if isPrimaryDevice {
                    identityKeyPair = context.identityManager.generateNewIdentityKeyPair()

                    context.db.write { tx in
                        context.identityManager.store(
                            keyPair: identityKeyPair,
                            for: identity,
                            tx: tx)
                    }
                } else {
                    Logger.warn("Identity key missing from linked device")
                }
            } else {
                Logger.warn("cannot create \(identity) pre-keys; missing identity key")
            }
        }
        guard let identityKeyPair else {
            return Promise(error: Error.noIdentityKey)
        }

        return firstly(on: globalQueue()) { () -> Promise<Void> in

            let isRegisteredAndReady = self.context.db.read { tx in
                return self.context.accountManager.isRegisteredAndReady(tx: tx)
            }

            // Check the system is idle before attempting to refresh any prekey operations
            if !isRegisteredAndReady {
                // if not ready or registered, and doing a create, bypass this
                // check since the system should be idle already
                if self.allowCreate {
                    return Promise.value(())
                } else {
                    // Return if things aren't ready.  Note that the keys will have been
                    // created at this point.
                    Logger.debug("skipping - not registered")
                    return Promise(error: Error.notRegistered)
                }
            } else {
                return self.context.messageProcessor.fetchingAndProcessingCompletePromise()
            }
        }.then(on: globalQueue()) { () -> Promise<CurrentState> in

            return firstly(on: self.context.schedulers.global()) { () -> Promise<Int> in
                if self.forceRefresh || self.allowCreate {
                    // Return a no-op since the prekeys will be refreshed regardless of the response
                    return Promise.value(0)
                } else {
                    return self.context.serviceClient.getPreKeysCount(for: self.identity)
                }
            }.then(on: self.context.schedulers.global()) { (preKeysCount: Int) -> Promise<CurrentState> in
                let preKey = self.context.db.read { tx in
                    return self.signedPreKeyStore.currentSignedPreKey(tx: tx)
                }

                return Promise.value(
                    CurrentState(
                        currentSignedPreKey: preKey,
                        preKeyRecordCount: preKeysCount
                    )
                )
            }
        }.then(on: globalQueue()) {(preKeyState: CurrentState) -> Promise<PreKey.Operation.Target> in

            // For create/forceRefresh, skip trying to validate and
            // move to update with the current targets
            guard !(self.forceRefresh || self.allowCreate) else { return Promise.value(self.requestedTargets) }

            // Take the gathered PreKeyState information and run it through
            // logic to determine what really needs to be updated.
            return Promise.value(self.requestedTargets.targets.reduce(into: []) { value, target in
                switch target {
                case .oneTimePreKey:
                    if preKeyState.preKeyRecordCount < Constants.EphemeralPreKeysMinimumCount {
                        value.insert(target: target)
                    } else {
                        Logger.info("Available \(self.identity) keys sufficient: \(preKeyState.preKeyRecordCount)")
                    }
                case .signedPreKey:
                    if
                        let signedPreKey = preKeyState.currentSignedPreKey,
                        case let currentDate = self.context.dateProvider(),
                        case let generatedDate = signedPreKey.generatedAt,
                        currentDate.timeIntervalSince(generatedDate) < Constants.SignedPreKeyRotationTime
                    {
                        Logger.info("Available \(self.identity) prekeys sufficient: \(preKeyState.preKeyRecordCount)")
                    } else {
                        value.insert(target: target)
                    }
                }
            })
        }.then(on: globalQueue()) { (neededTargets: PreKey.Operation.Target) -> Promise<Update> in

            // Map the keys to the requested operation
            // Pass these keys along to be uploaded to the service/stored/accepted
            Promise.value(neededTargets.targets.reduce(into: Update()) { result, target in
                switch target {
                case .oneTimePreKey:
                    result.preKeyRecords = self.preKeyStore.generatePreKeyRecords()
                case .signedPreKey:
                    result.signedPreKey = self.signedPreKeyStore.generateRandomSignedRecord()
                }
            })
        }.then(on: globalQueue()) { (update: Update) -> Promise<Void> in

            // If there is nothing to update, skip this step.
            guard !update.isEmpty() else { return Promise.value(()) }

            return firstly(on: globalQueue()) { () -> Promise<Void> in
                self.context.serviceClient.setPreKeys(
                    for: self.identity,
                    identityKey: identityKeyPair.publicKey,
                    signedPreKeyRecord: update.signedPreKey,
                    preKeyRecords: update.preKeyRecords,
                    auth: self.auth
                )
            }.done(on: globalQueue()) { () in

                self.context.db.write { tx in
                    // save last-resort PQ key here as well (if created)
                    if let signedPreKeyRecord = update.signedPreKey {

                        // Mark the new Signed Prekey as accepted
                        self.signedPreKeyStore.storeSignedPreKeyAsAcceptedAndCurrent(
                            signedPreKeyId: signedPreKeyRecord.id,
                            signedPreKeyRecord: signedPreKeyRecord,
                            tx: tx
                        )

                        // cleanup (if not New key, but probably can't hurt?)
                        self.signedPreKeyStore.cullSignedPreKeyRecords(tx: tx)
                        self.signedPreKeyStore.clearPreKeyUpdateFailureCount(tx: tx)
                    }

                    if let newPreKeyRecords = update.preKeyRecords {

                        // Store newly added prekeys
                        self.preKeyStore.storePreKeyRecords(newPreKeyRecords, tx: tx)

                        // OneTime PreKey Cleanup
                        self.preKeyStore.cullPreKeyRecords(tx: tx)
                    }

                    // Same for PQ keys
                }
            }.recover(on: globalQueue()) { error in
                self.didFail(error: error, update: update)
                throw error
            }
        }
    }

    private func didFail(error: Swift.Error, update: Update) {
        guard !error.isNetworkFailureOrTimeout else {
            Logger.debug("don't report PK rotation failure w/ network error")
            return
        }
        guard let statusCode = error.httpStatusCode else {
            Logger.debug("don't report PK rotation failure w/ non NetworkManager error: \(error)")
            return
        }
        guard statusCode >= 400 && statusCode <= 599 else {
            Logger.debug("don't report PK rotation failure w/ non application error")
            return
        }

        self.context.db.write { tx in
            if update.signedPreKey != nil {
                signedPreKeyStore.incrementPreKeyUpdateFailureCount(tx: tx)
            }
        }
    }
}
