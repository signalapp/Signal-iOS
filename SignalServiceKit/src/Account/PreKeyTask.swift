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

        internal static let PqPreKeysMinimumCount: UInt = 10

        // Signed prekeys should be rotated every at least every 2 days
        internal static let SignedPreKeyRotationTime: TimeInterval = 2 * kDayInterval

        internal static let LastResortPqPreKeyRotationTime: TimeInterval = 2 * kDayInterval
    }

    private struct CurrentState {
        let currentSignedPreKey: SignedPreKeyRecord?
        let currentLastResortPqPreKey: KyberPreKeyRecord?
        let ecPreKeyRecordCount: Int
        let pqPreKeyRecordCount: Int
    }

    private class Update {
        var signedPreKey: SignedPreKeyRecord?
        var preKeyRecords: [PreKeyRecord]?
        var lastResortPreKey: KyberPreKeyRecord?
        var pqPreKeyRecords: [KyberPreKeyRecord]?

        func isEmpty() -> Bool {
            if
                preKeyRecords == nil,
                signedPreKey == nil,
                lastResortPreKey == nil,
                pqPreKeyRecords == nil
            {
                return true
            }
            return false
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
    private let kyberPreKeyStore: SignalKyberPreKeyStore

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
        self.kyberPreKeyStore = protocolStore.kyberPreKeyStore

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

            return firstly(on: globalQueue()) { () -> Promise<(ecCount: Int, pqCount: Int)> in
                if self.forceRefresh || self.allowCreate {
                    // Return a no-op since the prekeys will be refreshed regardless of the response
                    return Promise.value((0, 0))
                } else {
                    return self.context.serviceClient.getPreKeysCount(for: self.identity)
                }
            }.then(on: globalQueue()) { (ecCount: Int, pqCount: Int) -> Promise<CurrentState> in
                let (preKey, lastResortKey) = self.context.db.read { tx in
                    let signedPreKey = self.signedPreKeyStore.currentSignedPreKey(tx: tx)
                    let lastResortKey = self.kyberPreKeyStore.getLastResortKyberPreKey(tx: tx)
                    return (signedPreKey, lastResortKey)
                }

                return Promise.value(
                    CurrentState(
                        currentSignedPreKey: preKey,
                        currentLastResortPqPreKey: lastResortKey,
                        ecPreKeyRecordCount: ecCount,
                        pqPreKeyRecordCount: pqCount
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
                    if preKeyState.ecPreKeyRecordCount < Constants.EphemeralPreKeysMinimumCount {
                        value.insert(target: target)
                    } else {
                        Logger.info("Available \(self.identity) keys sufficient: \(preKeyState.ecPreKeyRecordCount)")
                    }
                case .oneTimePqPreKey:
                    if preKeyState.pqPreKeyRecordCount < Constants.PqPreKeysMinimumCount {
                        value.insert(target: target)
                    } else {
                        Logger.info("Available \(self.identity) PQ keys sufficient: \(preKeyState.pqPreKeyRecordCount)")
                    }
                case .signedPreKey:
                    if
                        let signedPreKey = preKeyState.currentSignedPreKey,
                        case let currentDate = self.context.dateProvider(),
                        case let generatedDate = signedPreKey.generatedAt,
                        currentDate.timeIntervalSince(generatedDate) < Constants.SignedPreKeyRotationTime
                    {
                        Logger.info("Available \(self.identity) signed PreKey sufficient: \(signedPreKey.generatedAt)")
                    } else {
                        value.insert(target: target)
                    }
                case .lastResortPqPreKey:
                    if
                        let lastResortPreKey = preKeyState.currentLastResortPqPreKey,
                        case let currentDate = self.context.dateProvider(),
                        case let generatedDate = lastResortPreKey.generatedAt,
                        currentDate.timeIntervalSince(generatedDate) < Constants.LastResortPqPreKeyRotationTime
                    {
                        Logger.info("Available \(self.identity) last resort PreKey sufficient: \(lastResortPreKey.generatedAt)")
                    } else {
                        value.insert(target: target)
                    }
                }
            })
        }.then(on: globalQueue()) { (neededTargets: PreKey.Operation.Target) -> Promise<Update> in

            // Map the keys to the requested operation.  Create the necessary keys and
            // pass them along to be uploaded to the service/stored/accepted
            return try self.context.db.write { tx in
                return Promise.value(try neededTargets.targets.reduce(into: Update()) { result, target in
                    switch target {
                    case .oneTimePreKey:
                        result.preKeyRecords = self.preKeyStore.generatePreKeyRecords(tx: tx)
                    case .signedPreKey:
                        result.signedPreKey = self.signedPreKeyStore.generateRandomSignedRecord()
                    case .oneTimePqPreKey:
                        result.pqPreKeyRecords = try self.kyberPreKeyStore.generateKyberPreKeyRecords(
                            count: 100,
                            signedBy: identityKeyPair,
                            tx: tx
                        )
                    case .lastResortPqPreKey:
                        result.lastResortPreKey = try self.kyberPreKeyStore.generateLastResortKyberPreKey(
                            signedBy: identityKeyPair,
                            tx: tx
                        )
                    }
                })
            }
        }.then(on: globalQueue()) { (update: Update) -> Promise<Void> in

            // If there is nothing to update, skip this step.
            guard !update.isEmpty() else { return Promise.value(()) }

            return firstly(on: globalQueue()) { () -> Promise<Void> in
                self.context.serviceClient.setPreKeys(
                    for: self.identity,
                    identityKey: identityKeyPair.publicKey,
                    signedPreKeyRecord: update.signedPreKey,
                    preKeyRecords: update.preKeyRecords,
                    pqLastResortPreKeyRecord: update.lastResortPreKey,
                    pqPreKeyRecords: update.pqPreKeyRecords,
                    auth: self.auth
                )
            }.done(on: globalQueue()) { () in

                try self.context.db.write { tx in
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

                    if let lastResortPreKey = update.lastResortPreKey {

                        try self.kyberPreKeyStore.storeLastResortPreKeyAndMarkAsCurrent(
                            record: lastResortPreKey,
                            tx: tx
                        )

                        // TODO(PQXDH): Mark the keys as accepted, and implement cleanup
                        // mark as accepted?
                        // self.signedPreKeyStore.cullSignedPreKeyRecords(tx: tx)
                        // self.signedPreKeyStore.clearPreKeyUpdateFailureCount(tx: tx)
                    }

                    if let newPreKeyRecords = update.preKeyRecords {

                        // Store newly added prekeys
                        self.preKeyStore.storePreKeyRecords(newPreKeyRecords, tx: tx)

                        // OneTime PreKey Cleanup
                        self.preKeyStore.cullPreKeyRecords(tx: tx)
                    }

                    if let pqPreKeyRecords = update.pqPreKeyRecords {
                        try self.kyberPreKeyStore.storeKyberPreKeyRecords(records: pqPreKeyRecords, tx: tx)

                        // TODO(PQXDH): Mark the keys as accepted, and implement cleanup
                        // self.preKeyStore.cullPreKeyRecords(tx: tx)
                    }
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

            if update.lastResortPreKey != nil {
                // signedPreKeyStore.incrementPreKeyUpdateFailureCount(tx: tx)
            }
        }
    }
}
