//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// We generate 100 one-time prekeys at a time.  We should replenish
// whenever ~2/3 of them have been consumed.
private let kEphemeralPreKeysMinimumCount: UInt = 35

@objc(SSKRefreshPreKeysOperation)
public class RefreshPreKeysOperation: OWSOperation {
    private let identity: OWSIdentity
    private let shouldRefreshSignedPreKey: Bool

    /// Create an operation for the given identity type, and optionally a
    /// signed pre-key already in use.
    ///
    /// If no signed pre-key is given, one will be generated and stored as part
    /// of this operation. Any existing signed pre-keys should already be
    /// accepted by the service and persisted.
    @objc(initForIdentity:shouldRefreshSignedPreKey:)
    public init(
        for identity: OWSIdentity,
        shouldRefreshSignedPreKey: Bool
    ) {
        self.identity = identity
        self.shouldRefreshSignedPreKey = shouldRefreshSignedPreKey
    }

    public override func run() {
        Logger.debug("")

        guard tsAccountManager.isRegistered else {
            Logger.debug("skipping - not registered")
            self.reportCancelled()
            return
        }

        // TODO: [CNPNI] Is it possible that this key will change during message processing? Should this check be later?
        guard let identityKeyPair = identityManager.identityKeyPair(for: identity) else {
            Logger.debug("skipping - no \(self.identity) identity key")
            owsAssertDebug(identity != .aci)
            self.reportCancelled()
            return
        }

        firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
            self.messageProcessor.fetchingAndProcessingCompletePromise()
        }.then(on: DispatchQueue.global()) { () -> Promise<Int> in
            self.accountServiceClient.getPreKeysCount(for: self.identity)
        }.then(on: DispatchQueue.global()) { (preKeysCount: Int) -> Promise<Void> in
            Logger.info("\(self.identity) preKeysCount: \(preKeysCount)")

            if !self.shouldRefreshSignedPreKey {
                // At the time of writing, if we're only refreshing one-time
                // pre-keys that means we have (external to this operation)
                // rotated our signed pre-key and therefore should have no
                // one-time pre-keys left. If you hit this assertion in the
                // future, this may no longer be true.
                owsAssertDebug(preKeysCount == 0)
            }

            let signalProtocolStore = self.signalProtocolStore(for: self.identity)

            guard preKeysCount < kEphemeralPreKeysMinimumCount ||
                    signalProtocolStore.signedPreKeyStore.currentSignedPrekeyId() == nil else {
                Logger.debug("Available \(self.identity) keys sufficient: \(preKeysCount)")
                return Promise.value(())
            }

            let newPreKeyRecords: [PreKeyRecord] = signalProtocolStore.preKeyStore.generatePreKeyRecords()

            // Store pre key records, and get a signed pre key record.
            let (signedPreKeyRecord, isNewSignedPreKey) = self.databaseStorage.write { transaction in
                signalProtocolStore.preKeyStore.storePreKeyRecords(newPreKeyRecords, transaction: transaction)

                if
                    !self.shouldRefreshSignedPreKey,
                    let currentSignedPreKey = signalProtocolStore.signedPreKeyStore.currentSignedPreKey(with: transaction)
                {
                    Logger.info("Using existing signed pre-key!")
                    return (currentSignedPreKey, false)
                } else {
                    Logger.info("Generating new signed pre-key!")

                    let newSignedPreKeyRecord = signalProtocolStore.signedPreKeyStore.generateRandomSignedRecord()

                    signalProtocolStore.signedPreKeyStore.storeSignedPreKey(
                        newSignedPreKeyRecord.id,
                        signedPreKeyRecord: newSignedPreKeyRecord,
                        transaction: transaction
                    )

                    return (newSignedPreKeyRecord, true)
                }
            }

            return firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
                self.serviceClient.registerPreKeys(
                    for: self.identity,
                    identityKey: identityKeyPair.publicKey,
                    signedPreKeyRecord: signedPreKeyRecord,
                    preKeyRecords: newPreKeyRecords,
                    auth: .implicit()
                )
            }.done(on: DispatchQueue.global()) { () in
                self.databaseStorage.write { transaction in
                    if isNewSignedPreKey {
                        signalProtocolStore.signedPreKeyStore.storeSignedPreKeyAsAcceptedAndCurrent(
                            signedPreKeyId: signedPreKeyRecord.id,
                            signedPreKeyRecord: signedPreKeyRecord,
                            transaction: transaction
                        )
                    }

                    signalProtocolStore.signedPreKeyStore.cullSignedPreKeyRecords(transaction: transaction)
                    signalProtocolStore.signedPreKeyStore.clearPrekeyUpdateFailureCount(transaction: transaction)

                    signalProtocolStore.preKeyStore.cullPreKeyRecords(transaction: transaction)
                }
            }
        }.done(on: DispatchQueue.global()) {
            Logger.info("done")
            self.reportSuccess()
        }.catch(on: DispatchQueue.global()) { error in
            self.reportError(withUndefinedRetry: error)
        }
    }

    public override func didSucceed() {
        TSPreKeyManager.refreshPreKeysDidSucceed()
    }

    override public func didFail(error: Error) {
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

        let signalProtocolStore = self.signalProtocolStore(for: identity)
        self.databaseStorage.write { transaction in
            signalProtocolStore.signedPreKeyStore.incrementPrekeyUpdateFailureCount(transaction: transaction)
        }
    }
}
