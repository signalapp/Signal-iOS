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

    @objc(initForIdentity:)
    public init(for identity: OWSIdentity) {
        self.identity = identity
    }

    public override func run() {
        Logger.debug("")

        guard tsAccountManager.isRegistered else {
            Logger.debug("skipping - not registered")
            self.reportCancelled()
            return
        }

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
            let signalProtocolStore = self.signalProtocolStore(for: self.identity)

            guard preKeysCount < kEphemeralPreKeysMinimumCount ||
                    signalProtocolStore.signedPreKeyStore.currentSignedPrekeyId() == nil else {
                Logger.debug("Available \(self.identity) keys sufficient: \(preKeysCount)")
                return Promise.value(())
            }

            let signedPreKeyRecord = signalProtocolStore.signedPreKeyStore.generateRandomSignedRecord()
            let preKeyRecords: [PreKeyRecord] = signalProtocolStore.preKeyStore.generatePreKeyRecords()

            self.databaseStorage.write { transaction in
                signalProtocolStore.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                                        signedPreKeyRecord: signedPreKeyRecord,
                                                                        transaction: transaction)
                signalProtocolStore.preKeyStore.storePreKeyRecords(preKeyRecords, transaction: transaction)
            }

            return firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
                self.accountServiceClient.setPreKeys(for: self.identity,
                                                     identityKey: identityKeyPair.publicKey,
                                                     signedPreKeyRecord: signedPreKeyRecord,
                                                     preKeyRecords: preKeyRecords)
            }.done(on: DispatchQueue.global()) { () in
                signedPreKeyRecord.markAsAcceptedByService()

                self.databaseStorage.write { transaction in
                    signalProtocolStore.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                                            signedPreKeyRecord: signedPreKeyRecord,
                                                                            transaction: transaction)
                    signalProtocolStore.signedPreKeyStore.setCurrentSignedPrekeyId(signedPreKeyRecord.id,
                                                                                   transaction: transaction)
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
        guard !error.isNetworkConnectivityFailure else {
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
