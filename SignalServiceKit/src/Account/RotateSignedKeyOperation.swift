//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

private let kSignedPreKeyRotationTime: TimeInterval = 2 * kDayInterval

@objc(SSKRotateSignedPreKeyOperation)
public class RotateSignedPreKeyOperation: OWSOperation {
    private let identity: OWSIdentity
    private let shouldSkipIfRecent: Bool

    @objc(initForIdentity:shouldSkipIfRecent:)
    public init(for identity: OWSIdentity, shouldSkipIfRecent: Bool) {
        self.identity = identity
        self.shouldSkipIfRecent = shouldSkipIfRecent
    }

    public override func run() {
        Logger.debug("")

        guard tsAccountManager.isRegistered else {
            Logger.debug("skipping - not registered")
            self.reportCancelled()
            return
        }

        guard identityManager.identityKeyPair(for: identity) != nil else {
            Logger.debug("skipping - no \(identity) identity key")
            self.reportCancelled()
            return
        }

        let signalProtocolStore = self.signalProtocolStore(for: identity)

        if shouldSkipIfRecent,
           let currentSignedPreKey = signalProtocolStore.signedPreKeyStore.currentSignedPreKey(),
           abs(currentSignedPreKey.generatedAt.timeIntervalSinceNow) < kSignedPreKeyRotationTime {
            self.reportCancelled()
            return
        }

        let signedPreKeyRecord: SignedPreKeyRecord = signalProtocolStore.signedPreKeyStore.generateRandomSignedRecord()

        firstly(on: .global()) { () -> Promise<Void> in
            self.messageProcessor.fetchingAndProcessingCompletePromise()
        }.then(on: .global()) { () -> Promise<Void> in
            self.databaseStorage.write { transaction in
                signalProtocolStore.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                                        signedPreKeyRecord: signedPreKeyRecord,
                                                                        transaction: transaction)
            }
            return self.accountServiceClient.setSignedPreKey(signedPreKeyRecord, for: self.identity)
        }.done(on: .global()) { () in
            Logger.info("Successfully uploaded \(self.identity) signed PreKey")
            signedPreKeyRecord.markAsAcceptedByService()
            self.databaseStorage.write { transaction in
                signalProtocolStore.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                                        signedPreKeyRecord: signedPreKeyRecord,
                                                                        transaction: transaction)
                signalProtocolStore.signedPreKeyStore.setCurrentSignedPrekeyId(signedPreKeyRecord.id,
                                                                               transaction: transaction)
                signalProtocolStore.signedPreKeyStore.cullSignedPreKeyRecords(transaction: transaction)
                signalProtocolStore.signedPreKeyStore.clearPrekeyUpdateFailureCount(transaction: transaction)
            }

            Logger.info("done")
            self.reportSuccess()
        }.catch(on: .global()) { error in
            self.reportError(withUndefinedRetry: error)
        }
    }

    override public func didFail(error: Error) {
        guard !error.isNetworkConnectivityFailure else {
            Logger.debug("don't report SPK rotation failure w/ network error")
            return
        }
        guard let statusCode = error.httpStatusCode else {
            Logger.debug("don't report SPK rotation failure w/ non NetworkManager error: \(error)")
            return
        }
        guard statusCode >= 400 && statusCode <= 599 else {
            Logger.debug("don't report SPK rotation failure w/ non application error")
            return
        }

        let signalProtocolStore = self.signalProtocolStore(for: identity)
        self.databaseStorage.write { transaction in
            signalProtocolStore.signedPreKeyStore.incrementPrekeyUpdateFailureCount(transaction: transaction)
        }
    }
}
